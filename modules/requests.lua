-- A generation owns every request and delayed action for one playing file.
-- Aborted subprocess callbacks can still arrive; checking the generation is essential.
local generation, active_count = 0, 0
local requests, timers = {}, {}

function playback_request_generation()
    return generation
end

local function curl_failure(status, http_status)
    if http_status and http_status >= 400 then
        local reasons = {[401] = '鉴权失败', [403] = '服务器拒绝访问', [404] = '接口不存在',
            [429] = '请求过于频繁', [522] = '源站连接超时'}
        return 'HTTP ' .. http_status .. '：' .. (reasons[http_status] or '服务器请求失败')
    end
    local reasons = {[6] = '域名解析失败', [7] = '无法连接服务器', [28] = '请求超时',
        [35] = 'TLS 握手失败', [52] = '服务器未返回响应', [60] = '证书校验失败'}
    return reasons[status] or ('请求失败（curl ' .. tostring(status) .. '）')
end

local function update_running()
    async_running = active_count > 0
end

function add_playback_timeout(seconds, callback)
    local owner = generation
    local timer
    timer = mp.add_timeout(seconds, function()
        timers[timer] = nil
        if owner == generation then callback() end
    end)
    local kill = timer.kill
    function timer:kill()
        timers[self] = nil
        kill(self)
    end
    timers[timer] = true
    return timer
end

function invalidate_playback_requests()
    generation = generation + 1
    local previous = requests
    requests = {}
    active_count = 0
    update_running()
    for _, cancel in pairs(previous) do cancel() end
    for timer in pairs(timers) do timer:kill() end
    timers = {}
end

-- Apply the configured proxy at the subprocess boundary, including update
-- requests. Copy arguments because the same request can be retried later.
local function with_curl_proxy(args)
    local command = tostring(args[1] or ''):gsub('\\', '/'):match('([^/]+)$'):lower()
    if command ~= 'curl' and command ~= 'curl.exe' then return args end
    local result, has_proxy = {}, false
    for i, value in ipairs(args) do
        result[i] = value
        if value == '-x' or value == '--proxy' or tostring(value):match('^%-%-proxy=') then has_proxy = true end
    end
    if not has_proxy and options and options.proxy and options.proxy ~= '' then
        -- Insert before a possible -- argument terminator.
        table.insert(result, 2, options.proxy)
        table.insert(result, 2, '--proxy')
    end
    return result
end

function call_cmd_async(args, callback, settings)
    args = with_curl_proxy(args)
    settings = settings or {}
    local owner, done = generation, false
    local id
    local playback_only = settings.playback_only ~= false
    if playback_only then active_count = active_count + 1; update_running() end

    local function finish(success, result, err)
        if done then return end
        done = true
        if id then requests[id] = nil end
        if owner ~= generation and playback_only then return end
        if playback_only then active_count = math.max(0, active_count - 1); update_running() end
        local output = result and type(result.stdout) == 'string' and result.stdout or ''
        local http_status = tonumber(output:match('\n__UOSC_HTTP_STATUS__:(%d+)%s*$'))
        output = output:gsub('\n__UOSC_HTTP_STATUS__:%d+%s*$', '')
        local metadata = {status = result and result.status, http_status = http_status}
        if not success or not result or result.status ~= 0 then
            if tostring(args[1]):lower():match('curl%.?e?x?e?$') then
                callback(curl_failure(result and result.status, http_status), nil, metadata)
                return
            end
            local detail = err or (result and ((result.stderr or '') .. (result.stdout or ''))) or ''
            callback('Calling failed. Exit code: ' .. tostring(result and result.status or 'unknown') ..
                ' Error: ' .. tostring(detail), nil)
        else
            callback(nil, output, metadata)
        end
    end

    id = mp.command_native_async({
        name = 'subprocess', capture_stderr = true, capture_stdout = true,
        playback_only = playback_only, args = args,
    }, finish)

    local function cancel()
        if done then return end
        done = true
        requests[id] = nil
        if playback_only and owner == generation then
            active_count = math.max(0, active_count - 1)
            update_running()
        end
        mp.abort_async_command(id)
    end
    if not done and playback_only then requests[id] = cancel end
    return cancel
end

mp.register_event('start-file', invalidate_playback_requests)
mp.register_event('end-file', invalidate_playback_requests)
mp.register_event('shutdown', invalidate_playback_requests)
