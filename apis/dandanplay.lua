local msg = require('mp.msg')
local utils = require("mp.utils")

local function extract_url(url)
    local path = url:match("^https?://[^/]+(/[^%?]*)")
    return path
end

local DANDAN_APPID_ENC = "UgjRIH45lE1BBLNmir1WKw=="
local DANDAN_ACCEPT_ENC = "SzuWlFZAPRMqeWf9qmfp8dcvYr3hvxuSrIRZuAeEfko="
local DANDAN_APPID_DEC = nil
local DANDAN_ACCEPT_DEC = nil

local function init_credentials()
    if not DANDAN_APPID_DEC then
        DANDAN_APPID_DEC = AES.ECB.decrypt(KEY, Base64.decode(DANDAN_APPID_ENC))
        DANDAN_ACCEPT_DEC = AES.ECB.decrypt(KEY, Base64.decode(DANDAN_ACCEPT_ENC))
    end
end

local function generateXSignature(url, time)
    init_credentials()
    local url_path = extract_url(url)
    if not url_path then return nil end

    local dataToHash = string.format("%s%d%s%s", DANDAN_APPID_DEC, time, url_path, DANDAN_ACCEPT_DEC)
    local hash = Sha256(dataToHash)
    return Base64.encode(hex_to_bin(hash))
end

function get_base_curl_args()
    local args = {
        "curl",
        "-L",
        "-s",
        "--compressed",
        "--user-agent", options.user_agent,
        "--max-time", "20",
        "-H", "accept: application/json",
    }

    if options.proxy ~= "" then
        table.insert(args, '-x')
        table.insert(args, options.proxy)
    end

    return args
end

-- 并发请求多个API服务器
local function make_concurrent_danmaku_request(servers, request_config, response_handler, custom_validator)
    local concurrent_manager = ConcurrentManager:new()
    local total_servers = #servers

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
            concurrent_manager:start_request(server, i, function(cb)
                cb({
                    server = server,
                    error = "无法生成请求参数",
                    data = nil,
                    index = i
                })
            end)
        end
    end

    local validator = custom_validator or function(res)
        return res and not res.error and res.data
    end

    concurrent_manager:wait_priority(total_servers, validator, function(results)
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

    local args = get_base_curl_args()
    table.insert(args, "--output")
    table.insert(args, danmaku_xml)
    table.insert(args, url)

    call_cmd_async(args, function(error)
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
    local args = get_base_curl_args()
    table.insert(args, "-X")
    table.insert(args, method)

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
        init_credentials()
        table.insert(args, '-H'); table.insert(args, string.format('X-AppId: %s', DANDAN_APPID_DEC))
        table.insert(args, '-H'); table.insert(args, string.format('X-Signature: %s', generateXSignature(url, time)))
        table.insert(args, '-H'); table.insert(args, string.format('X-Timestamp: %s', time))
    end

    table.insert(args, url)

    return args
end

-- 尝试通过解析文件名匹配剧集
function match_episode(animeTitle, bangumiId, episode_num, target_server, callback)
    callback = callback or function(error)
        if error then msg.error(error) end
    end
    local servers = target_server and {target_server} or get_api_servers()
    local request_config = {
        make_args = function(server, index)
            local endpoint = "/api/v2/bangumi/" .. bangumiId
            local url = server .. endpoint
            msg.verbose("尝试获取番剧信息: " .. url)
            return make_danmaku_request_args("GET", url)
        end
    }

    -- 集数存在性校验器
    local episode_validator = function(result)
        if not result or result.error or not result.data then return false end
        if not result.data.bangumi or not result.data.bangumi.episodes then return false end

        local episodes = result.data.bangumi.episodes
        local target_ep = tonumber(episode_num)

        -- 遍历检查目标集数是否存在
        for _, episode in ipairs(episodes) do
            local ep_num = tonumber(episode.episodeNumber)
            if ep_num and ep_num == target_ep then
                return true -- 找到了这一集，数据有效
            end
        end

        return false
    end

    local response_handler = function(results)
        for _, result in ipairs(results) do
            if episode_validator(result) then
                local episodes = result.data.bangumi.episodes
                for _, episode in ipairs(episodes) do
                    local ep_num = tonumber(episode.episodeNumber)
                    if ep_num and ep_num == tonumber(episode_num) then
                        DANMAKU.anime = animeTitle
                        DANMAKU.episode = episode.episodeTitle
                        set_episode_id(episode.episodeId, result.server)
                        local match = {
                            animeTitle = animeTitle,
                            episodeTitle = episode.episodeTitle,
                            episodeId = episode.episodeId,
                            bangumiId = bangumiId,
                            match_type = "episode",
                            similarity = 1.0
                        }
                        save_selected_episode_with_offset(
                            result.server,
                            animeTitle,
                            episode.episodeTitle,
                            episode.episodeId,
                            bangumiId
                        )
                        save_match_to_cache(result.server, {match}, "episode", {}, true)
                        callback(nil)
                        return
                    end
                end
            end
        end

        local error_msg = string.format("所有服务器均未找到第 %s 集", tostring(episode_num))
        if results[1] and results[1].error then error_msg = results[1].error end
        callback(error_msg)
    end

    make_concurrent_danmaku_request(servers, request_config, response_handler, episode_validator)
end

function clean_anime_title(title)
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

function match_anime_concurrent(callback, specific_servers)
    local servers = specific_servers or get_api_servers()
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
    local similarity_validator = function(result)
        if not result or result.error or not result.data then return false end
        if not result.data.animes or #result.data.animes == 0 then return false end
        local matches = process_anime_matches(result.data.animes, title, season_num, result.server)

        -- 如果找到了至少一个高相似度的结果，则视为有效
        if matches and #matches > 0 then
            return true
        end

        return false
    end
    local response_handler = function(results)
        for _, result in ipairs(results) do
            if similarity_validator(result) then
                local matches = process_anime_matches(result.data.animes, title, season_num, result.server)
                local best_match = matches[1]
                msg.verbose("✅ 模糊匹配选中: " .. best_match.animeTitle .. " (server: " .. result.server .. ")")

                -- 继续流程：获取剧集
                match_episode(best_match.animeTitle, best_match.bangumiId, episode_num, result.server, function(error)
                    if error then
                        if callback then callback(error) end
                    else
                        if callback then callback(nil) end
                    end
                end)
                return
            end
        end
        if callback then callback("所有服务器均未找到匹配番剧 (threshold >= 0.75)") end
    end
    make_concurrent_danmaku_request(servers, request_config, response_handler, similarity_validator)
end

-- 针对御坂服务器的特殊处理
function inferBangumiId(match, server)
    if not (match and match.animeId and match.episodeId) then
        return nil
    end

    local animeId_str = tostring(match.animeId)
    local episodeId_str = tostring(match.episodeId)

    if episodeId_str:find(animeId_str, 1, true)
        and not episodeId_str:startswith(animeId_str)
    then
        return "A" .. animeId_str
    end

    if animeId_str:startswith("9")
        and #animeId_str == 6
        and #episodeId_str == 14
        and server:find("/api/v1/")
    then
        local extracted = tonumber(episodeId_str:sub(3, 8))
        if extracted then
            return "A" .. tostring(extracted)
        end
    end

    return nil
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

    local id = inferBangumiId(match, server)
    if id then
        match.bangumiId = id
    end
    DANMAKU.anime   = match.animeTitle
    DANMAKU.episode = match.episodeTitle

    msg.verbose("   最终使用服务器: " .. server)

    set_episode_id(match.episodeId, server)
    save_selected_episode_with_offset(
        server,
        match.animeTitle,
        match.episodeTitle,
        tostring(match.episodeId),
        match.bangumiId
    )
    save_match_to_cache(server, {match}, "episode", {}, true)

    callback(nil)
end

function process_anime_matches(animes, title, season_num, result_server)
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
    local best_match, best_score = nil, -1
    if #filtered_animes == 1 then
        best_match = filtered_animes[1]
        best_score = 1
    elseif #filtered_animes > 1 then
        local base_title = title:gsub("%s*%(%d+%)", ""):gsub("^%s*(.-)%s*$", "%1")
        local target_title = base_title
        if is_english(base_title) then
            local chinese_title = query_tmdb(base_title, anime_type)
            if chinese_title then
                base_title = chinese_title
            end
        end
        if tonumber(season_num) and tonumber(season_num) > 1 then
            target_title = base_title .. " 第" .. number_to_chinese(season_num) .. "季"
        else
            target_title = base_title .. " 第一季"
        end
        for _, anime in ipairs(filtered_animes) do
            local anime_title = anime.animeTitle or ""
            local score = jaro_winkler(target_title, anime_title)
            local anime_season = extract_season(anime_title)
            if tonumber(anime_season) and anime_season ~= tonumber(season_num) then
                score = score - 0.2
            end
            if score > best_score then
                best_score = score
                best_match = anime
            end
        end
    end
    local threshold = 0.75
    if best_match and best_score >= threshold and not best_match.animeTitle:find("搜索正在") then
        best_match.similarity = best_score
        return {best_match}
    end
    return {}
end

function process_search_result(result, title, season_num, episode_num, callback)
    local animes = result.data.animes
    local result_server = result.server

    local matches = process_anime_matches(animes, title, season_num, result_server)
    if matches and #matches > 0 then
        local best_match = matches[1]
        msg.verbose("✅ 模糊匹配选中: " .. best_match.animeTitle .. " (score=" .. string.format("%.2f", best_match.similarity or 0) .. ", 服务器: " .. result_server .. ")")
        match_episode(best_match.animeTitle, best_match.bangumiId, episode_num, result_server, function(error)
            if error then
                msg.warn("match_episode 失败: " .. error)
                if callback then callback("match_episode 失败: " .. error) end
            else
                if callback then callback(nil) end
            end
        end)
    else
        msg.warn("anime_match 没有找到相似度 >= 0.75")
        if callback then callback("anime_match 相似度不足") end
    end
end

-- 执行哈希匹配获取弹幕
function match_file_concurrent(file_path, file_name, callback, specific_servers)
    local servers = specific_servers or get_api_servers()
    local hash = nil
    local file_info = utils.file_info(file_path)
    local excluded_path = utils.parse_json(options.excluded_path)
    if PLATFORM == "windows" then
        for i, path in pairs(excluded_path) do excluded_path[i] = path:gsub("/", "\\") end
    end
    local dir = get_parent_directory(file_path)
    if not is_protocol(file_path) and not contains_any(excluded_path, dir) and file_info and file_info.size >= 16 * 1024 * 1024 then
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
    local strict_validator = function(result)
        if not result or result.error or not result.data then return false end
        local data = result.data
        if data.isMatched and data.matches and #data.matches == 1 then return true end
        if data.matches and #data.matches > 1 then
            -- 如果 title 解析失败了，只要有返回结果就算对
            if not title then return true end
            for _, match in ipairs(data.matches) do
                if match.animeTitle == title then
                    return true
                end
            end
        end
        return false
    end
    local response_handler = function(results)
        for _, r in ipairs(results) do
            if strict_validator(r) then
                local data = r.data
                if data.isMatched and data.matches and #data.matches == 1 then
                    msg.verbose("✅ 精确匹配成功: " .. data.matches[1].animeTitle)
                    process_match_result(r, title, callback, data.matches[1])
                    return
                end
                if data.matches then
                    for _, match in ipairs(data.matches) do
                        if not title or match.animeTitle == title then
                            msg.verbose("✅ 文件名匹配选中: " .. match.animeTitle)
                            process_match_result(r, title, callback, match)
                            return
                        end
                    end
                end
            end
        end
        if callback then callback("没有匹配的剧集 (所有服务器尝试完毕)") end
    end
    make_concurrent_danmaku_request(servers, request_config, response_handler, strict_validator)
end

-- 异步获取弹幕数据
function fetch_danmaku_data(args, callback)
    call_cmd_async(args, function(error, json)
        async_running = false
        if error then
            msg.info("获取弹幕数据出错，请稍后在选择弹幕源里重试。错误信息: " .. error)
            show_message("弹幕请求失败，打开控制台查看详情", 5)
            return
        end

        -- 检查返回的json是否为空，如果为空，也可能导致卡住或解析失败
        if not json or json == "" then
             msg.error("HTTP 请求成功返回，但数据内容为空。")
             show_message("数据返回为空", 3)
             return
        end

        local success, data = pcall(utils.parse_json, json)
        if not success then
            msg.error("JSON 解析失败" )
            show_message("弹幕数据解析失败", 3)
            return
        end

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
        local servers = get_api_servers()
        local base = servers[1]

        for _, s in ipairs(servers) do
            if s:find("api%.dandanplay%.") or s:find("/api/v1/") then
                base = s
                break
            end
        end

        local url = base .. "/api/v2/extcomment?url=" .. url_encode(query)
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
    local servers = get_api_servers()
    local base = servers[1]

    -- 依序寻找匹配的服务器
    for _, s in ipairs(servers) do
        if s:find("api%.dandanplay%.") or s:find("/api/v1/") then
            base = s
            break
        end
    end

    local url = base .. "/api/v2/extcomment?url=" .. url_encode(related["url"])
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
        handle_fetched_danmaku(data, url, from_menu)
    end)
end

-- 处理获取到的数据
function handle_fetched_danmaku(data, url, from_menu)
    if data and data["comments"] then
        if data["count"] == 0 and DANMAKU.sources[url] == nil then
            DANMAKU.sources[url] = {from = "api_server"}
            load_danmaku(from_menu)
            return
        end
        save_danmaku_data(data["comments"], url, "api_server")
        load_danmaku(from_menu)
    else
        show_message("弹幕数据加载不成功，请稍后在选择弹幕源里重试", 3)
        msg.verbose("无数据或格式错误，结束加载url：" .. url)
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
        local filtered_relateds = filter_excluded_platforms(data["relateds"])
        local function process_related(index)
            if index > #filtered_relateds then
                -- 所有相关弹幕加载完成后，开始加载主库弹幕
                local main_url = server .. "/api/v2/comment/" .. episodeId .. "?withRelated=false&chConvert=0"
                handle_main_danmaku(main_url, from_menu)
                return
            end

            local related = filtered_relateds[index]

            -- 处理当前的相关弹幕
            handle_related_danmaku(index, filtered_relateds, related, related["shift"], function(comments)
                if comments and #comments > 0 then
                    save_danmaku_data(comments, related["url"], "api_server")
                elseif DANMAKU.sources[related["url"]] == nil then
                    DANMAKU.sources[related["url"]] = {from = "api_server"}
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
    local servers = get_api_servers()
    local base = servers[1]
    for _, s in ipairs(servers) do
        if s:find("api%.dandanplay%.") or s:find("/api/v1/") then
            base = s
            break
        end
    end

    local url = base .. "/api/v2/extcomment?url=" .. url_encode(query)
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

-- 执行匹配链：处理优先级和 Fallback
local function execute_match_chain(strategy, file_path, file_name, servers)
    local function fallback_to_anime(err_source)
        msg.warn(err_source .. " 失败，尝试 Fallback 到 anime_match")
        match_anime_concurrent(function(err)
            if err then msg.error("所有匹配策略均失败: " .. err) end
        end, servers)
    end

    local function fallback_to_file(err_source)
        msg.warn(err_source .. " 失败，尝试 Fallback 到 file_match")
        match_file_concurrent(file_path, file_name, function(err)
            if err then msg.error("所有匹配策略均失败: " .. err) end
        end, servers)
    end

    if strategy == "anime_first" then
        match_anime_concurrent(function(err)
            if err then fallback_to_file("anime_match") end
        end, servers)
    else
        match_file_concurrent(file_path, file_name, function(err)
            if err then fallback_to_anime("file_match") end
        end, servers)
    end
end

-- 修改 get_danmaku_with_hash 函数以使用并发版本
function get_danmaku_with_hash(file_name, file_path, specific_servers)
    local servers = specific_servers or get_api_servers()

    local strategy = "file_first"
    -- 如果首选服务器是 dandanplay，或者没有 MD5 库，则优先搜番剧
    if (servers[1] and servers[1]:find("api%.dandanplay%.")) or (type(MD5) ~= "table" or not MD5.sum) then
        strategy = "anime_first"
    end
    if is_protocol(file_path) and options.hash_for_url then
        set_danmaku_button()
        local temp_file = "temp-" .. PID .. ".mp4"
        local output_path = utils.join_path(DANMAKU_PATH, temp_file)
        local arg = {
            "curl", "--connect-timeout", "10", "--max-time", "30", "--range", "0-16777215",
            "--user-agent", options.user_agent, "--output", output_path, "-L", file_path,
        }
        if options.proxy ~= "" then table.insert(arg, "-x"); table.insert(arg, options.proxy) end

        call_cmd_async(arg, function(error)
            async_running = false
            -- 下载完成后，执行统一匹配链
            execute_match_chain(strategy, output_path, file_name, servers)
        end)
        return
    end

    -- 标准处理
    execute_match_chain(strategy, file_path, file_name, servers)
end
