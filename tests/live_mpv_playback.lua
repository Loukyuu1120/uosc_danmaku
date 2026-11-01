-- Run only in an isolated test config with a generated local video.
local utils = require('mp.utils')
local opts = require('mp.options')
local settings = {plugin = '', report = '', query = '躲在超市后门抽烟的两人', options_path = '', timeout = 45, menu = false}
opts.read_options(settings, 'live_mpv_playback')
package.path = settings.plugin .. '/?.lua;' .. package.path
local report, done = {requests = {}}, false
local started, selected = mp.get_time(), nil
local function finish()
    if done then return end
    done = true
    local output = assert(io.open(settings.report, 'wb'))
    output:write(utils.format_json(report)); output:close()
    mp.commandv('quit')
end
mp.add_timeout(settings.timeout, function() report.timeout = true; finish() end)
local ok, failure = pcall(dofile, settings.plugin .. '/main.lua')
if not ok then report.startup_error = tostring(failure); finish(); return end
options.api_servers = 'https://danmaku-api.152468.xyz'
if settings.options_path ~= '' then
    local source = assert(io.open(settings.options_path, 'rb'))
    local actual_options = utils.parse_json(source:read('*a')); source:close()
    for key, value in pairs(actual_options or {}) do options[key] = value end
end
report.load_more_danmaku = options.load_more_danmaku
local native_async = mp.command_native_async
mp.command_native_async = function(command, callback)
    for _, argument in ipairs(command.args or {}) do
        local endpoint = tostring(argument):match('/api/v2/([^?]+)')
        if endpoint then report.requests[#report.requests + 1] = endpoint end
    end
    return native_async(command, callback)
end
options.autoload_danmaku_matches = false
options.auto_load = false
local original_render = render_danmaku
render_danmaku = function(...)
    original_render(...)
    report.rendered = COMMENTS and #COMMENTS or 0
    report.visible = mp.get_property_native(HAS_DANMAKU)
    report.total_seconds = mp.get_time() - started
    report.load_seconds = selected and mp.get_time() - selected
    finish()
end
mp.register_event('file-loaded', function()
    if settings.menu then
        uosc_available = true
        local commandv = mp.commandv
        mp.commandv = function(...)
            local command = {...}
            if command[1] == 'script-message-to' and command[2] == 'uosc' and command[3] == 'update-menu' then
                local menu = parse_json_table(command[4])
                for _, item in ipairs(menu and menu.items or {}) do
                    if type(item.value) == 'table' and item.value[3] == 'switch-danmaku-source' and not report.first_result_seconds then
                        report.first_result_seconds = mp.get_time() - started
                        report.result_title = item.title
                        report.other_sources_pending = menu.footnote:find('其余仍在查询', 1, true) ~= nil
                        mp.add_timeout(2, finish)
                    end
                end
            end
            return commandv(...)
        end
        local get_property = mp.get_property
        mp.get_property = function(name, ...)
            if name == 'filename/no-ext' then return settings.query .. ' S1E1' end
            return get_property(name, ...)
        end
        open_danmaku_source_menu(true)
        mp.add_timeout(0.1, function() open_danmaku_source_menu(true) end)
        mp.add_timeout(0.2, function() open_danmaku_source_menu(false) end)
        return
    end
    local server = get_api_servers()[1]
    call_cmd_async(make_danmaku_request_args('GET', server .. '/api/v2/search/anime?keyword=' .. url_encode(settings.query)), function(err, json)
        if err then report.search_error = err; finish(); return end
        local data = parse_json_table(json)
        local anime = data and data.animes and data.animes[1]
        if not anime then report.search_error = 'no results'; finish(); return end
        report.title = anime.animeTitle
        call_cmd_async(make_danmaku_request_args('GET', server .. '/api/v2/bangumi/' .. anime.bangumiId), function(detail_err, detail_json)
            if detail_err then report.episode_error = detail_err; finish(); return end
            local details = parse_json_table(detail_json)
            local episodes = details and details.bangumi and details.bangumi.episodes
            local episode = episodes and episodes[1]
            if not episode then report.episode_error = 'no episodes'; finish(); return end
            report.episodes, report.episode = #episodes, episode.episodeTitle
            ENABLED = true
            DANMAKU.anime, DANMAKU.episode = anime.animeTitle, episode.episodeTitle
            selected = mp.get_time()
            set_episode_id(episode.episodeId, server, true)
        end)
    end)
end)
