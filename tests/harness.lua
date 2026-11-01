package.path = './?.lua;' .. package.path
local getenv = os.getenv
os.getenv = function(name) if name == 'TEMP' then return test_root end; return getenv(name) end
unpack = unpack or table.unpack
events, messages, hooks, observers, pending, timers, overlays, commands = {}, {}, {}, {}, {}, {}, {}, {}
properties = {platform = 'windows', path = test_root .. '/Show S01E01.mkv',
    ['filename/no-ext'] = 'Show S01E01', filename = 'Show S01E01.mkv',
    ['media-title'] = 'Show S01E01', ['time-pos'] = 0, ['osd-width'] = 1920,
    ['osd-height'] = 1080, vf = {}, ['track-list'] = {},
    ['current-tracks/video'] = {image = false}, duration = 120, ['container-fps'] = 24}
local function noop() end
local function timer(callback)
    local t = {callback = callback, enabled = true, timeout = 0}
    function t:kill() self.enabled = false end
    function t:resume() self.enabled = true end
    timers[#timers + 1] = t
    return t
end
mp = {
    commandv = function(...) commands[#commands + 1] = {...} end,
    get_script_name = function() return 'uosc_danmaku' end,
    get_script_directory = function() return test_root .. '/uosc_danmaku' end,
    get_property = function(name, default) return properties[name] or default end,
    get_property_native = function(name, default) return properties[name] or default end,
    get_property_number = function(name, default) return properties[name] or default end,
    set_property_native = function(name, value) properties[name] = value end,
    set_property_bool = function(name, value) properties[name] = value end,
    get_opt = function() return nil end,
    add_key_binding = noop, get_time = function() return 1 end,
    register_event = function(name, callback)
        events[name] = events[name] or {}; table.insert(events[name], callback)
    end,
    register_script_message = function(name, callback) messages[name] = callback end,
    add_hook = function(name, priority, callback) hooks[#hooks + 1] = callback end,
    observe_property = function(name, kind, callback) observers[callback] = name end,
    unobserve_property = function(callback) observers[callback] = nil end,
    add_timeout = function(seconds, callback, disabled)
        local t = timer(callback); t.timeout = seconds; t.enabled = not disabled; return t
    end,
    add_periodic_timer = function() error('unexpected render polling timer') end,
    command_native = function(command)
        if command[1] == 'expand-path' then return command[2]:gsub('^~~', test_root) end
        if command[1] == 'normalize-path' then return command[2] end
        if command.name == 'subprocess' then error('unexpected blocking subprocess') end
        return ''
    end,
    command_native_async = function(command, callback)
        pending[#pending + 1] = {command = command, callback = callback}
        return #pending
    end,
    abort_async_command = function(id) pending[id].aborted = true end,
    create_osd_overlay = function()
        local o = {data = '', updates = 0}
        function o:update() self.removed = false; self.updates = self.updates + 1 end
        function o:remove() self.removed = true end
        overlays[#overlays + 1] = o
        return o
    end,
}
package.preload['mp.msg'] = function() return setmetatable({}, {__index = function() return noop end}) end
package.preload['mp.utils'] = function() return {
    parse_json = py_parse_json, format_json = py_format_json, file_info = py_file_info,
    getpid = function() return 123 end,
    join_path = function(a,b) return a .. '/' .. b end,
    split_path = function(path) return path:match('^(.-)([^/\\]+)$') end,
    readdir = function() return {} end,
} end
package.preload['mp.options'] = function() return {read_options = noop} end
package.preload['mp.input'] = function() return {
    get = function(args) if args.items then last_select = args else last_input = args end end, select = function(args) last_select = args end,
    terminate = noop,
} end
function fire(name)
    for _, callback in ipairs(events[name] or {}) do callback({}) end
end
function respond(id, body, status)
    pending[id].callback(true, {status = status or 0, stdout = body, stderr = ''})
end
function flush_timers()
    local snapshot = {}; for i,t in ipairs(timers) do snapshot[i] = t end
    for _,t in ipairs(snapshot) do if t.enabled then t.enabled = false; t.callback() end end
end
