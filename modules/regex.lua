-- Small UTF-8 regular-expression matcher for imported blocking rules.
-- Supports groups, alternatives, classes, repetition, anchors and lookarounds.
-- Backreferences use a bounded capture matcher; unsupported extensions are never interpreted
-- as Lua patterns. Memoization and a work limit keep bad rules from hanging mpv.
local M = {}

local function chars(text)
    local result = {}
    for c in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do result[#result + 1] = c end
    return result
end

local function utf8(code)
    if code < 128 then return string.char(code) end
    if code < 2048 then return string.char(192 + math.floor(code / 64), 128 + code % 64) end
    if code < 65536 then return string.char(224 + math.floor(code / 4096), 128 + math.floor(code / 64) % 64, 128 + code % 64) end
    return string.char(240 + math.floor(code / 262144), 128 + math.floor(code / 4096) % 64, 128 + math.floor(code / 64) % 64, 128 + code % 64)
end

local function word(c) return c ~= nil and c:match('^[A-Za-z0-9_]$') ~= nil end

function M.compile(pattern)
    if type(pattern) ~= 'string' or #pattern > 4096 then return nil, '正则表达式过长' end
    local ok, compiled = pcall(function()
        local tokens, at, serial, depth = chars(pattern), 1, 0, 0
        local captures, references = 0, {}
        local flags = {i = false, m = false, s = false}
        local function node(kind, fields)
            serial = serial + 1
            assert(serial <= 1024, '正则表达式过于复杂')
            fields = fields or {}; fields.kind, fields.id = kind, serial
            return fields
        end
        local function take() local c = tokens[at]; at = at + 1; return c end
        local function escape(in_class)
            local c = take(); assert(c, '转义符后缺少字符')
            if not in_class and c:match('^[1-9]$') then
                local digits = c
                while tokens[at] and tokens[at]:match('^%d$') do digits = digits .. take() end
                local group = tonumber(digits)
                references[#references + 1] = group
                return node('backreference', {group = group})
            end
            if c:match('^[dDsSwW]$') then return node('shorthand', {value = c}) end
            if not in_class and (c == 'b' or c == 'B') then return node('boundary', {negative = c == 'B'}) end
            if c == 'x' or c == 'u' then
                local count, hex = c == 'x' and 2 or 4, ''
                for _ = 1, count do local h = take(); assert(h and h:match('^%x$'), '无效的十六进制转义'); hex = hex .. h end
                local code = tonumber(hex, 16)
                if code >= 0xD800 and code <= 0xDBFF then
                    assert(take() == '\\' and take() == 'u', '缺少 UTF-16 低代理项')
                    local low = ''; for _ = 1, 4 do local h = take(); assert(h and h:match('^%x$'), '无效的 UTF-16 转义'); low = low .. h end
                    low = tonumber(low, 16); assert(low >= 0xDC00 and low <= 0xDFFF, '无效的 UTF-16 低代理项')
                    code = 0x10000 + (code - 0xD800) * 1024 + low - 0xDC00
                end
                assert(code < 0xD800 or code > 0xDFFF, '无效的 Unicode 转义')
                return node('literal', {value = utf8(code)})
            end
            assert(not c:match('^[1-9pkKPAzZG]$'), '不支持反向引用或该正则扩展')
            local controls = {n = '\n', r = '\r', t = '\t', f = '\f', v = '\11', ['0'] = '\0', b = '\8'}
            return node('literal', {value = controls[c] or c})
        end
        local expression
        local function atom()
            local c = take(); assert(c, '缺少表达式')
            if c == '\\' then return escape(false) end
            if c == '.' then return node('any') end
            if c == '^' then return node('start') end
            if c == '$' then return node('finish') end
            if c == '[' then
                local negate = tokens[at] == '^'; if negate then at = at + 1 end
                local items = {}
                while tokens[at] and tokens[at] ~= ']' do
                    local first = take()
                    first = first == '\\' and escape(true) or node('literal', {value = first})
                    if tokens[at] == '-' and tokens[at + 1] and tokens[at + 1] ~= ']' then
                        at = at + 1
                        local last = take(); last = last == '\\' and escape(true) or node('literal', {value = last})
                        assert(first.kind == 'literal' and last.kind == 'literal' and first.value <= last.value, '无效的字符范围')
                        first = node('range', {first = first.value, last = last.value})
                    end
                    items[#items + 1] = first
                end
                assert(take() == ']', '字符组缺少 ]')
                return node('class', {items = items, negative = negate})
            end
            if c == '(' then
                depth = depth + 1; assert(depth <= 64, '正则表达式嵌套过深')
                local look, negative, behind, group
                if tokens[at] ~= '?' then captures = captures + 1; group = captures end
                if tokens[at] == '?' then
                    at = at + 1
                    local modifier = take()
                    if modifier == '=' or modifier == '!' then look, negative = true, modifier == '!'
                    elseif modifier == '<' then
                        modifier = take(); assert(modifier == '=' or modifier == '!', '不支持该分组扩展')
                        look, behind, negative = true, true, modifier == '!'
                    elseif modifier ~= ':' then
                        local enabled = true
                        while modifier and modifier ~= ')' do
                            if modifier == '-' then enabled = false
                            else assert(flags[modifier] ~= nil, '不支持该正则标志'); flags[modifier] = enabled end
                            modifier = take()
                        end
                        assert(modifier == ')', '正则标志未闭合')
                        depth = depth - 1; return node('empty')
                    end
                end
                local child = expression(); assert(take() == ')', '分组缺少 )'); depth = depth - 1
                return look and node('look', {child = child, negative = negative, behind = behind})
                    or group and node('capture', {child = child, group = group}) or child
            end
            assert(not c:match('^[)*+?{}|]$'), '无效的正则运算符')
            return node('literal', {value = c})
        end
        local function sequence()
            local items = {}
            while tokens[at] and tokens[at] ~= ')' and tokens[at] ~= '|' do
                local child = atom()
                local c, minimum, maximum = tokens[at]
                if c == '*' then minimum, maximum, at = 0, math.huge, at + 1
                elseif c == '+' then minimum, maximum, at = 1, math.huge, at + 1
                elseif c == '?' then minimum, maximum, at = 0, 1, at + 1
                elseif c == '{' then
                    at = at + 1
                    local digits = ''; while tokens[at] and tokens[at]:match('^%d$') do digits = digits .. take() end
                    minimum = tonumber(digits); assert(minimum, '无效的重复次数')
                    maximum = minimum
                    if tokens[at] == ',' then
                        at = at + 1; digits = ''
                        while tokens[at] and tokens[at]:match('^%d$') do digits = digits .. take() end
                        maximum = tonumber(digits) or math.huge
                    end
                    assert(take() == '}' and maximum >= minimum and minimum <= 10000 and (maximum == math.huge or maximum <= 10000), '无效的重复范围')
                end
                if minimum then
                    child = node('repeat', {child = child, minimum = minimum, maximum = maximum})
                    if tokens[at] == '?' then at = at + 1 end -- Greediness does not change a boolean match.
                end
                items[#items + 1] = child
            end
            return node('sequence', {items = items})
        end
        expression = function()
            local items = {sequence()}
            while tokens[at] == '|' do at = at + 1; items[#items + 1] = sequence() end
            return #items == 1 and items[1] or node('alternative', {items = items})
        end
        local root = expression(); assert(at > #tokens, '多余的闭合符号')
        for _, group in ipairs(references) do assert(group <= captures, '不存在的分组引用') end
        return {root = root, flags = flags, nodes = serial, captures = captures, backreferences = #references > 0}
    end)
    if not ok then return nil, tostring(compiled) end
    return compiled
end

function M.test(compiled, text)
    if type(text) ~= 'string' or #text > 65536 then return false, '弹幕超出正则匹配长度限制' end
    local ok, matched = pcall(function()
        local input, cache, work = chars(text), {}, 0
        local flags = compiled.flags
        local function same(a, b) return flags.i and a:lower() == b:lower() or a == b end
        local function accepts(n, c)
            if not c then return false end
            if n.kind == 'literal' then return same(c, n.value) end
            if n.kind == 'range' then
                local value, first, last = c, n.first, n.last
                if flags.i then value, first, last = value:lower(), first:lower(), last:lower() end
                return value >= first and value <= last
            end
            if n.kind == 'shorthand' then
                local kind = n.value:lower()
                local result = kind == 'd' and c:match('^%d$') ~= nil
                    or kind == 's' and (c:match('^%s$') ~= nil or c == '　') or kind == 'w' and word(c)
                if n.value ~= kind then return not result end
                return result
            end
            if n.kind == 'class' then
                local found = false
                for _, item in ipairs(n.items) do if accepts(item, c) then found = true; break end end
                return n.negative and not found or not n.negative and found
            end
            return false
        end
        if compiled.backreferences then
            assert(#input <= 8192, '带分组引用的弹幕超出长度限制')
            local function tick() work = work + 1; assert(work <= 100000, '正则匹配超出运算限制') end
            local function state_key(state)
                local key = {tostring(state.position)}
                for group = 1, compiled.captures do
                    local value = state.captures[group]
                    key[#key + 1] = value and (#value .. ':' .. value) or '-'
                end
                return table.concat(key, '|')
            end
            local function copied(captures)
                local result = {}; for k, v in pairs(captures) do result[k] = v end; return result
            end
            local walk_capture
            walk_capture = function(n, state)
                tick()
                local position, kind, results, seen = state.position, n.kind, {}, {}
                local function push(next_state)
                    tick(); local key = state_key(next_state)
                    if not seen[key] then seen[key] = true; results[#results + 1] = next_state end
                end
                local function advance(p) push({position = p, captures = state.captures}) end
                if kind == 'sequence' then
                    local states = {state}
                    for _, child in ipairs(n.items) do
                        local following, unique = {}, {}
                        for _, current in ipairs(states) do
                            for _, next_state in ipairs(walk_capture(child, current)) do
                                local key = state_key(next_state)
                                if not unique[key] then unique[key] = true; following[#following + 1] = next_state end
                            end
                        end
                        states = following; if #states == 0 then break end
                    end
                    for _, current in ipairs(states) do push(current) end
                elseif kind == 'alternative' then
                    for _, child in ipairs(n.items) do for _, current in ipairs(walk_capture(child, state)) do push(current) end end
                elseif kind == 'capture' then
                    for _, current in ipairs(walk_capture(n.child, state)) do
                        local values = copied(current.captures)
                        values[n.group] = table.concat(input, '', position, current.position - 1)
                        push({position = current.position, captures = values})
                    end
                elseif kind == 'backreference' then
                    local value = state.captures[n.group]
                    if value then
                        local letters, found = chars(value), true
                        for i, c in ipairs(letters) do
                            if not input[position + i - 1] or not same(c, input[position + i - 1]) then found = false; break end
                        end
                        if found then advance(position + #letters) end
                    end
                elseif kind == 'repeat' then
                    local states = {state}
                    if n.minimum == 0 then push(state) end
                    for count = 1, math.min(n.maximum, #input + n.minimum + 1) do
                        local following, unique = {}, {}
                        for _, current in ipairs(states) do
                            for _, next_state in ipairs(walk_capture(n.child, current)) do
                                local key = state_key(next_state)
                                if not unique[key] then unique[key] = true; following[#following + 1] = next_state end
                            end
                        end
                        if #following == 0 then break end
                        if count >= n.minimum then for _, current in ipairs(following) do push(current) end end
                        local unchanged = #following == #states
                        if unchanged then for _, current in ipairs(states) do if not unique[state_key(current)] then unchanged = false; break end end end
                        if unchanged and count >= n.minimum then break end
                        states = following
                    end
                elseif kind == 'look' then
                    local matches = {}
                    if n.behind then
                        for start = 1, position do
                            for _, current in ipairs(walk_capture(n.child, {position = start, captures = state.captures})) do
                                if current.position == position then matches[#matches + 1] = current end
                            end
                        end
                    else matches = walk_capture(n.child, state) end
                    if n.negative then if #matches == 0 then advance(position) end
                    else for _, current in ipairs(matches) do push({position = position, captures = current.captures}) end end
                elseif kind == 'start' then
                    if position == 1 or flags.m and input[position - 1] == '\n' then advance(position) end
                elseif kind == 'finish' then
                    if position == #input + 1 or (flags.m or position == #input) and input[position] == '\n' then advance(position) end
                elseif kind == 'boundary' then
                    if (word(input[position - 1]) ~= word(input[position])) ~= n.negative then advance(position) end
                elseif kind == 'empty' then advance(position)
                elseif kind == 'any' then
                    if input[position] and (flags.s or input[position] ~= '\n' and input[position] ~= '\r') then advance(position + 1) end
                elseif accepts(n, input[position]) then advance(position + 1) end
                return results
            end
            for start = 1, #input + 1 do
                if #walk_capture(compiled.root, {position = start, captures = {}}) > 0 then return true end
            end
            return false
        end
        local walk
        walk = function(n, position)
            work = work + 1; assert(work <= 200000, '正则匹配超出运算限制')
            cache[n.id] = cache[n.id] or {}
            if cache[n.id][position] then return cache[n.id][position] end
            local result, seen = {}, {}
            local function push(p) if not seen[p] then seen[p] = true; result[#result + 1] = p end end
            local kind = n.kind
            if kind == 'sequence' then
                local positions = {position}
                for _, item in ipairs(n.items) do
                    local following, unique = {}, {}
                    for _, p in ipairs(positions) do
                        for _, q in ipairs(walk(item, p)) do if not unique[q] then unique[q] = true; following[#following + 1] = q end end
                    end
                    positions = following; if #positions == 0 then break end
                end
                for _, p in ipairs(positions) do push(p) end
            elseif kind == 'capture' then
                for _, p in ipairs(walk(n.child, position)) do push(p) end
            elseif kind == 'alternative' then
                for _, item in ipairs(n.items) do for _, p in ipairs(walk(item, position)) do push(p) end end
            elseif kind == 'repeat' then
                local positions = {position}
                if n.minimum == 0 then push(position) end
                for count = 1, math.min(n.maximum, #input + n.minimum + 1) do
                    local following, unique = {}, {}
                    for _, p in ipairs(positions) do
                        for _, q in ipairs(walk(n.child, p)) do
                            if not unique[q] then unique[q] = true; following[#following + 1] = q end
                        end
                    end
                    if #following == 0 then break end
                    if count >= n.minimum then for _, p in ipairs(following) do push(p) end end
                    local unchanged = #following == #positions
                    if unchanged then for _, p in ipairs(positions) do if not unique[p] then unchanged = false; break end end end
                    if unchanged and count >= n.minimum then break end
                    positions = following
                end
            elseif kind == 'start' then
                if position == 1 or flags.m and input[position - 1] == '\n' then push(position) end
            elseif kind == 'finish' then
                if position == #input + 1 or (flags.m or position == #input) and input[position] == '\n' then push(position) end
            elseif kind == 'boundary' then
                local boundary = word(input[position - 1]) ~= word(input[position])
                if boundary ~= n.negative then push(position) end
            elseif kind == 'look' then
                local found = false
                if n.behind then
                    for start = 1, position do
                        for _, stop in ipairs(walk(n.child, start)) do if stop == position then found = true; break end end
                        if found then break end
                    end
                else found = #walk(n.child, position) > 0 end
                if found ~= (n.negative or false) then push(position) end
            elseif kind == 'empty' then push(position)
            elseif kind == 'any' then
                if input[position] and (flags.s or input[position] ~= '\n' and input[position] ~= '\r') then push(position + 1) end
            elseif accepts(n, input[position]) then push(position + 1) end
            cache[n.id][position] = result
            return result
        end
        for start = 1, #input + 1 do if #walk(compiled.root, start) > 0 then return true end end
        return false
    end)
    if not ok then return false, tostring(matched) end
    return matched
end

return M
