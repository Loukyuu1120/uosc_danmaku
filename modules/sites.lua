local utils = require('mp.utils')

require('sites/bilibili')
require('sites/bahamut')
require('sites/iqiyi')
require('sites/mgtv')
require('sites/tencentvideo')
require('sites/youku')

function save_danmaku_xml(url, content)
    save_danmaku_memory(url, parse_xml_danmaku(content), 'user_custom')
end

function save_site_danmaku_json(url, content)
    save_danmaku_memory(url, parse_json_danmaku(content), 'user_custom')
end

function load_site_danmaku(url, callback)
    local host = url:match('^https?://([^/:]+)')
    if not host then return false end
    host = host:lower()
    local loaders = {
        {'bilibili.com', load_danmaku_for_bilibili},
        {'bilivideo.com', load_danmaku_for_bilibili},
        {'bilivideo.cn', load_danmaku_for_bilibili},
        {'gamer.com.tw', load_danmaku_for_bahamut},
        {'bahamut.akamaized.net', load_danmaku_for_bahamut},
        {'iqiyi.com', load_danmaku_for_iqiyi},
        {'mgtv.com', load_danmaku_for_mgtv},
        {'v.qq.com', load_danmaku_for_tencent},
        {'youku.com', load_danmaku_for_youku},
    }
    for _, entry in ipairs(loaders) do
        if host == entry[1] or host:sub(-#entry[1] - 1) == '.' .. entry[1] then
            local completed = false
            entry[2](url, function(success)
                if completed then return end
                completed = true
                callback(success)
            end)
            return true
        end
    end
    return false
end

-- Bounded asynchronous workers replace upstream's coroutine polling monitor.
function parallel_requests(items, build_args, on_response, on_complete, settings)
    settings = settings or {}
    local next_index, pending, stopped, finished = 1, 0, false, false
    local cancellations = {}
    local pump
    pump = function()
        if stopped or finished then return end
        while pending < (settings.concurrency or 3) and next_index <= #items do
            local index = next_index
            next_index = index + 1
            local item = items[index]
            local args = build_args(item)
            if args then
                pending = pending + 1
                local settled, abort, timeout = false
                local function settle(err, output)
                    if settled or stopped then return end
                    settled = true
                    if timeout then timeout:kill() end
                    cancellations[index] = nil
                    pending = pending - 1
                    local ok, detail = pcall(on_response, item, err, output)
                    if not ok then require('mp.msg').warn(tostring(detail)) end
                    pump()
                end
                abort = call_cmd_async(args, settle)
                if not settled then
                    timeout = add_playback_timeout(settings.per_request_timeout or 15, function()
                        if abort then abort() end
                        settle('request timeout', nil)
                    end)
                    cancellations[index] = function() abort(); timeout:kill() end
                end
            else
                on_response(item, 'no request arguments', nil)
            end
        end
        if next_index > #items and pending == 0 and not finished then
            finished = true
            if on_complete then on_complete() end
        end
    end
    pump()
    return function()
        stopped = true
        for _, cancel in pairs(cancellations) do cancel() end
    end
end
