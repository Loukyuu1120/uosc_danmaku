local msg = require('mp.msg')
local utils = require("mp.utils")

------------------------------------------------
-- 并发请求管理器
------------------------------------------------
ConcurrentManager = {
    active_requests = 0,
    max_concurrent = 6, -- 最大并发数
    pending_requests = {},
    results = {},
    waiting = false
}

function ConcurrentManager:new()
    local o = {
        active_requests = 0,
        max_concurrent = 6,
        pending_requests = {},
        results = {},
        final_callback = nil,
        server_results = {}
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function ConcurrentManager:wait_all(callback)
    self.final_callback = callback
    self:check_completion()
end

function ConcurrentManager:check_completion()
    if self.active_requests == 0 and #self.pending_requests == 0 and self.final_callback then
        local callback = self.final_callback
        self.final_callback = nil
        callback()
    end
end

function ConcurrentManager:start_request(server, key, request_func)
    if self.active_requests >= self.max_concurrent then
        table.insert(self.pending_requests, {server = server, key = key, func = request_func})
        return
    end
    self:do_request(server, key, request_func)
end

function ConcurrentManager:do_request(server, key, request_func)
    self.active_requests = self.active_requests + 1
    request_func(function(result)
        if not result.server then
            result.server = server
        end
        result.index = key
        if not self.results[server] then
            self.results[server] = {}
        end
        self.results[server][key] = result

        self.active_requests = self.active_requests - 1

        if #self.pending_requests > 0 and self.active_requests < self.max_concurrent then
            local next_request = table.remove(self.pending_requests, 1)
            self:do_request(next_request.server, next_request.key, next_request.func)
        end

        self:check_completion()
    end)
end

local function extract_url(url)
    local path = url:match("^https?://[^/]+(/[^%?]*)")
    return path
end

local function generateXSignature(url, time, appid, app_accept)
    local url_path = extract_url(url)
    if not url_path then
        return nil
    end

    local dataToHash = string.format("%s%d%s%s", AES.ECB.decrypt(KEY, Base64.decode(appid)),
    time, url_path, AES.ECB.decrypt(KEY, Base64.decode(app_accept)))
    local hash = Sha256(dataToHash)
    local base64Hash = Base64.encode(hex_to_bin(hash))
    return base64Hash
end

-- 并发请求多个API服务器
local function make_concurrent_danmaku_request(servers, request_config, response_handler)
    local concurrent_manager = ConcurrentManager:new()
    for i, server in ipairs(servers) do
        local args = request_config.make_args(server, i)

        if args then
            concurrent_manager:start_request(server, i, function(cb)
                call_cmd_async(args, function(error, json)
                    local result = {
                        server = server,
                        error = error,
                        data = nil,
                        index = i
                    }

                    if not error and json then
                        local success, parsed = pcall(utils.parse_json, json)
                        if success then
                            result.data = parsed
                        else
                            result.error = "JSON解析失败"
                        end
                    end

                    cb(result)
                end)
            end)
        else
            if not concurrent_manager.results[server] then
                concurrent_manager.results[server] = {}
            end
            concurrent_manager.results[server][i] = {
                server = server,
                error = "无法生成请求参数",
                data = nil,
                index = i
            }
        end
    end

    concurrent_manager:wait_all(function()
        local results = {}
        for server, server_results in pairs(concurrent_manager.results) do
            for i, result in pairs(server_results) do
                table.insert(results, result)
            end
        end

        table.sort(results, function(a, b)
            return a.index < b.index
        end)

        response_handler(results)
    end)
end

-- 解析服务器字符串
local function parse_servers(servers_str)
    local servers = {}
    for server in servers_str:gmatch("([^,]+)") do
        server = server:gsub("^%s*(.-)%s*$", "%1")
        if server ~= "" then
            table.insert(servers, server)
        end
    end
    return servers
end

-- 获取API服务器列表
function get_api_servers()
    if options.api_servers and options.api_servers ~= "" then
        return parse_servers(options.api_servers)
    else
        return {options.api_server}
    end
end

-- 写入history.json
-- 读取episodeId获取danmaku
function set_episode_id(input, target_server, from_menu)
    from_menu = from_menu or false
    DANMAKU.source = "dandanplay"
    for url, source in pairs(DANMAKU.sources) do
        if source.from == "api_server" then
            if source.fname and file_exists(source.fname) then
                os.remove(source.fname)
            end

            if not source.from_history then
                DANMAKU.sources[url] = nil
            else
                DANMAKU.sources[url]["fname"] = nil
            end
        end
    end
    local episodeId = tonumber(input)
    write_history(episodeId, target_server)
    set_danmaku_button()
    local server = target_server
    if not server then
        for _, s in pairs(get_api_servers()) do
            fetch_danmaku(episodeId, from_menu, s)
        end
    else
        if options.load_more_danmaku and server:find("api%.dandanplay%.") then
            fetch_danmaku_all(episodeId, from_menu, server)
        else
            fetch_danmaku(episodeId, from_menu, server)
        end
    end
end

-- 回退使用额外的弹幕获取方式
function get_danmaku_fallback(query)
    local url = options.fallback_server .. "/?url=" .. query
    msg.verbose("尝试获取弹幕：" .. url)
    local temp_file = "danmaku-" .. PID .. DANMAKU.count .. ".xml"
    local danmaku_xml = utils.join_path(DANMAKU_PATH, temp_file)
    DANMAKU.count = DANMAKU.count + 1
    local arg = {
        "curl",
        "-L",
        "-s",
        "--compressed",
        "--user-agent",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0",
        "--output",
        danmaku_xml,
        url,
    }

    if options.proxy ~= "" then
        table.insert(arg, '-x')
        table.insert(arg, options.proxy)
    end

    call_cmd_async(arg, function(error)
        async_running = false
        if error then
            show_message("HTTP 请求失败，打开控制台查看详情", 5)
            msg.error(error)
            return
        end
        if file_exists(danmaku_xml) then
            save_danmaku_downloaded(query, danmaku_xml)
            load_danmaku(true)
        end
    end)
end

-- 返回弹幕请求参数
function make_danmaku_request_args(method, url, headers, body)
    local args = {
        "curl",
        "-L",
        "-X",
        method,
        "-H",
        "Accept: application/json",
        "-H",
        "User-Agent: " .. options.user_agent,
    }

    if headers then
        for k, v in pairs(headers) do
            table.insert(args, '-H')
            table.insert(args, string.format('%s: %s', k, v))
        end
    end

    if body then
        table.insert(args, '-d')
        table.insert(args, utils.format_json(body))
        table.insert(args, '-H')
        table.insert(args, 'Content-Type: application/json')
    end

    if url:find("api%.dandanplay%.") then
        local time = os.time()
        local appid = "UgjRIH45lE1BBLNmir1WKw=="
        local app_accept = "SzuWlFZAPRMqeWf9qmfp8dcvYr3hvxuSrIRZuAeEfko="
        table.insert(args, '-H')
        table.insert(args, string.format('X-AppId: %s', AES.ECB.decrypt(KEY, Base64.decode(appid))))
        table.insert(args, '-H')
        table.insert(args, string.format('X-Signature: %s', generateXSignature(url, time, appid, app_accept)))
        table.insert(args, '-H')
        table.insert(args, string.format('X-Timestamp: %s', time))
    end

    if options.proxy ~= "" then
        table.insert(args, '-x')
        table.insert(args, options.proxy)
    end

    table.insert(args, url)

    return args
end

-- 尝试通过解析文件名匹配剧集
local function match_episode(animeTitle, bangumiId, episode_num, target_server)
    local servers = target_server and {target_server} or get_api_servers()
    local endpoint = "/api/v2/bangumi/" .. bangumiId

    local concurrent_manager = ConcurrentManager:new()
    local total_servers = #servers
    local has_valid_response = false
    local selected_result = nil
    for i, server in ipairs(servers) do
        local url = server .. endpoint
        local args = make_danmaku_request_args("GET", url)
        msg.info("尝试获取番剧信息: " .. url)

        if args then
            concurrent_manager:start_request(server, i, function(cb)
                call_cmd_async(args, function(error, json)
                    local result = {
                        server = server,
                        error = error,
                        data = nil,
                        success = false
                    }

                    if not error and json then
                        local success, parsed = pcall(utils.parse_json, json)
                        if success and parsed then
                            result.data = parsed
                            result.success = true
                        else
                            result.error = "JSON解析失败"
                        end
                    end

                    cb(result)
                end)
            end)
        else
            if not concurrent_manager.results[server] then
                concurrent_manager.results[server] = {}
            end
            concurrent_manager.results[server][i] = {
                server = server,
                error = "无法生成请求参数",
                data = nil,
                success = false
            }
        end
    end

    concurrent_manager:wait_all(function()
        for server, server_results in pairs(concurrent_manager.results) do
            for i, result in pairs(server_results) do
                if result and result.success and result.data and result.data.bangumi and result.data.bangumi.episodes then
                    selected_result = result
                    has_valid_response = true
                    msg.verbose("使用服务器响应: " .. result.server)
                    break
                end
            end
            if selected_result then break end
        end

        if not has_valid_response then
            for server, server_results in pairs(concurrent_manager.results) do
                for i, result in pairs(server_results) do
                    if result and result.data then
                        selected_result = result
                        msg.verbose("回退使用服务器: " .. result.server)
                        break
                    end
                end
                if selected_result then break end
            end
        end

        if not selected_result or not selected_result.data or not selected_result.data.bangumi then
            if selected_result and selected_result.error then
                msg.error("获取番剧信息失败: " .. selected_result.error)
            else
                msg.error("获取番剧信息失败: 所有服务器请求失败")
            end
            return
        end

        local data = selected_result.data
        if not data.bangumi or not data.bangumi.episodes then
            msg.error("番剧数据格式错误")
            return
        end

        for _, episode in ipairs(data.bangumi.episodes) do
            local ep_num = tonumber(episode.episodeNumber)
            if ep_num and ep_num == tonumber(episode_num) then
                DANMAKU.anime = animeTitle
                DANMAKU.episode = episode.episodeTitle
                set_episode_id(episode.episodeId, selected_result.server)
                break
            end
        end
    end)
end

local function clean_anime_title(title)
    local patterns = {
        "%[OVA%]", "%[OAD%]", "%[剧场版%]", "%[Movie%]", "%[電影%]",
        "%[特別篇%]", "%[Special%]", "%[SP%]",
        "OVA", "OAD", "剧场版", "Movie", "特別篇", "Special"
    }

    local cleaned = title
    for _, pattern in ipairs(patterns) do
        cleaned = cleaned:gsub(pattern, "")
    end

    cleaned = cleaned:gsub("%[.-%]", "")

    cleaned = cleaned:gsub("%s+", " ")
    cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
    return url_encode(cleaned)
end

local function query_tmdb_chinese_title(title, class)
    -- 确保class是有效的值
    if class == "tvseries" or class == "ova" then
        class = "tv"
    end

    local encoded_title = url_encode(title)
    local url = string.format("https://api.themoviedb.org/3/search/%s?api_key=%s&query=%s&language=zh-CN",
        class, Base64.decode(options.tmdb_api_key), encoded_title)

    local cmd = {
        "curl",
        "-s",
        "-H", "accept: application/json",
        url
    }

    if options.proxy ~= "" then
        table.insert(cmd, '-x')
        table.insert(cmd, options.proxy)
    end

    local res = mp.command_native({
        name = "subprocess",
        args = cmd,
        capture_stdout = true,
        capture_stderr = true,
    })

    -- 检查curl命令是否执行成功
    if res.status ~= 0 then
        return nil
    end

    local data = utils.parse_json(res.stdout)

    -- 检查HTTP状态码
    if data and data.status_code and data.status_code == 34 then
        return nil
    end

    if not data or not data.results or #data.results == 0 then
        return nil
    end

    -- 返回第一个结果的中文标题
    if class == "tv" then
        return data.results[1].name
    else
        return data.results[1].title
    end
end

function match_anime_concurrent(callback)
    local servers = get_api_servers()
    local title, season_num, episode_num = parse_title()
    episode_num = episode_num or 1
    local encoded_query = clean_anime_title(title)

    local request_config = {
        make_args = function(server, index)
            local endpoint = "/api/v2/search/anime?keyword=" .. encoded_query
            local url = server .. endpoint
            return make_danmaku_request_args("GET", url)
        end
    }

    local response_handler = function(results)
        local selected_result = nil
        for _, result in ipairs(results) do
            if result.data and result.data.animes and #result.data.animes > 0 then
                local valid_anime_count = 0
                for _, anime in ipairs(result.data.animes) do
                    if anime.animeTitle and anime.bangumiId then
                        valid_anime_count = valid_anime_count + 1
                    end
                end
                if valid_anime_count > 0 then
                    selected_result = result
                    break
                end
            end
        end

        if selected_result then
            process_search_result(selected_result, title, season_num, episode_num, callback)
        else
            if callback then callback("anime_match 没有匹配") end
        end
    end

    make_concurrent_danmaku_request(servers, request_config, response_handler)
end


function process_match_result(selected_result, title, callback, forced_match)
    if not selected_result then
        msg.info("❌ 缺少服务器结果")
        callback("没有匹配的剧集")
        return
    end

    local server = selected_result.server or "未知服务器"
    local match = forced_match

    if not match then
        msg.info("❌ 服务器 " .. server .. " 没有有效的匹配数据（未传入 match）")
        callback("没有匹配的剧集")
        return
    end

    DANMAKU.anime   = match.animeTitle
    DANMAKU.episode = match.episodeTitle

    msg.info("   最终使用服务器: " .. server)
    msg.info("   动画: " .. (DANMAKU.anime or "nil"))
    msg.info("   剧集: " .. (DANMAKU.episode or "nil"))

    set_episode_id(match.episodeId, server)

    callback(nil)
end



function process_search_result(result, title, season_num, episode_num, callback)
    local animes = result.data.animes
    local result_server = result.server

    local filtered_animes = {}
    local anime_type = "tvseries"
    local lower_title = title:lower()

    if lower_title:match("ova") or lower_title:match("oad") then
        anime_type = "ova"
    elseif lower_title:match("剧场版") or lower_title:match("movie") or lower_title:match("劇場版") then
        anime_type = "movie"
    end

    local function filter_by_type(animes, t)
        local result = {}
        for _, a in ipairs(animes) do
            if a.type == t or (t == "tvseries" and (a.type == "jpdrama")) then
                table.insert(result, a)
            end
        end
        return result
    end

    filtered_animes = filter_by_type(animes, anime_type)
    if #filtered_animes == 0 and anime_type == "tvseries" and not season_num then
        filtered_animes = filter_by_type(animes, "movie")
    end

    msg.info("过滤后动画数量: " .. #filtered_animes .. " (类型: " .. anime_type .. ")")

    local best_match, best_score = nil, -1
    if #filtered_animes == 1 then
        best_match = filtered_animes[1]
        best_score = 1
    elseif #filtered_animes > 1 then
        local base_title = title:gsub("%s*%(%d+%)", ""):gsub("^%s*(.-)%s*$", "%1")
        local target_title = base_title
        if is_english(base_title) then
            local chinese_title = query_tmdb_chinese_title(base_title, anime_type)
            if chinese_title then
                base_title = chinese_title
                msg.info("成功获取中文标题: " .. chinese_title)
            else
                msg.info("无法获取中文标题，使用原英文标题: " .. base_title)
            end
        end

        if tonumber(season_num) > 1 then
            target_title = base_title .. " 第" .. number_to_chinese(season_num) .. "季"
        else
            target_title = base_title .. " 第一季"
        end

        msg.info("目标匹配标题: " .. target_title)
        msg.info("数据来源服务器: " .. result_server)

        for _, anime in ipairs(filtered_animes) do
            local anime_title = anime.animeTitle or ""
            local score = jaro_winkler(target_title, anime_title)
            local anime_season = extract_season(anime_title)
            if tonumber(season_num) > 0 and anime_season ~= tonumber(season_num) then
                score = score - 0.2
            end
            msg.info("候选: " .. anime_title .. " -> 相似度 " .. string.format("%.3f", score))

            if score > best_score then
                best_score = score
                best_match = anime
            end
        end
    end

    local threshold = 0.75
    if best_match and best_score >= threshold and not best_match.animeTitle:find("搜索正在") then
        msg.info("✅ 模糊匹配选中: " .. best_match.animeTitle .. " (score=" .. string.format("%.2f", best_score) .. ", 服务器: " .. result_server .. ")")
        match_episode(best_match.animeTitle, best_match.bangumiId, episode_num, result_server)
        if callback then callback(nil) end
    else
        msg.warn("anime_match 没有找到相似度 >= " .. threshold)
        if callback then callback("anime_match 相似度不足") end
    end
end

-- 执行哈希匹配获取弹幕
function match_file_concurrent(file_path, file_name, callback)
    local servers = get_api_servers()
    local hash = nil
    local file_info = utils.file_info(file_path)
    if file_info and file_info.size > 16 * 1024 * 1024 then
        local file, error = io.open(normalize(file_path), 'rb')
        if file and not error then
            local m = MD5.new()
            for _ = 1, 16 * 1024 do
                local content = file:read(1024)
                if not content then break end
                m:update(content)
            end
            file:close()
            hash = m:finish()
        end
    end

    if hash then
        msg.info("hash:", hash)
    else
        msg.info("未生成hash，将使用文件名匹配模式")
    end

    local title, season_num, episode_num = parse_title()
    if title and episode_num then
        if season_num then
            file_name = title .. " S" .. season_num .. "E" .. episode_num
        else
            file_name = title .. " E" .. episode_num
        end
    else
        file_name = title or file_name
    end
    local endpoint = "/api/v2/match"
    local body = {
        fileName   = file_name,
        fileHash   = hash or "a1b2c3d4e5f67890abcd1234ef567890",
        matchMode  = hash and "hashAndFileName" or "fileNameOnly"
    }

    local request_config = {
        make_args = function(server, index)
            local url = server .. endpoint
            return make_danmaku_request_args("POST", url, {
                ["Content-Type"] = "application/json"
            }, body)
        end
    }
    local response_handler = function(results)
        for _, server in ipairs(servers) do
            local r = nil
            for _, rr in ipairs(results) do
                if rr.server == server then
                    r = rr
                    break
                end
            end
            if r and r.data then
                local data = r.data
                if data.isMatched and data.matches and #data.matches == 1 then
                    local match = data.matches[1]
                    msg.info("✅ 精确匹配成功: " .. match.animeTitle)
                    process_match_result(r, title, callback, match)
                    return
                end
                if data.matches and #data.matches > 1 then
                    for _, match in ipairs(data.matches) do
                        -- msg.info("server: " .. r.server .. ", 匹配候选: " .. match.animeTitle)
                        if match.animeTitle == title then
                            msg.info("✅ 从多个结果中根据标题选中: " .. match.animeTitle)
                            process_match_result(r, title, callback, match)
                            return
                        end
                    end
                end
            end
        end
        callback("没有匹配的剧集")
    end
    make_concurrent_danmaku_request(servers, request_config, response_handler)
end

-- 异步获取弹幕数据
function fetch_danmaku_data(args, callback)
    call_cmd_async(args, function(error, json)
        async_running = false
        if error then
            show_message("获取数据失败", 3)
            msg.error("HTTP 请求失败：" .. error)
            return
        end
        local data = utils.parse_json(json)
        callback(data)
    end)
end

-- 保存弹幕数据
function save_danmaku_data(comments, query, danmaku_source)
    local temp_file = "danmaku-" .. PID .. DANMAKU.count .. ".json"
    local danmaku_file = utils.join_path(DANMAKU_PATH, temp_file)
    DANMAKU.count = DANMAKU.count + 1
    local success = save_danmaku_json(comments, danmaku_file)

    if success then
        if DANMAKU.sources[query] ~= nil then
            if DANMAKU.sources[query].fname and file_exists(DANMAKU.sources[query].fname) then
                os.remove(DANMAKU.sources[query].fname)
            end
            DANMAKU.sources[query]["fname"] = danmaku_file
        else
            DANMAKU.sources[query] = {from = danmaku_source, fname = danmaku_file}
        end
    end
end

function save_danmaku_downloaded(url, downloaded_file)
    if DANMAKU.sources[url] ~= nil then
        if DANMAKU.sources[url].fname and file_exists(DANMAKU.sources[url].fname) then
            os.remove(DANMAKU.sources[url].fname)
        end
        DANMAKU.sources[url]["fname"] = downloaded_file
    else
        DANMAKU.sources[url] = {from = "user_custom", fname = downloaded_file}
    end
end

-- 处理弹幕数据
function handle_danmaku_data(query, data, from_menu)
    local comments = data["comments"]
    local count = data["count"]

    -- 如果没有数据，进行重试
    if count == 0 then
        show_message("服务器无缓存数据，再次尝试请求", 30)
        msg.verbose("服务器无缓存数据，再次尝试请求")
        -- 等待 2 秒后重试
        local start = os.time()
        while os.time() - start < 2 do
            -- 空循环，等待 2 秒
        end
        -- 重新发起请求
        local url = get_api_servers()[1] .. "/api/v2/extcomment?url=" .. url_encode(query)
        local args = make_danmaku_request_args("GET", url)

        if args == nil then
            return
        end

        fetch_danmaku_data(args, function(retry_data)
            if not retry_data or not retry_data["comments"] or retry_data["count"] == 0 then
                get_danmaku_fallback(query)
                return
            end
            save_danmaku_data(retry_data["comments"], query, "user_custom")
            load_danmaku(from_menu)
        end)
    else
        save_danmaku_data(comments, query, "user_custom")
        load_danmaku(from_menu)
    end
end

-- 处理第三方弹幕数据
function handle_related_danmaku(index, relateds, related, shift, callback)
    local url = get_api_servers()[1] .. "/api/v2/extcomment?url=" .. url_encode(related["url"])
    show_message(string.format("正在从第三方库装填弹幕 [%d/%d]", index, #relateds), 30)
    msg.verbose("正在从第三方库装填弹幕：" .. url)

    local args = make_danmaku_request_args("GET", url)

    if args == nil then
        return
    end

    fetch_danmaku_data(args, function(data)
        local comments = {}
        if data and data["comments"] then
            if data["count"] == 0 then
                -- 如果没有数据，稍等 2 秒重试
                local start = os.time()
                while os.time() - start < 2 do
                    -- 空循环，等待 2 秒
                end
                fetch_danmaku_data(args, function(data)
                    for _, comment in ipairs(data["comments"]) do
                        comment["shift"] = shift
                        table.insert(comments, comment)
                    end
                    callback(comments)
                end)
            else
                for _, comment in ipairs(data["comments"]) do
                    comment["shift"] = shift
                    table.insert(comments, comment)
                end
                callback(comments)
            end
        else
            show_message("无数据", 3)
            msg.info("无数据")
            callback(comments)
        end
    end)
end

-- 处理dandan库的弹幕数据
function handle_main_danmaku(url, from_menu)
    show_message("正在从弹弹Play库装填弹幕", 30)
    msg.verbose("尝试获取弹幕：" .. url)
    local args = make_danmaku_request_args("GET", url)

    if args == nil then
        return
    end

    fetch_danmaku_data(args, function(data)
        if not data or not data["comments"] then
            show_message("无数据", 3)
            msg.info("无数据")
            return
        end

        local comments = data["comments"]
        local count = data["count"]

        if count == 0 then
            if DANMAKU.sources[url] == nil then
                DANMAKU.sources[url] = {from = "api_server"}
            end
            load_danmaku(from_menu)
            return
        end

        save_danmaku_data(comments, url, "api_server")
        load_danmaku(from_menu)
    end)
end

-- 处理获取到的数据
function handle_fetched_danmaku(data, url, from_menu)
    if data and data["comments"] then
        if data["count"] == 0 then
            if DANMAKU.sources[url] == nil then
                DANMAKU.sources[url] = {from = "api_server"}
            end
            msg.verbose("弹幕内容为空，结束加载url：" .. url)
            return
        end
        save_danmaku_data(data["comments"], url, "api_server")
        msg.info("弹幕加载url：" .. url)
        load_danmaku(from_menu)
    else
        msg.verbose("无数据，结束加载url：" .. url)
    end
end

-- 过滤被排除的平台
function filter_excluded_platforms(relateds)
    -- 解析排除的平台列表
    local excluded_list = {}
    local excluded_json = options.excluded_platforms
    if excluded_json and excluded_json ~= "" and excluded_json ~= "[]" then
        local success, parsed = pcall(utils.parse_json, excluded_json)
        if success and parsed and type(parsed) == "table" then
            excluded_list = parsed
        end
    end

    -- 如果没有排除列表，直接返回原列表
    if #excluded_list == 0 then
        return relateds
    end

    -- 过滤弹幕源
    local filtered = {}
    for _, related in ipairs(relateds) do
        local url = related["url"]
        local should_exclude = false

        -- 检查URL是否包含任何被排除的平台关键词
        for _, platform in ipairs(excluded_list) do
            if url:find(platform, 1, true) then
                should_exclude = true
                msg.info(string.format("已排除平台 [%s] 的弹幕源: %s", platform, url))
                break
            end
        end

        if not should_exclude then
            table.insert(filtered, related)
        end
    end

    msg.info(string.format("原始弹幕源: %d 个, 过滤后: %d 个", #relateds, #filtered))
    return filtered
end

-- 匹配弹幕库 comment, 仅匹配dandan本身弹幕库
-- 通过danmaku api（url）+id获取弹幕
function fetch_danmaku(episodeId, from_menu, specific_server)
    local server = specific_server or get_api_servers()[1]
    local url = server .. "/api/v2/comment/" .. episodeId .. "?withRelated=true&chConvert=0"
    show_message("弹幕加载中...", 30)
    msg.verbose("尝试获取弹幕：" .. url)
    local args = make_danmaku_request_args("GET", url)

    if args == nil then
        return
    end

    fetch_danmaku_data(args, function(data)
        handle_fetched_danmaku(data, url, from_menu)
    end)
end

-- 主函数：获取所有相关弹幕
function fetch_danmaku_all(episodeId, from_menu, specific_server)
    local server = specific_server or get_api_servers()[1]
    local url = server .. "/api/v2/related/" .. episodeId
    show_message("弹幕加载中...", 30)
    msg.verbose("尝试获取弹幕：" .. url)
    local args = make_danmaku_request_args("GET", url)

    if args == nil then
        return
    end

    fetch_danmaku_data(args, function(data)
        if not data or not data["relateds"] then
            show_message("无数据", 3)
            msg.info("无数据")
            return
        end

        -- 处理所有的相关弹幕，过滤掉被排除的平台
        local relateds = data["relateds"]
        local filtered_relateds = filter_excluded_platforms(relateds)
        local function process_related(index)
            if index > #filtered_relateds then
                -- 所有相关弹幕加载完成后，开始加载主库弹幕
                url = server .. "/api/v2/comment/" .. episodeId .. "?withRelated=false&chConvert=0"
                handle_main_danmaku(url, from_menu)
                return
            end

            local related = filtered_relateds[index]
            local shift = related["shift"]

            -- 处理当前的相关弹幕
            handle_related_danmaku(index, filtered_relateds, related, shift, function(comments)
                if #comments == 0 then
                    if DANMAKU.sources[related["url"]] == nil then
                        DANMAKU.sources[related["url"]] = {from = "api_server"}
                    end
                else
                    save_danmaku_data(comments, related["url"], "api_server")
                end

                -- 继续处理下一个相关弹幕
                process_related(index + 1)
            end)
        end

        -- 从第一个相关库开始请求
        process_related(1)
    end)
end

-- 从用户添加过的弹幕源添加弹幕
function addon_danmaku(dir, from_menu)
    if dir then
        local history_json = read_file(HISTORY_PATH)
        local history = utils.parse_json(history_json) or {}
        if history[dir] and history[dir].extra ~= nil then
            return
        end
    end
    for url, source in pairs(DANMAKU.sources) do
        if source.from ~= "api_server" then
            add_danmaku_source(url, from_menu)
        end
    end
end

--通过输入源url获取弹幕库
function add_danmaku_source(query, from_menu)
    if DANMAKU.sources[query] == nil then
        DANMAKU.sources[query] = {from = "user_custom"}
    end

    from_menu = from_menu or false
    if from_menu then
        add_source_to_history(query, DANMAKU.sources[query])
    end

    if is_protocol(query) then
        add_danmaku_source_online(query, from_menu)
    else
        add_danmaku_source_local(query, from_menu)
    end
end

function add_danmaku_source_local(query, from_menu)
    local path = normalize(query)
    if not file_exists(path) then
        msg.warn("无效的文件路径")
        return
    end
    if not (string.match(path, "%.xml$") or string.match(path, "%.json$") or string.match(path, "%.ass$")) then
        msg.warn("仅支持弹幕文件")
        return
    end

    if DANMAKU.sources[query] ~= nil then
        if DANMAKU.sources[query].fname and file_exists(DANMAKU.sources[query].fname) then
            os.remove(DANMAKU.sources[query].fname)
        end
        DANMAKU.sources[query]["from"] = "user_local"
        DANMAKU.sources[query]["fname"] = path
    else
        DANMAKU.sources[query] = {from = "user_local", fname = path}
    end

    set_danmaku_button()
    load_danmaku(from_menu)
end

--通过输入源url获取弹幕库
function add_danmaku_source_online(query, from_menu)
    set_danmaku_button()
    local url = get_api_servers()[1] .. "/api/v2/extcomment?url=" .. url_encode(query)
    show_message("弹幕加载中...", 30)
    msg.verbose("尝试获取弹幕：" .. url)
    local args = make_danmaku_request_args("GET", url)

    if args == nil then
        return
    end

    fetch_danmaku_data(args, function(data)
        if not data or not data["comments"] then
            show_message("此源弹幕无法加载", 3)
            msg.verbose("此源弹幕无法加载")
            return
        end
        handle_danmaku_data(query, data, from_menu)
    end)
end

-- 将弹幕转换为factory可读的json格式
function save_danmaku_json(comments, json_filename)
    local temp_file = "danmaku-" .. PID .. ".json"
    json_filename = json_filename or utils.join_path(DANMAKU_PATH, temp_file)
    local json_file = io.open(json_filename, "w")

    if json_file then
        json_file:write("[\n")
        for _, comment in ipairs(comments) do
            local p = comment["p"]
            local shift = comment["shift"]
            if p then
                local fields = split(p, ",")
                if shift ~= nil then
                    fields[1] = tonumber(fields[1]) + tonumber(shift)
                end
                local c_value = string.format(
                    "%s,%s,%s,25,,,",
                    tostring(fields[1]), -- first field of p to first field of c
                    fields[3], -- third field of p to second field of c
                    fields[2]  -- second field of p to third field of c
                )
                local m_value = comment["m"]
                                :gsub("[%z\1-\31]", "")
                                :gsub("\\", "")
                                :gsub("\"", "")

                -- Write the JSON object as a single line, no spaces or extra formatting
                local json_entry = string.format('{"c":"%s","m":"%s"},\n', c_value, m_value)
                json_file:write(json_entry)
            end
        end
        json_file:write("]")
        json_file:close()
        return true
    end

    return false
end

-- 修改 get_danmaku_with_hash 函数以使用并发版本
function get_danmaku_with_hash(file_name, file_path)
    local servers = get_api_servers()
    local priority_strategy = "file_match"
    if servers[1] and servers[1]:find("api%.dandanplay%.") then
        msg.info("检测到 首选项 为 dandanplay，优先使用 anime_match 策略")
        priority_strategy = "anime_match"
    end
    if type(MD5) ~= "table" or not MD5.sum then
        msg.warn("MD5 模块不支持 Lua 5.1，回退到：" .. priority_strategy)

        if priority_strategy == "anime_match" then
            match_anime_concurrent(function(error)
                if error then
                    msg.warn("anime_match 失败，尝试 fallback 到 file_match: " .. error)
                    match_file_concurrent(file_path, file_name, function(err2)
                        if err2 then
                            msg.error(err2)
                        end
                    end)
                end
            end)
        else
            match_file_concurrent(file_path, file_name, function(error)
                if error then
                    msg.error(error)
                    match_anime_concurrent()
                end
            end)
        end
        return
    end
    if is_protocol(file_path) then
        set_danmaku_button()
        local temp_file = "temp-" .. PID .. ".mp4"
        local arg = {
            "curl",
            "--connect-timeout", "10",
            "--max-time", "30",
            "--range", "0-16777215",
            "--user-agent", options.user_agent,
            "--output", utils.join_path(DANMAKU_PATH, temp_file),
            "-L", file_path,
        }

        if options.proxy ~= "" then
            table.insert(arg, "-x")
            table.insert(arg, options.proxy)
        end

        call_cmd_async(arg, function(error)
            async_running = false
            file_path = utils.join_path(DANMAKU_PATH, temp_file)

            if priority_strategy == "anime_match" then
                match_anime_concurrent(function(error)
                    if error then
                        msg.warn("anime_match 失败，尝试 fallback 到 file_match: " .. error)
                        match_file_concurrent(file_path, file_name, function(err2)
                            if err2 then
                                msg.error(err2)
                            end
                        end)
                    end
                end)
            else
                match_file_concurrent(file_path, file_name, function(error)
                    if error then
                        msg.error(error)
                        match_anime_concurrent()
                    end
                end)
            end
        end)

        return
    end

    -- 本地文件路径过滤
    local dir = get_parent_directory(file_path)
    local excluded_path = utils.parse_json(options.excluded_path)

    if PLATFORM == "windows" then
        for i, path in pairs(excluded_path) do
            excluded_path[i] = path:gsub("/", "\\")
        end
    end
    if contains_any(excluded_path, dir) then
        if priority_strategy == "anime_match" then
            match_anime_concurrent(function(error)
                if error then
                    msg.warn("anime_match 失败，尝试 fallback 到 file_match: " .. error)
                    match_file_concurrent(file_path, file_name, function(err2)
                        if err2 then
                            msg.error(err2)
                        end
                    end)
                end
            end)
        else
            match_file_concurrent(file_path, file_name)
        end
        return
    end
    if priority_strategy == "anime_match" then
        match_anime_concurrent(function(error)
            if error then
                msg.warn("anime_match 失败，尝试 fallback 到 file_match: " .. error)
                match_file_concurrent(file_path, file_name, function(err2)
                    if err2 then
                        msg.error(err2)
                    end
                end)
            end
        end)
        return
    end
    match_file_concurrent(file_path, file_name, function(error)
        if error then
            msg.error(error)
            match_anime_concurrent()
        end
    end)
end
