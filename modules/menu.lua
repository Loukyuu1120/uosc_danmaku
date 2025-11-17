local msg = require('mp.msg')
local utils = require("mp.utils")

input_loaded, input = pcall(require, "mp.input")
uosc_available = false

local function extract_server_identifier(server_url)
    if not server_url then
        return "未知"
    end

    -- 为常见服务器分配简短的字母标识
    local server_aliases = {
        ["api.dandanplay.net"] = "弹弹play",
        ["localhost"] = "本地",
        ["127.0.0.1"] = "本地"
    }
    local hostname = server_url:gsub("^https?://", ""):gsub("/.*$", ""):gsub(":[0-9]+$", "")

    if server_aliases[hostname] then
        return server_aliases[hostname]
    else
        return hostname:sub(1, 5)
    end
end

function get_animes(query)
    local encoded_query = url_encode(query)
    local servers = get_api_servers()
    local endpoint = "/api/v2/search/anime?keyword=" .. encoded_query

    local items = {}
    local message = "加载数据中...(" .. #servers .. "个服务器)"
    local menu_type = "menu_anime"
    local menu_title = "在此处输入番剧名称"
    local footnote = "使用enter或ctrl+enter进行搜索"
    local menu_cmd = { "script-message-to", mp.get_script_name(), "search-anime-event" }

    table.insert(items, {
        title = "← 返回",
        value = { "script-message-to", mp.get_script_name(), "open_search_danmaku_menu" },
        keep_open = false,
        selectable = true,
    })

    if uosc_available then
        update_menu_uosc(menu_type, menu_title, message, footnote, menu_cmd, query)
    else
        show_message(message, 30)
    end
    msg.verbose("尝试获取番剧数据：" .. endpoint .. " (服务器数量: " .. #servers .. ")")

    -- 使用集合来避免重复
    local seen_anime_ids = {}
    local total_results = 0

    local concurrent_manager = ConcurrentManager:new()
    local request_count = 0  -- 记录实际发起的请求数量

    for i, server in ipairs(servers) do
        local url = server .. endpoint
        local args = make_danmaku_request_args("GET", url, nil, nil)

        if args then
            request_count = request_count + 1  -- 只有成功创建args的请求才计数
            local request_func = function(callback)
                call_cmd_async(args, function(error, json)
                    local result = {
                        success = false,
                        server = server,
                        animes = {}
                    }

                    if not error and json then
                        local success, parsed = pcall(utils.parse_json, json)
                        if success and parsed and parsed.animes then
                            result.success = true
                            result.animes = parsed.animes
                        end
                    end

                    callback(result)
                end)
            end

            concurrent_manager:start_request(server, i, request_func)
        end
    end

    if request_count == 0 then
        local message = "无可用服务器"
        if uosc_available then
            update_menu_uosc(menu_type, menu_title, items, footnote, menu_cmd, query)
        else
            show_message(message, 3)
        end
        return
    end

    local callback_executed = false

    concurrent_manager:wait_all(function()
        if callback_executed then
            return
        end
        callback_executed = true

        for server, server_results in pairs(concurrent_manager.results) do
            for key, result in pairs(server_results) do
                if result.success and result.animes then
                    for _, anime in ipairs(result.animes) do
                        local anime_id = anime.bangumiId or anime.animeId
                        if anime_id and not seen_anime_ids[anime_id] then
                            local server_identifier = extract_server_identifier(server)
                            local display_title = anime.animeTitle
                            if server_identifier then
                                display_title = display_title .. " [" .. server_identifier .. "]"
                            end

                            table.insert(items, {
                                title = display_title,
                                hint = anime.typeDescription,
                                value = {
                                    "script-message-to",
                                    mp.get_script_name(),
                                    "search-episodes-event",
                                    anime.animeTitle,  -- 保持原始title，不带服务器标识
                                    anime.bangumiId,
                                    server,
                                    query
                                },
                            })
                            seen_anime_ids[anime_id] = true
                            total_results = total_results + 1
                        end
                    end
                end
            end
        end

        if total_results > 0 then
            local message = "✅ 搜索到 " .. total_results .. " 个结果"

            if uosc_available then
                update_menu_uosc(menu_type, menu_title, items, footnote, menu_cmd, query)
            elseif input_loaded then
                show_message("", 0)
                mp.add_timeout(0.1, function()
                    open_menu_select(items)
                end)
            end
        else
            if #items == 1 then
                local message = "无结果"
                if uosc_available then
                    update_menu_uosc(menu_type, menu_title, items, footnote, menu_cmd, query)
                else
                    show_message(message, 3)
                end
            end
        end
    end)
end

function get_episodes(animeTitle, bangumiId, source_server, original_query)
    local servers = {}

    -- 如果指定了源服务器，优先使用该服务器
    if source_server and source_server ~= "" then
        table.insert(servers, source_server)
        msg.verbose("使用指定服务器: " .. source_server)
    else
        servers = get_api_servers()
        msg.verbose("使用自动服务器选择，数量: " .. #servers)
    end

    local endpoint = "/api/v2/bangumi/" .. bangumiId
    local items = {}
    local message = "加载数据中...(" .. #servers .. "个服务器)"
    local menu_type = "menu_episodes"
    local menu_title = "剧集信息 - " .. animeTitle
    local footnote = "使用 / 打开筛选"

    -- 添加返回按钮，使用原始搜索关键词
    local return_query = original_query or animeTitle:match("^(.-)%s*%(%d+%)$") or animeTitle
    table.insert(items, {
        title = "← 返回",
        value = { "script-message-to", mp.get_script_name(), "search-anime-event", return_query },
        keep_open = false,
        selectable = true,
    })

    if uosc_available then
        update_menu_uosc(menu_type, menu_title, message, footnote)
    else
        show_message(message, 30)
    end

    -- 存储所有服务器的结果
    local all_episodes = {}
    local completed_requests = 0
    local successful_requests = 0

    for i, server in ipairs(servers) do
        local url = server .. endpoint
        local args = make_danmaku_request_args("GET", url, nil, nil)

        if args then
            call_cmd_async(args, function(error, json)
                completed_requests = completed_requests + 1

                local result_data = nil
                local has_data = false

                if not error and json then
                    local success, parsed = pcall(utils.parse_json, json)
                    if success and parsed and parsed.bangumi and parsed.bangumi.episodes then
                        result_data = parsed
                        has_data = true
                        successful_requests = successful_requests + 1

                        -- 记录这个服务器的剧集数据
                        all_episodes[server] = {
                            episodes = parsed.bangumi.episodes,
                            count = #parsed.bangumi.episodes,
                            bangumi = parsed.bangumi
                        }
                        msg.verbose("服务器 " .. server .. " 返回 " .. #parsed.bangumi.episodes .. " 个剧集")
                    end
                end

                -- 所有请求完成后处理
                if completed_requests == #servers then
                    local best_server = nil
                    local max_episodes = 0

                    -- 选择剧集数量最多的服务器
                    for srv, data in pairs(all_episodes) do
                        if data.count > max_episodes then
                            max_episodes = data.count
                            best_server = srv
                        end
                    end

                    if best_server and all_episodes[best_server] then
                        local episodes = all_episodes[best_server].episodes
                        msg.info("✅ 获取到 " .. #episodes .. " 个剧集 (服务器: " .. best_server .. ", 成功: " .. successful_requests .. "/" .. #servers .. ")")

                        -- 按剧集号排序
                        table.sort(episodes, function(a, b)
                            return (tonumber(a.episodeNumber) or 0) < (tonumber(b.episodeNumber) or 0)
                        end)

                        for _, episode in ipairs(episodes) do
                            table.insert(items, {
                                title = episode.episodeTitle or "未知标题",
                                hint = "第" .. (episode.episodeNumber or "?") .. "集",
                                value = {
                                    "script-message-to",
                                    mp.get_script_name(),
                                    "load-danmaku",
                                    animeTitle,
                                    episode.episodeTitle or "未知标题",
                                    tostring(episode.episodeId),
                                    best_server  -- 传递服务器信息
                                },
                                keep_open = false,
                                selectable = true,
                            })
                        end

                        if uosc_available then
                            update_menu_uosc(menu_type, menu_title, items, footnote)
                        elseif input_loaded then
                            mp.add_timeout(0.1, function()
                                open_menu_select(items)
                            end)
                        end
                    else
                        -- 如果没有结果，确保返回按钮仍然显示
                        if #items == 1 then -- 只有返回按钮
                            local message = "获取剧集列表失败"
                            if uosc_available then
                                update_menu_uosc(menu_type, menu_title, items, footnote)
                            else
                                show_message(message, 3)
                            end
                        end
                    end
                end
            end)
        else
            completed_requests = completed_requests + 1
        end
    end
end

function update_menu_uosc(menu_type, menu_title, menu_item, menu_footnote, menu_cmd, query)
    local items = {}
    if type(menu_item) == "string" then
        table.insert(items, {
            title = menu_item,
            value = "",
            italic = true,
            keep_open = true,
            selectable = false,
            align = "center",
        })
    else
        items = menu_item
    end

    local menu_props = {
        type = menu_type,
        title = menu_title,
        search_style = menu_cmd and "palette" or "on_demand",
        search_debounce = menu_cmd and "submit" or 0,
        on_search = menu_cmd,
        footnote = menu_footnote,
        search_suggestion = query,
        items = items,
    }
    local json_props = utils.format_json(menu_props)
    mp.commandv("script-message-to", "uosc", "open-menu", json_props)
end

function open_menu_select(menu_items, is_time)
    local item_titles, item_values = {}, {}
    for i, v in ipairs(menu_items) do
        item_titles[i] = is_time and "[" .. v.hint .. "] " .. v.title or
            (v.hint and v.title .. " (" .. v.hint .. ")" or v.title)
        item_values[i] = v.value
    end
    mp.commandv('script-message-to', 'console', 'disable')
    input.select({
        prompt = '筛选:',
        items = item_titles,
        submit = function(id)
            mp.commandv(unpack(item_values[id]))
        end,
    })
end

-- 打开弹幕输入搜索菜单
function open_input_menu_get()
    mp.commandv('script-message-to', 'console', 'disable')
    local title = parse_title()
    input.get({
        prompt = '番剧名称:',
        default_text = title,
        cursor_position = title and #title + 1,
        submit = function(text)
            input.terminate()
            mp.commandv("script-message-to", mp.get_script_name(), "search-anime-event", text)
        end
    })
end

function open_input_menu_uosc()
    local items = {}

    if DANMAKU.anime and DANMAKU.episode then
        local episode = DANMAKU.episode:gsub("%s.-$","")
        episode = episode:match("^(第.*[话回集]+)%s*") or episode
        items[#items + 1] = {
            title = string.format("已关联弹幕：%s-%s", DANMAKU.anime, episode),
            bold = true,
            italic = true,
            keep_open = true,
            selectable = false,
        }
    end

    items[#items + 1] = {
        hint = "  追加|ds或|dy或|dm可搜索电视剧|电影|国漫",
        keep_open = true,
        selectable = false,
    }

    local menu_props = {
        type = "menu_danmaku",
        title = "在此处输入番剧名称",
        search_style = "palette",
        search_debounce = "submit",
        search_suggestion = parse_title(),
        on_search = { "script-message-to", mp.get_script_name(), "search-anime-event" },
        footnote = "使用enter或ctrl+enter进行搜索",
        items = items
    }
    local json_props = utils.format_json(menu_props)
    mp.commandv("script-message-to", "uosc", "open-menu", json_props)
end

function open_input_menu()
    if uosc_available then
        open_input_menu_uosc()
    elseif input_loaded then
        open_input_menu_get()
    end
end

-- 打开弹幕源添加管理菜单
function open_add_menu_get()
    mp.commandv('script-message-to', 'console', 'disable')
    input.get({
        prompt = 'Input url:',
        submit = function(text)
            input.terminate()
            mp.commandv("script-message-to", mp.get_script_name(), "add-source-event", text)
        end
    })
end

function open_add_menu_uosc()
    local sources = {}
    for url, source in pairs(DANMAKU.sources) do
        if source.fname then
            local item = {title = url, value = url, keep_open = true,}
            if source.from == "api_server" then
                if source.blocked then
                    item.hint = "来源：弹幕服务器（已屏蔽）"
                    item.actions = {{icon = "check", name = "unblock"},}
                else
                    item.hint = "来源：弹幕服务器（未屏蔽）"
                    item.actions = {{icon = "not_interested", name = "block"},}
                end
            else
                item.hint = "来源：用户添加"
                item.actions = {{icon = "delete", name = "delete"},}
            end
            table.insert(sources, item)
        end
    end
    local menu_props = {
        type = "menu_source",
        title = "在此输入源地址url",
        search_style = "palette",
        search_debounce = "submit",
        on_search = { "script-message-to", mp.get_script_name(), "add-source-event" },
        footnote = "使用enter或ctrl+enter进行添加",
        items = sources,
        item_actions_place = "outside",
        callback = {mp.get_script_name(), 'setup-danmaku-source'},
    }
    local json_props = utils.format_json(menu_props)
    mp.commandv("script-message-to", "uosc", "open-menu", json_props)
end

function open_add_menu()
    if uosc_available then
        open_add_menu_uosc()
    elseif input_loaded then
        open_add_menu_get()
    end
end

-- 打开弹幕内容菜单
function open_content_menu(pos)
    local items = {}
    local time_pos = pos or mp.get_property_native("time-pos")
    local duration = mp.get_property_number("duration", 0)

    if COMMENTS ~= nil then
        for _, event in ipairs(COMMENTS) do
            local text = event.clean_text:gsub("^m%s[mbl%s%-%d%.]+$", ""):gsub("^%s*(.-)%s*$", "%1")
            local delay = get_delay_for_time(DELAYS, event.start_time)
            local start_time = event.start_time + delay
            local end_time = event.end_time + delay
            if text and text ~= "" and start_time >= 0 and start_time <= duration then
                table.insert(items, {
                    title = abbr_str(text, 60),
                    hint = seconds_to_time(start_time),
                    value = { "seek", start_time, "absolute" },
                    active = time_pos >= start_time and time_pos <= end_time,
                })
            end
        end
    end

    local menu_props = {
        type = "menu_content",
        title = "弹幕内容",
        footnote = "使用 / 打开搜索",
        items = items
    }
    local json_props = utils.format_json(menu_props)

    if uosc_available then
        mp.commandv("script-message-to", "uosc", "open-menu", json_props)
    elseif input_loaded then
        open_menu_select(items, true)
    end
end

local menu_items_config = {
    bold = { title = "粗体", hint = options.bold, original = options.bold,
        footnote = "true / false", },
    fontsize = { title = "大小", hint = options.fontsize, original = options.fontsize,
        scope = { min = 0, max = math.huge }, footnote = "请输入整数(>=0)", },
    outline = { title = "描边", hint = options.outline, original = options.outline,
        scope = { min = 0.0, max = 4.0 }, footnote = "输入范围：(0.0-4.0)" },
    shadow = { title = "阴影", hint = options.shadow, original = options.shadow,
        scope = { min = 0, max = math.huge }, footnote = "请输入整数(>=0)", },
    scrolltime = { title = "速度", hint = options.scrolltime, original = options.scrolltime,
        scope = { min = 1, max = math.huge }, footnote = "请输入整数(>=1)", },
    opacity = { title = "透明度", hint = options.opacity, original = options.opacity,
        scope = { min = 0, max = 1 }, footnote = "输入范围：0（完全透明）到1（不透明）", },
    displayarea = { title = "弹幕显示范围", hint = options.displayarea, original = options.displayarea,
        scope = { min = 0.0, max = 1.0 }, footnote = "显示范围(0.0-1.0)", },
}
-- 创建一个包含键顺序的表，这是样式菜单的排布顺序
local ordered_keys = {"bold", "fontsize", "outline", "shadow", "scrolltime", "opacity", "displayarea"}

-- 设置弹幕样式菜单
function add_danmaku_setup(actived, status)
    if not uosc_available then
        show_message("无uosc UI框架，不支持使用该功能", 2)
        return
    end

    local items = {}
    for _, key in ipairs(ordered_keys) do
        local config = menu_items_config[key]
        local item_config = {
            title = config.title,
            hint = "目前：" .. tostring(config.hint),
            active = key == actived,
            keep_open = true,
            selectable = true,
        }
        if config.hint ~= config.original then
            local original_str = tostring(config.original)
            item_config.actions = {{icon = "refresh", name = key, label = "恢复默认配置 < " .. original_str .. " >"}}
        end
        table.insert(items, item_config)
    end

    local menu_props = {
        type = "menu_style",
        title = "弹幕样式",
        search_style = "disabled",
        footnote = "样式更改仅在本次播放生效",
        item_actions_place = "outside",
        items = items,
        callback = { mp.get_script_name(), 'setup-danmaku-style'},
    }

    local actions = "open-menu"
    if status ~= nil then
        -- msg.info(status)
        if status == "updata" then
            -- "updata" 模式会保留输入框文字
            menu_props.title = "  " .. menu_items_config[actived]["footnote"]
            actions = "update-menu"
        elseif status == "refresh" then
            -- "refresh" 模式会清除输入框文字
            menu_props.title = "  " .. menu_items_config[actived]["footnote"]
        elseif status == "error" then
            menu_props.title = "输入非数字字符或范围出错"
            -- 创建一个定时器，在1秒后触发回调函数，删除搜索栏错误信息
            mp.add_timeout(1.0, function() add_danmaku_setup(actived, "updata") end)
        end
        menu_props.search_style = "palette"
        menu_props.search_debounce = "submit"
        menu_props.footnote = menu_items_config[actived]["footnote"] or ""
        menu_props.on_search = { "script-message-to", mp.get_script_name(), "setup-danmaku-style", actived }
    end

    local json_props = utils.format_json(menu_props)
    mp.commandv("script-message-to", "uosc", actions, json_props)
end

-- 设置弹幕源延迟菜单
function danmaku_delay_setup(source_url)
    if not uosc_available then
        show_message("无uosc UI框架，不支持使用该功能", 2)
        return
    end

    local sources = {}
    for url, source in pairs(DANMAKU.sources) do
        if source.fname and not source.blocked then
            local delay = 0
            if source.delay_segments then
                for _, seg in ipairs(source.delay_segments) do
                    if seg.start == 0 then
                        delay = seg.delay or 0
                        break
                    end
                end
            end
            local item = {title = url, value = url, keep_open = true,}
            item.hint = "当前弹幕源延迟:" .. string.format("%.1f", delay + 1e-10) .. "秒"
            item.active = url == source_url
            table.insert(sources, item)
        end
    end

    local menu_props = {
        type = "menu_delay",
        title = "弹幕源延迟设置",
        search_style = "disabled",
        items = sources,
        callback = {mp.get_script_name(), 'setup-source-delay'},
    }
    if source_url ~= nil then
        menu_props.title = "请输入数字，单位（秒）/ 或者按照形如\"14m15s\"的格式输入分钟数加秒数"
        menu_props.search_style = "palette"
        menu_props.search_debounce = "submit"
        menu_props.on_search = { "script-message-to", mp.get_script_name(), "setup-source-delay", source_url }
    end

    local json_props = utils.format_json(menu_props)
    mp.commandv("script-message-to", "uosc", "open-menu", json_props)
end


-- 总集合弹幕菜单
function open_add_total_menu_uosc()
    local items = {}
    local total_menu_items_config = {
        { title = "弹幕搜索", action = "open_search_danmaku_menu" },
        { title = "从源添加弹幕", action = "open_add_source_menu" },
        { title = "弹幕源延迟设置", action = "open_source_delay_menu" },
        { title = "弹幕样式", action = "open_setup_danmaku_menu" },
        { title = "弹幕内容", action = "open_content_danmaku_menu" },
    }


    if DANMAKU.anime and DANMAKU.episode then
        local episode = DANMAKU.episode:gsub("%s.-$","")
        episode = episode:match("^(第.*[话回集]+)%s*") or episode
        items[#items + 1] = {
            title = string.format("已关联弹幕：%s-%s", DANMAKU.anime, episode),
            bold = true,
            italic = true,
            keep_open = true,
            selectable = false,
        }
    end

    for _, config in ipairs(total_menu_items_config) do
        table.insert(items, {
            title = config.title,
            value = { "script-message-to", mp.get_script_name(), config.action },
            keep_open = false,
            selectable = true,
        })
    end

    local menu_props = {
        type = "menu_total",
        title = "弹幕设置",
        search_style = "disabled",
        items = items,
    }
    local json_props = utils.format_json(menu_props)
    mp.commandv("script-message-to", "uosc", "open-menu", json_props)
end

function open_add_total_menu_select()
    local item_titles, item_values = {}, {}
    local total_menu_items_config = {
        { title = "弹幕搜索", action = "open_search_danmaku_menu" },
        { title = "从源添加弹幕", action = "open_add_source_menu" },
        { title = "弹幕内容", action = "open_content_danmaku_menu" },
    }
    for i, config in ipairs(total_menu_items_config) do
        item_titles[i] = config.title
        item_values[i] = { "script-message-to", mp.get_script_name(), config.action }
    end

    mp.commandv('script-message-to', 'console', 'disable')
    input.select({
        prompt = '选择:',
        items = item_titles,
        submit = function(id)
            mp.commandv(unpack(item_values[id]))
        end,
    })
end

function open_add_total_menu()
    if uosc_available then
        open_add_total_menu_uosc()
    elseif input_loaded then
        open_add_total_menu_select()
    end
end

mp.commandv(
    "script-message-to",
    "uosc",
    "set-button",
    "danmaku",
    utils.format_json({
        icon = "search",
        tooltip = "弹幕搜索",
        command = "script-message open_search_danmaku_menu",
    })
)

mp.commandv(
    "script-message-to",
    "uosc",
    "set-button",
    "danmaku_source",
    utils.format_json({
        icon = "add_box",
        tooltip = "从源添加弹幕",
        command = "script-message open_add_source_menu",
    })
)

mp.commandv(
    "script-message-to",
    "uosc",
    "set-button",
    "danmaku_styles",
    utils.format_json({
        icon = "palette",
        tooltip = "弹幕样式",
        command = "script-message open_setup_danmaku_menu",
    })
)

mp.commandv(
    "script-message-to",
    "uosc",
    "set-button",
    "danmaku_delay",
    utils.format_json({
        icon = "more_time",
        tooltip = "弹幕源延迟设置",
        command = "script-message open_source_delay_menu",
    })
)

mp.commandv(
    "script-message-to",
    "uosc",
    "set-button",
    "danmaku_menu",
    utils.format_json({
        icon = "grid_view",
        tooltip = "弹幕设置",
        command = "script-message open_add_total_menu",
    })
)

mp.commandv(
    "script-message-to",
    "uosc",
    "set-button",
    "danmaku_source_select",
    utils.format_json({
        icon = "source",
        tooltip = "选择弹幕源",
        command = "script-message open_danmaku_source_menu",
    })
)

mp.register_script_message('uosc-version', function()
    uosc_available = true
end)

mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "off")
mp.register_script_message("set", function(prop, value)
    if prop ~= "show_danmaku" then
        return
    end

    if value == "on" then
        ENABLED = true
        set_danmaku_visibility(true)
        if COMMENTS == nil then
            local path = mp.get_property("path")
            init(path)
        else
            show_loaded()
            show_danmaku_func()
        end
    else
        show_message("关闭弹幕", 2)
        ENABLED = false
        set_danmaku_visibility(false)
        hide_danmaku_func()
    end

    mp.commandv("script-message-to", "uosc", "set", "show_danmaku", value)
end)

-- 注册函数给 uosc 按钮使用
mp.register_script_message("search-anime-event", function(query)
    if uosc_available then
        mp.commandv("script-message-to", "uosc", "close-menu", "menu_danmaku")
    end
    local name, class = query:match("^(.-)%s*|%s*(.-)%s*$")
    if name and class then
        query_extra(name, class)
    else
        get_animes(query)
    end
end)
mp.register_script_message("search-episodes-event", function(animeTitle, bangumiId, source_server, original_query)
    if uosc_available then
        mp.commandv("script-message-to", "uosc", "close-menu", "menu_anime")
    end
    get_episodes(animeTitle, bangumiId, source_server, original_query)
end)

-- Register script message to show the input menu
mp.register_script_message("load-danmaku", function(animeTitle, episodeTitle, episodeId, source_server)
    ENABLED = true
    DANMAKU.anime = animeTitle
    DANMAKU.episode = episodeTitle

    -- 如果有指定服务器，临时设置使用该服务器
    if source_server and source_server ~= "" then
        -- 保存原始服务器设置
        local original_servers = options.api_servers
        local original_server = options.api_server

        -- 临时设置为指定服务器
        options.api_servers = source_server
        options.api_server = source_server

        set_episode_id(episodeId, source_server, true)

        -- 恢复原始服务器设置
        options.api_servers = original_servers
        options.api_server = original_server
    else
        set_episode_id(episodeId, nil, true)
    end
end)

mp.register_script_message("add-source-event", function(query)
    if uosc_available then
        mp.commandv("script-message-to", "uosc", "close-menu", "menu_source")
    end
    ENABLED = true
    add_danmaku_source(query, true)
end)

mp.register_script_message("open_setup_danmaku_menu", function()
    if uosc_available then
        mp.commandv("script-message-to", "uosc", "close-menu", "menu_total")
    end
    add_danmaku_setup()
end)
mp.register_script_message("open_content_danmaku_menu", function()
    if uosc_available then
        mp.commandv("script-message-to", "uosc", "close-menu", "menu_total")
    end
    open_content_menu()
end)

mp.register_script_message("setup-danmaku-style", function(query, text)
    local event = utils.parse_json(query)
    if event ~= nil then
        -- item点击 或 图标点击
        if event.type == "activate" then
            if not event.action then
                if ordered_keys[event.index] == "bold" then
                    options.bold = not options.bold
                    menu_items_config.bold.hint = options.bold and "true" or "false"
                end
                -- "updata" 模式会保留输入框文字
                add_danmaku_setup(ordered_keys[event.index], "updata")
                return
            else
                -- msg.info("event.action：" .. event.action)
                options[event.action] = menu_items_config[event.action]["original"]
                menu_items_config[event.action]["hint"] = options[event.action]
                add_danmaku_setup(event.action, "updata")
                if event.action == "fontsize" or event.action == "scrolltime" then
                    load_danmaku(true)
                end
            end
        end
    else
        -- 数值输入
        if text == nil or text == "" then
            return
        end
        local newText, _ = text:gsub("%s", "") -- 移除所有空白字符
        if tonumber(newText) ~= nil and menu_items_config[query]["scope"] ~= nil then
            local num = tonumber(newText)
            local min_num = menu_items_config[query]["scope"]["min"]
            local max_num = menu_items_config[query]["scope"]["max"]
            if num and min_num <= num and num <= max_num then
                if string.match(menu_items_config[query]["footnote"], "整数") then
                    -- 输入范围为整数时向下取整
                    num = tostring(math.floor(num))
                end
                options[query] = tostring(num)
                menu_items_config[query]["hint"] = options[query]
                -- "refresh" 模式会清除输入框文字
                add_danmaku_setup(query, "refresh")
                if query == "fontsize" or query == "scrolltime" then
                    load_danmaku(true, true)
                end
                return
            end
        end
        add_danmaku_setup(query, "error")
    end
end)

mp.register_script_message('setup-danmaku-source', function(json)
    local event = utils.parse_json(json)
    if event.type == 'activate' then

        if event.action == "delete" then
            local rm = DANMAKU.sources[event.value]["fname"]
            if rm and file_exists(rm) and DANMAKU.sources[event.value]["from"] ~= "user_local" then
                os.remove(rm)
            end
            DANMAKU.sources[event.value] = nil
            remove_source_from_history(event.value)
            mp.commandv("script-message-to", "uosc", "close-menu", "menu_source")
            open_add_menu_uosc()
            load_danmaku(true)
        end

        if event.action == "block" then
            DANMAKU.sources[event.value]["blocked"] = true
            add_source_to_history(event.value, DANMAKU.sources[event.value])
            mp.commandv("script-message-to", "uosc", "close-menu", "menu_source")
            open_add_menu_uosc()
            load_danmaku(true)
        end

        if event.action == "unblock" then
            DANMAKU.sources[event.value]["blocked"] = false
            add_source_to_history(event.value, DANMAKU.sources[event.value])
            mp.commandv("script-message-to", "uosc", "close-menu", "menu_source")
            open_add_menu_uosc()
            load_danmaku(true)
        end
    end
end)

mp.register_script_message("setup-source-delay", function(query, text)
    local event = utils.parse_json(query)
    if event ~= nil then
        -- item点击
        if event.type == "activate" then
            danmaku_delay_setup(event.value)
        end
    else
        -- 数值输入
        if text == nil or text == "" then
            return
        end
        local newText, _ = text:gsub("%s", "") -- 移除所有空白字符
        local num = tonumber(newText)
        local delay_segments = shallow_copy(DANMAKU.sources[query]["delay_segments"] or {})
        for i = #delay_segments, 1, -1 do
            if delay_segments[i].start == 0 then
                table.remove(delay_segments, i)
            end
        end
        if num ~= nil then
            table.insert(delay_segments, 1, { start = 0, delay = tonumber(num) })
            DANMAKU.sources[query]["delay_segments"] = delay_segments
            add_source_to_history(query, DANMAKU.sources[query])
            mp.commandv("script-message-to", "uosc", "close-menu", "menu_delay")
            danmaku_delay_setup(query)
            load_danmaku(true, true)
        elseif newText:match("^%-?%d+m%d+s$") then
            local minutes, seconds = string.match(newText, "^(%-?%d+)m(%d+)s$")
            minutes = tonumber(minutes)
            seconds = tonumber(seconds)
            if minutes < 0 then seconds = -seconds end
            table.insert(delay_segments, 1, { start = 0, delay = 60 * minutes + seconds })
            DANMAKU.sources[query]["delay_segments"] = delay_segments
            add_source_to_history(query, DANMAKU.sources[query])
            mp.commandv("script-message-to", "uosc", "close-menu", "menu_delay")
            danmaku_delay_setup(query)
            load_danmaku(true, true)
        end
    end
end)

local MATCH_CACHE = {}
local MATCH_CACHE_PATH = mp.command_native({"expand-path", options.match_cache_path})
local MAX_CACHE_ENTRIES = 100
local CACHE_EXPIRE_DAYS = 30

-- 加载匹配结果缓存
local function load_match_cache()
    local cache_json = read_file(MATCH_CACHE_PATH)
    if cache_json then
        local cache = utils.parse_json(cache_json) or {}
        local current_time = os.time()
        local cleaned_cache = {}
        local count = 0

        -- 清理过期缓存
        for key, entry in pairs(cache) do
            if entry.timestamp and (current_time - entry.timestamp) < (CACHE_EXPIRE_DAYS * 24 * 3600) then
                cleaned_cache[key] = entry
                count = count + 1
            end
        end

        -- 如果超过最大条目数，删除最旧的
        if count > MAX_CACHE_ENTRIES then
            local sorted = {}
            for key, entry in pairs(cleaned_cache) do
                table.insert(sorted, {key = key, timestamp = entry.timestamp})
            end
            table.sort(sorted, function(a, b) return a.timestamp < b.timestamp end)

            for i = 1, count - MAX_CACHE_ENTRIES do
                cleaned_cache[sorted[i].key] = nil
            end
        end

        MATCH_CACHE = cleaned_cache
    end
end

-- 保存匹配结果缓存
local function save_match_cache()
    write_json_file(MATCH_CACHE_PATH, MATCH_CACHE)
end

local function get_cache_key(file_path, file_name)
    local path = file_path or mp.get_property("path")
    local name = file_name or mp.get_property("filename/no-ext")

    if path and not is_protocol(path) then
        path = normalize(path)
    end

    local file_info = utils.file_info(path)
    local file_size = file_info and file_info.size or 0
    local file_mtime = file_info and file_info.mtime or 0

    return (name or path) .. "|" .. tostring(file_size) .. "|" .. tostring(file_mtime)
end

local function save_match_to_cache(file_path, file_name, server, matches, match_type, danmaku_counts)
    local cache_key = get_cache_key(file_path, file_name)
    if not MATCH_CACHE[cache_key] then
        MATCH_CACHE[cache_key] = {
            timestamp = os.time(),
            servers = {}
        }
    end

    MATCH_CACHE[cache_key].servers[server] = {
        matches = matches,
        match_type = match_type,
        timestamp = os.time(),
        danmaku_counts = danmaku_counts or {}
    }

    save_match_cache()
end

local function get_match_from_cache(file_path, file_name, server)
    local cache_key = get_cache_key(file_path, file_name)
    if MATCH_CACHE[cache_key] and MATCH_CACHE[cache_key].servers[server] then
        local entry = MATCH_CACHE[cache_key].servers[server]
        local current_time = os.time()
        if (current_time - entry.timestamp) < (CACHE_EXPIRE_DAYS * 24 * 3600) then
            -- 确保danmaku_counts的key都是string类型
            local danmaku_counts = {}
            if entry.danmaku_counts then
                for k, v in pairs(entry.danmaku_counts) do
                    danmaku_counts[tostring(k)] = v
                end
            end
            return entry.matches, entry.match_type, danmaku_counts
        end
    end
    return nil, nil, nil
end

local function get_all_servers_matches(file_path, file_name, callback)
    local servers = get_api_servers()
    local all_results = {}
    local completed = 0
    local total = #servers

    -- 检查是否是dandanplay服务器
    local is_dandanplay = false
    for _, server in ipairs(servers) do
        if server:find("api%.dandanplay%.") then
            is_dandanplay = true
            break
        end
    end

    local function process_results()
        completed = completed + 1
        if completed == total then
            if callback then callback(all_results) end
        end
    end

    local function get_danmaku_count(episodeId, server, callback)
        if not episodeId then
            callback(0)
            return
        end
        local url = server .. "/api/v2/comment/" .. episodeId .. "?withRelated=false&chConvert=0"
        local args = make_danmaku_request_args("GET", url)
        if args then
            call_cmd_async(args, function(error, json)
                local count = 0
                if not error and json then
                    local success, parsed = pcall(utils.parse_json, json)
                    if success and parsed and parsed.count then
                        count = tonumber(parsed.count) or 0
                    end
                end
                callback(count)
            end)
        else
            callback(0)
        end
    end

    for _, server in ipairs(servers) do
        -- 先检查缓存
        local cached_matches, cached_type, cached_counts = get_match_from_cache(file_path, file_name, server)
        if cached_matches then
            all_results[server] = {
                matches = cached_matches,
                match_type = cached_type,
                danmaku_counts = cached_counts or {},
                from_cache = true
            }
            process_results()
        else
            if is_dandanplay and server:find("api%.dandanplay%.") then
                local title, season_num, episode_num = parse_title()
                episode_num = episode_num or 1
                local cleaned_title = title
                if cleaned_title then
                    cleaned_title = cleaned_title:gsub("%[.-%]", "")
                    cleaned_title = cleaned_title:gsub("%s+", " ")
                    cleaned_title = cleaned_title:gsub("^%s+", ""):gsub("%s+$", "")
                end
                local encoded_query = url_encode(cleaned_title or "")
                local endpoint = "/api/v2/search/anime?keyword=" .. encoded_query
                local url = server .. endpoint
                local args = make_danmaku_request_args("GET", url)

                if args then
                    call_cmd_async(args, function(error, json)
                        local matches = {}
                        if not error and json then
                            local success, parsed = pcall(utils.parse_json, json)
                            if success and parsed and parsed.animes then
                                for _, anime in ipairs(parsed.animes) do
                                    table.insert(matches, {
                                        animeTitle = anime.animeTitle,
                                        bangumiId = anime.bangumiId or anime.animeId,
                                        typeDescription = anime.typeDescription,
                                        match_type = "anime"
                                    })
                                end
                            end
                        end
                        -- anime类型暂时不获取弹幕数（需要先获取剧集列表）
                        all_results[server] = {
                            matches = matches,
                            match_type = "anime",
                            danmaku_counts = {},
                            from_cache = false
                        }
                        save_match_to_cache(file_path, file_name, server, matches, "anime", {})
                        process_results()
                    end)
                else
                    all_results[server] = {
                        matches = {},
                        match_type = "anime",
                        danmaku_counts = {},
                        from_cache = false
                    }
                    process_results()
                end
            else
                local hash = nil
                local file_info = utils.file_info(file_path)
                if file_info and file_info.size > 16 * 1024 * 1024 then
                    local file, err = io.open(normalize(file_path), 'rb')
                    if file and not err then
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
                local url = server .. endpoint
                local args = make_danmaku_request_args("POST", url, {
                    ["Content-Type"] = "application/json"
                }, body)

                if args then
                    call_cmd_async(args, function(error, json)
                        local matches = {}
                        if not error and json then
                            local success, parsed = pcall(utils.parse_json, json)
                            if success and parsed and parsed.matches then
                                for _, match in ipairs(parsed.matches) do
                                    -- 从episodeId计算episodeNumber（如果缺失）
                                    local ep_num = match.episodeNumber
                                    if not ep_num and match.episodeId then
                                        ep_num = tonumber(match.episodeId) % 1000
                                    end

                                    table.insert(matches, {
                                        animeTitle = match.animeTitle,
                                        episodeTitle = match.episodeTitle,
                                        episodeId = match.episodeId,
                                        episodeNumber = ep_num,
                                        match_type = "file"
                                    })
                                end
                            end
                        end

                        -- 异步获取弹幕数
                        local danmaku_counts = {}
                        local count_requests = 0
                        local total_matches = #matches

                        if total_matches == 0 then
                            all_results[server] = {
                                matches = matches,
                                match_type = "file",
                                danmaku_counts = {},
                                from_cache = false
                            }
                            save_match_to_cache(file_path, file_name, server, matches, "file", {})
                            process_results()
                        else
                            for i, match in ipairs(matches) do
                                if match.episodeId then
                                    -- 将episodeId转换为string作为key
                                    local episode_id_str = tostring(match.episodeId)
                                    get_danmaku_count(match.episodeId, server, function(count)
                                        danmaku_counts[episode_id_str] = count
                                        count_requests = count_requests + 1
                                        if count_requests == total_matches then
                                            all_results[server] = {
                                                matches = matches,
                                                match_type = "file",
                                                danmaku_counts = danmaku_counts,
                                                from_cache = false
                                            }
                                            save_match_to_cache(file_path, file_name, server, matches, "file", danmaku_counts)
                                            process_results()
                                        end
                                    end)
                                else
                                    count_requests = count_requests + 1
                                    if count_requests == total_matches then
                                        all_results[server] = {
                                            matches = matches,
                                            match_type = "file",
                                            danmaku_counts = danmaku_counts,
                                            from_cache = false
                                        }
                                        save_match_to_cache(file_path, file_name, server, matches, "file", danmaku_counts)
                                        process_results()
                                    end
                                end
                            end
                        end
                    end)
                else
                    all_results[server] = {
                        matches = {},
                        match_type = "file",
                        danmaku_counts = {},
                        from_cache = false
                    }
                    process_results()
                end
            end
        end
    end
end

-- 构建菜单项的函数
local function build_menu_items(all_results, servers, show_refresh)
    local items = {}

    -- 添加刷新按钮
    if show_refresh then
        table.insert(items, {
            title = "🔄 刷新匹配结果",
            hint = "清除缓存并重新加载",
            value = {
                "script-message-to",
                mp.get_script_name(),
                "refresh-danmaku-matches"
            },
            keep_open = false,
            selectable = true,
        })
        table.insert(items, {
            title = "",
            italic = true,
            keep_open = true,
            selectable = false,
        })
    end

    for _, server in ipairs(servers) do
        local result = all_results[server]
        local server_id = extract_server_identifier(server)
        local match_count = result and #result.matches or 0

        -- 创建服务器项（不可选择，仅作为标题）
        table.insert(items, {
            title = "━━━ " .. server_id .. " (" .. match_count .. "个匹配) ━━━",
            hint = server,
            italic = true,
            keep_open = true,
            selectable = false,
        })

        -- 添加匹配结果作为可选项
        if result and result.matches and #result.matches > 0 then
            -- 获取当前文件的集数
            local _, _, current_episode_num = parse_title()

            for _, match in ipairs(result.matches) do
                local match_title = ""
                local match_hint = ""
                local danmaku_count = 0

                -- 获取弹幕数（episodeId需要转换为string）
                if result.danmaku_counts and match.episodeId then
                    local episode_id_str = tostring(match.episodeId)
                    danmaku_count = result.danmaku_counts[episode_id_str] or 0
                end

                if result.match_type == "anime" then
                    match_title = "  └─ " .. (match.animeTitle or "未知")
                    -- 显示集数信息（从当前文件解析）
                    local hint_parts = {}
                    if current_episode_num then
                        table.insert(hint_parts, "第" .. current_episode_num .. "集")
                    end
                    if match.typeDescription then
                        table.insert(hint_parts, match.typeDescription)
                    end
                    match_hint = table.concat(hint_parts, " | ")
                    if danmaku_count > 0 then
                        match_hint = match_hint .. (match_hint ~= "" and " | " or "") .. danmaku_count .. "条弹幕"
                    end
                else
                    -- 优先使用当前文件的集数，如果没有则使用匹配结果的episodeNumber
                    local ep_num = current_episode_num or match.episodeNumber
                    if not ep_num and match.episodeId then
                        ep_num = tonumber(match.episodeId) % 1000
                    end

                    match_title = "  └─ " .. (match.animeTitle or "未知") .. " - " .. (match.episodeTitle or "未知")
                    match_hint = "第" .. (ep_num or "?") .. "集"
                    if danmaku_count > 0 then
                        match_hint = match_hint .. " | " .. danmaku_count .. "条弹幕"
                    end
                end

                table.insert(items, {
                    title = match_title,
                    hint = match_hint,
                    value = {
                        "script-message-to",
                        mp.get_script_name(),
                        "switch-danmaku-source",
                        server,
                        result.match_type,
                        utils.format_json(match)
                    },
                    keep_open = false,
                    selectable = true,
                })
            end
        else
            table.insert(items, {
                title = "  └─ 无匹配结果",
                italic = true,
                keep_open = true,
                selectable = false,
            })
        end
    end

    return items
end

-- 打开弹幕源选择菜单
function open_danmaku_source_menu(force_refresh)
    if not uosc_available then
        show_message("无uosc UI框架，不支持使用该功能", 2)
        return
    end

    local path = mp.get_property("path")
    local file_name = mp.get_property("filename/no-ext")

    if not path or not file_name then
        show_message("无法获取文件信息", 2)
        return
    end

    local items = {}
    local servers = get_api_servers()
    local menu_props = {
        type = "menu_danmaku_source",
        title = "选择弹幕源",
        search_style = "disabled",
        items = items,
    }

    -- 如果强制刷新，清除缓存
    if force_refresh then
        local cache_key = get_cache_key(path, file_name)
        if MATCH_CACHE[cache_key] then
            MATCH_CACHE[cache_key] = nil
            save_match_cache()
            msg.info("已清除缓存，重新加载匹配结果")
        end
    end

    -- 先尝试从缓存加载
    local cached_results = {}
    local has_cached = false
    for _, server in ipairs(servers) do
        local cached_matches, cached_type, cached_counts = get_match_from_cache(path, file_name, server)
        if cached_matches then
            cached_results[server] = {
                matches = cached_matches,
                match_type = cached_type,
                danmaku_counts = cached_counts or {},
                from_cache = true
            }
            has_cached = true
        end
    end

    -- 如果有缓存，立即显示
    if has_cached and not force_refresh then
        items = build_menu_items(cached_results, servers, true)
        menu_props.items = items
        local json_props = utils.format_json(menu_props)
        mp.commandv("script-message-to", "uosc", "open-menu", json_props)

        -- 在后台更新缓存（如果有新数据）
        get_all_servers_matches(path, file_name, function(all_results)
            -- 检查是否有更新
            local has_update = false
            for _, server in ipairs(servers) do
                local cached = cached_results[server]
                local fresh = all_results[server]
                if fresh and cached then
                    if #fresh.matches ~= #cached.matches then
                        has_update = true
                        break
                    end
                elseif fresh and not cached then
                    has_update = true
                    break
                end
            end

            -- 如果有更新，刷新菜单
            if has_update then
                items = build_menu_items(all_results, servers, true)
                menu_props.items = items
                json_props = utils.format_json(menu_props)
                mp.commandv("script-message-to", "uosc", "update-menu", json_props)
            end
        end)
    else
        -- 没有缓存或强制刷新，显示加载提示
        table.insert(items, {
            title = "正在加载匹配结果...",
            italic = true,
            keep_open = true,
            selectable = false,
            align = "center",
        })
        local json_props = utils.format_json(menu_props)
        mp.commandv("script-message-to", "uosc", "open-menu", json_props)

        -- 获取所有服务器的匹配结果
        get_all_servers_matches(path, file_name, function(all_results)
            items = build_menu_items(all_results, servers, true)

            -- 更新菜单
            menu_props.items = items
            local json_props = utils.format_json(menu_props)
            mp.commandv("script-message-to", "uosc", "update-menu", json_props)
        end)
    end
end

-- 切换弹幕源
mp.register_script_message("switch-danmaku-source", function(server, match_type, match_json)
    local match = utils.parse_json(match_json)
    if not match then
        show_message("解析匹配结果失败", 2)
        return
    end

    ENABLED = true

    if match_type == "anime" then
        -- 需要先获取剧集列表
        if match.bangumiId then
            DANMAKU.anime = match.animeTitle
            local title, season_num, episode_num = parse_title()
            episode_num = episode_num or 1

            -- 获取剧集信息
            local endpoint = "/api/v2/bangumi/" .. match.bangumiId
            local url = server .. endpoint
            local args = make_danmaku_request_args("GET", url, nil, nil)

            if args then
                call_cmd_async(args, function(error, json)
                    if not error and json then
                        local success, parsed = pcall(utils.parse_json, json)
                        if success and parsed and parsed.bangumi and parsed.bangumi.episodes then
                            local episodes = parsed.bangumi.episodes

                            -- 根据episodeNumber匹配，而不是数组索引
                            local target_episode = nil
                            for _, episode in ipairs(episodes) do
                                local ep_num = tonumber(episode.episodeNumber)
                                if ep_num and ep_num == tonumber(episode_num) then
                                    target_episode = episode
                                    break
                                end
                            end

                            if target_episode then
                                DANMAKU.episode = target_episode.episodeTitle or "未知标题"
                                set_episode_id(target_episode.episodeId, server, true)
                                msg.info("✅ 匹配成功: " .. DANMAKU.anime .. " 第" .. episode_num .. "集")
                            else
                                msg.warn("未找到对应集数: 第" .. episode_num .. "集 (总共" .. #episodes .. "集)")
                                show_message("未找到对应集数: 第" .. episode_num .. "集", 3)

                                -- 显示可用的集数范围
                                if #episodes > 0 then
                                    local min_ep = tonumber(episodes[1].episodeNumber) or 1
                                    local max_ep = min_ep
                                    for _, ep in ipairs(episodes) do
                                        local ep_num = tonumber(ep.episodeNumber)
                                        if ep_num then
                                            if ep_num < min_ep then min_ep = ep_num end
                                            if ep_num > max_ep then max_ep = ep_num end
                                        end
                                    end
                                    msg.info("可用集数范围: " .. min_ep .. " - " .. max_ep)
                                end
                            end
                        else
                            msg.error("获取剧集列表失败: 数据格式错误")
                            show_message("获取剧集列表失败", 3)
                        end
                    else
                        msg.error("获取剧集列表失败: " .. (error or "未知错误"))
                        show_message("获取剧集列表失败", 3)
                    end
                end)
            else
                msg.error("无法生成请求参数")
                show_message("无法生成请求参数", 3)
            end
        end
    else
        -- 直接使用episodeId
        DANMAKU.anime = match.animeTitle
        DANMAKU.episode = match.episodeTitle
        if match.episodeId then
            set_episode_id(match.episodeId, server, true)
        end
    end

    if uosc_available then
        mp.commandv("script-message-to", "uosc", "close-menu", "menu_danmaku_source")
    end
end)

-- 初始化时加载缓存
load_match_cache()

-- 注册脚本消息
mp.register_script_message("open_danmaku_source_menu", function()
    open_danmaku_source_menu(false)
end)

-- 刷新匹配结果
mp.register_script_message("refresh-danmaku-matches", function()
    if uosc_available then
        mp.commandv("script-message-to", "uosc", "close-menu", "menu_danmaku_source")
    end
    -- 延迟一下再打开，确保菜单已关闭
    mp.add_timeout(0.1, function()
        open_danmaku_source_menu(true)
    end)
end)

-- 自动加载匹配结果
mp.register_script_message("auto_load_danmaku_matches", function()
    if not uosc_available then
        return
    end

    local path = mp.get_property("path")
    local file_name = mp.get_property("filename/no-ext")

    if not path or not file_name or is_protocol(path) then
        return
    end

    -- 在后台静默加载匹配结果到缓存
    get_all_servers_matches(path, file_name, function(all_results)
        -- 匹配结果已自动保存到缓存
        msg.verbose("自动加载匹配结果完成，共 " .. #get_api_servers() .. " 个服务器")
    end)
end)
