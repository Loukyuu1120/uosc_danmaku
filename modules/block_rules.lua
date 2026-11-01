local regex = require('modules/regex')
local M = {}
local kinds = {[0] = 'text', [1] = 'regex', [2] = 'user', [3] = 'color'}
local prefixes = {t = 'text', r = 'regex', u = 'user', c = 'color'}
M.types = {text = 0, regex = 1, user = 2, color = 3}
M.prefixes = {text = 't', regex = 'r', user = 'u', color = 'c'}
M.labels = {text = '文本', regex = '正则', user = '用户', color = '颜色', lua = 'Lua 模式'}

function M.decode(text)
    return text:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"'):gsub('&apos;', "'"):gsub('&amp;', '&')
end

function M.xml_entries(content)
    local nodes, entries, at = {}, {}, 1
    for first, attrs, body, following in content:gmatch('()<item%s+([^>]-)>(.-)</item>()') do
        if first > at then nodes[#nodes + 1] = {raw_text = content:sub(at, first - 1)} end
        local enabled = attrs:match('enabled%s*=%s*"([^"]*)"') or attrs:match("enabled%s*=%s*'([^']*)'")
        local prefix, pattern = body:match('^%s*([truc])=(.*)$')
        if prefix and (enabled == 'true' or enabled == 'false') then
            local entry = {kind = prefixes[prefix], pattern = M.decode(pattern), enabled = enabled == 'true'}
            entries[#entries + 1], nodes[#nodes + 1] = entry, {entry = entry, attributes = attrs}
        else nodes[#nodes + 1] = {raw_text = content:sub(first, following - 1)} end
        at = following
    end
    if at <= #content then nodes[#nodes + 1] = {raw_text = content:sub(at)} end
    return entries, nodes
end

function M.json_rows(data)
    if type(data) ~= 'table' then return nil end
    local rows = data.rules ~= nil and data.rules or data
    if type(rows) ~= 'table' then return nil end
    for key in pairs(rows) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 or key > #rows then return nil end
    end
    return rows, data.rules ~= nil and data or nil
end

function M.from_json(raw)
    if type(raw) ~= 'table' or type(raw.filter) ~= 'string' or not kinds[tonumber(raw.type)] then return nil end
    return {kind = kinds[tonumber(raw.type)], pattern = raw.filter, enabled = raw.opened == true, meta = raw}
end

function M.input(text, default_kind)
    text = tostring(text or ''):match('^%s*(.-)%s*$')
    local prefix, pattern = text:match('^([truc])=(.*)$')
    return prefix and prefixes[prefix] or default_kind or 'text', prefix and pattern or text
end

local function color(value)
    if type(value) == 'number' then return value >= 0 and value <= 0xFFFFFF and math.floor(value) or nil end
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$')
    local hex = value:match('^#(%x+)$') or value:match('^0[xX](%x+)$')
    if not hex and value:match('^%x%x%x%x%x%x$') then hex = value end
    local n = hex and tonumber(hex, 16) or tonumber(value)
    return n and n >= 0 and n <= 0xFFFFFF and math.floor(n) or nil
end

-- Bilibili XML identifies senders by CRC32 rather than their numeric UID.
-- Hash a UID supplied by an exported user rule; never try to recover a UID.
local crc_table
local function xor(a, b)
    local result, bit = 0, 1
    while a > 0 or b > 0 do
        if a % 2 ~= b % 2 then result = result + bit end
        a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
    end
    return result
end
function M.user_hash(uid)
    if not crc_table then
        crc_table = {}
        for i = 0, 255 do
            local c = i
            for _ = 1, 8 do c = c % 2 == 1 and xor(math.floor(c / 2), 0xEDB88320) or math.floor(c / 2) end
            crc_table[i] = c
        end
    end
    local crc = 0xFFFFFFFF
    for i = 1, #uid do crc = xor(math.floor(crc / 256), crc_table[xor(crc % 256, uid:byte(i))]) end
    return string.format('%08x', xor(crc, 0xFFFFFFFF))
end

function M.validate(kind, pattern)
    if type(pattern) ~= 'string' or pattern == '' then return nil, '规则不能为空' end
    if kind == 'regex' then return regex.compile(pattern) end
    if kind == 'color' and not color(pattern) then return nil, '颜色应为 #RRGGBB、0xRRGGBB 或十进制 RGB 值' end
    if kind == 'lua' then local ok, err = pcall(string.find, '', pattern); if not ok then return nil, err end end
    return true
end

function M.compile(entry)
    local compiled, err = M.validate(entry.kind, entry.pattern)
    if not compiled then return nil, err end
    local rule = {kind = entry.kind, pattern = entry.pattern}
    if entry.kind == 'regex' then rule.regex = compiled
    elseif entry.kind == 'color' then rule.color = color(entry.pattern)
    elseif entry.kind == 'user' and entry.pattern:match('^%d+$') then rule.user_hash = M.user_hash(entry.pattern) end
    return rule
end

local function hash_equal(a, b)
    if not a or not b or tostring(a) == '' or tostring(a) == '0' or tostring(b) == '' or tostring(b) == '0' then return false end
    a, b = tostring(a):lower():gsub('^0+', ''), tostring(b):lower():gsub('^0+', '')
    return a == b
end

function M.matches(rule, text, record)
    if rule.kind == 'text' then return text:find(rule.pattern, 1, true) ~= nil end
    if rule.kind == 'lua' then local ok, found = pcall(string.find, text, rule.pattern); return ok and found ~= nil end
    if rule.kind == 'regex' then
        rule.cache = rule.cache or {}
        if rule.cache[text] ~= nil then return rule.cache[text] end
        local matched, err = regex.test(rule.regex, text)
        rule.cached = (rule.cached or 0) + 1
        if rule.cached > 256 then rule.cache, rule.cached = {}, 1 end
        rule.cache[text] = matched
        return matched, err
    end
    record = record or {}
    if rule.kind == 'color' then return math.floor(math.max(0, math.min(tonumber(record.color) or 0xFFFFFF, 0xFFFFFF))) == rule.color end
    if rule.kind == 'user' then
        for _, field in ipairs({'user_id', 'user_name', 'user_hash'}) do
            if record[field] ~= nil and tostring(record[field]) ~= '' and tostring(record[field]) ~= '0' and tostring(record[field]) == rule.pattern then return true end
        end
        if hash_equal(record.user_hash, rule.pattern) then return true end
        return rule.user_hash ~= nil and hash_equal(record.user_hash, rule.user_hash)
    end
    return false
end

return M
