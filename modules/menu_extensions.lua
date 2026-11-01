local utils = require('mp.utils')
local rule_labels = require('modules/block_rules').labels
local unpack = unpack or table.unpack

function open_blacklist_menu_uosc(action, index)
    -- ---------- 编辑菜单：搜索框预填原文，回车提交，Esc 取消 ----------
    if action == "edit" then
        local entry = blacklist_get_state().entries[index]
        if not entry then return end
        mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json({
            type = "menu_blacklist_edit",
            title = "修改规则（原样写入）",
            search_style = "palette", search_debounce = "submit",
            search_suggestion = entry.pattern,
            footnote = "在输入框中修改规则后回车提交；Esc 取消",
            items = {
                { title = "↩️ 返回黑名单（不修改）", selectable = true,
                  value = { "script-message-to", mp.get_script_name(), "open_blacklist_menu" } },
            },
            on_search = { "script-message-to", mp.get_script_name(),
                          "blacklist-deal", "edit-submit", tostring(index) },
        }))
        return
    end
    -- ------------- 主菜单 -------------
    local state = blacklist_get_state()
    local items = {}
    if not state.ext then
        items[#items + 1] = {
            title = "blacklist_path 的扩展名不受支持",
            hint = "请配置为 .txt / .xml / .json 文件",
            selectable = false, muted = true, keep_open = true,
        }
    elseif not state.exists then
        items[#items + 1] = {
            title = "新建弹幕屏蔽词文件（." .. state.ext .. "）",
            hint = abbr_str(state.path or "", 60), selectable = true,
            value = { "script-message-to", mp.get_script_name(), "blacklist-deal", "create" },
        }
    elseif state.parse_failed then
        items[#items + 1] = {
            title = "文件解析失败，可能不是标准 " .. state.ext:upper() .. " 格式",
            hint = "为避免覆盖原内容，请手动选择重置",
            selectable = false, muted = true, keep_open = true,
        }
        items[#items + 1] = {
            title = "重置为标准格式（覆盖原文件）",
            hint = "原内容将丢失，请谨慎操作", selectable = true,
            value = { "script-message-to", mp.get_script_name(), "blacklist-deal", "reset" },
        }
    else
        for i, entry in ipairs(state.entries) do
            local hint = state.ext == "txt" and ("#" .. i)
                or ((entry.error and '规则无效' or entry.enabled and "已启用" or "已停用") .. " · #" .. i)
            local actions
            if state.ext == "txt" then
                actions = { { name = "delete", icon = "delete", label = "删除此规则" } }
            else
                actions = {
                    { name = "edit",   icon = "edit", label = "修改此规则" },
                    { name = "toggle", icon = entry.enabled and "toggle_on" or "toggle_off",
                      label = entry.enabled and "停用此规则" or "启用此规则" },
                    { name = "delete", icon = "delete", label = "删除此规则" },
                }
            end
            items[#items + 1] = {
                title = abbr_str(entry.pattern, 60), hint = (rule_labels[entry.kind] or "文本") .. " · " .. hint,
                muted = state.ext ~= "txt" and not entry.enabled or nil,
                actions = actions, keep_open = true,
            }
        end
        if #state.entries == 0 then
            items[#items + 1] = {
                title = "暂无屏蔽词", hint = "在输入框输入后回车添加",
                selectable = false, muted = true, italic = true, keep_open = true,
            }
        end
    end
    -- 格式提示（内联）
    local hint
    if state.ext == "txt" then
        hint = "txt：每行一条，支持 lua 正则"
    elseif state.ext == "xml" then
        hint = 't=文本，r=正则，u=用户，c=#颜色'
    else
        hint = 't=文本，r=正则，u=用户，c=#颜色'
    end
    local footnote = state.exists and not state.parse_failed
        and ("输入屏蔽词回车添加；用条目按钮修改 / 启停 / 删除 ｜ " .. hint)
        or (not state.exists and "点击“新建”创建文件；或直接输入后回车（自动创建）" or hint)
    mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json({
        type = "menu_blacklist", title = "请在此输入需添加的弹幕规则",
        search_style = "palette", search_debounce = "submit",
        on_search = { "script-message-to", mp.get_script_name(), "blacklist-deal", "add" },
        footnote = footnote, items = items,
        item_actions_place = "outside",
        callback = { mp.get_script_name(), "blacklist-deal" },
    }))
end

function open_blacklist_menu_select()
    local state = blacklist_get_state()
    local titles, values = {}, {}
    local function push(t, v) titles[#titles + 1] = t; values[#values + 1] = v end
    if not state.ext then
        push("blacklist_path 的扩展名不受支持（需 .txt/.xml/.json）", nil)
    elseif not state.exists then
        push("新建黑名单文件（." .. state.ext .. "）", "create")
    elseif state.parse_failed then
        push("文件解析失败，可能不是标准 " .. state.ext:upper() .. " 格式", nil)
        push("重置为标准格式（覆盖原文件）", "reset")
    else
        push("＋ 添加屏蔽词", "add")
        for i, entry in ipairs(state.entries) do
            local status = state.ext ~= "txt" and (entry.enabled and "[启用] " or "[停用] ") or ""
            push(status .. "[" .. (rule_labels[entry.kind] or "文本") .. "] " .. abbr_str(entry.pattern, 50), { kind = "entry", index = i })
        end
        if #state.entries > 0 then push("－ 删除条目...", "delete_mode") end
    end
    push("↩️ 返回", "close")
    mp.commandv("script-message-to", "console", "disable")
    input.select({
        prompt = "黑名单编辑:",
        items = titles,
        submit = function(id)
            input.terminate()
            local action = values[id]
            if action == "create" or action == "reset" then
                local ok, message = blacklist_create_file()
                if message then show_message("[弹幕屏蔽规则] " .. message, ok and 2 or 3) end
                if ok then add_playback_timeout(0.05, open_blacklist_menu) end
            elseif action == "add" then
                mp.commandv("script-message-to", "console", "disable")
                input.get({
                    prompt = "输入屏蔽词（回车添加）:",
                    submit = function(text)
                        input.terminate()
                        local ok, message = blacklist_add_entry(text)
                        if message then show_message("[弹幕屏蔽规则] " .. message, ok and 2 or 3) end
                        if ok then add_playback_timeout(0.05, open_blacklist_menu) end
                    end,
                })
            elseif action == "delete_mode" then
                local d_titles, d_values = {}, {}
                for i, entry in ipairs(state.entries) do
                    d_titles[#d_titles + 1] = abbr_str(entry.pattern, 50)
                    d_values[#d_values + 1] = i
                end
                input.select({
                    prompt = "选择要删除的条目（立即生效）:",
                    items = d_titles,
                    submit = function(d_id)
                        input.terminate()
                        local i = d_values[d_id]
                        if i then
                            local ok, message = blacklist_delete_entry(i)
                            if message then show_message("[弹幕屏蔽规则] " .. message, ok and 2 or 3) end
                            if ok then add_playback_timeout(0.05, open_blacklist_menu) end
                        end
                    end,
                })
            elseif type(action) == "table" and action.kind == "entry" then
                local index = action.index
                local entry = state.entries[index]
                if not entry then return end
                local a_titles, a_values = {}, {}
                local function apush(t, v) a_titles[#a_titles + 1] = t; a_values[#a_values + 1] = v end
                if state.ext ~= "txt" then
                    apush("修改此规则", "edit")
                    apush(entry.enabled and "停用此规则" or "启用此规则", "toggle")
                end
                apush("删除此规则", "delete")
                apush("↩️ 返回", "back")
                input.select({
                    prompt = abbr_str(entry.pattern, 40),
                    items = a_titles,
                    submit = function(a_id)
                        input.terminate()
                        local op = a_values[a_id]
                        if op == "edit" then
                            mp.commandv("script-message-to", "console", "disable")
                            input.get({
                                prompt = "修改规则（原样写入）:",
                                default_text = entry.pattern,
                                submit = function(text)
                                    input.terminate()
                                    local ok, message = blacklist_edit_entry(index, text)
                                    if message then show_message("[弹幕屏蔽规则] " .. message, ok and 2 or 3) end
                                    if ok then add_playback_timeout(0.05, open_blacklist_menu) end
                                end,
                            })
                        else
                            local ok, message
                            if op == "toggle" then
                                ok, message = blacklist_toggle_entry(index)
                            elseif op == "delete" then
                                ok, message = blacklist_delete_entry(index)
                            elseif op == "back" then
                                add_playback_timeout(0.05, open_blacklist_menu)
                                return
                            end
                            if message then show_message("[弹幕屏蔽规则] " .. message, ok and 2 or 3) end
                            if ok then add_playback_timeout(0.05, open_blacklist_menu) end
                        end
                    end,
                })
            end
        end,
    })
end

function open_blacklist_menu()
    if not get_blacklist_path() then
        show_message("未配置 blacklist_path，黑名单编辑不可用", 3)
        return
    end
    blacklist_get_state(true)   -- 强制从磁盘重建，保证与文件一致
    if uosc_available then
        mp.commandv("script-message-to", "uosc", "close-menu", "menu_blacklist")
        open_blacklist_menu_uosc()
    elseif input_loaded then
        open_blacklist_menu_select()
    else
        show_message("无支持可用的 UI框架，不支持使用该功能", 3)
    end
end

mp.register_script_message("open_blacklist_menu", function()
    if uosc_available then
        mp.commandv("script-message-to", "uosc", "close-menu", "menu_total")
    end
    open_blacklist_menu()
end)

mp.register_script_message("blacklist-deal", function(payload, arg, extra)
    -- ① uosc 菜单回调：条目动作按钮 / 整项激活
    local event = parse_json_table(payload or "")
    if event and event.type == "activate" then
        local index = tonumber(event.index)
        if event.action == "edit" then
            if index then open_blacklist_menu_uosc("edit", index) end
        elseif event.action == "toggle" or event.action == "delete" then
            if index then
                local ok, message
                if event.action == "toggle" then
                    ok, message = blacklist_toggle_entry(index)
                else
                    ok, message = blacklist_delete_entry(index)
                end
                if message then show_message("[弹幕屏蔽规则] " .. message, ok and 2 or 3) end
                if ok then add_playback_timeout(0.05, open_blacklist_menu) end
            end
        elseif type(event.value) == "table" then
            mp.commandv(unpack(event.value))  -- 新建 / 重置整项点击（回放 value 命令）
        end
        return
    end
    -- ② palette / value 触发的模式：先取 (ok, message)，末尾统一反馈
    local mode = tostring(payload or "")
    local index = tonumber(arg)
    local ok, message
    if mode == "create" or mode == "reset" then
        ok, message = blacklist_create_file()
    elseif mode == "add" then
        ok, message = blacklist_add_entry(arg)          -- arg = palette 输入文本
    elseif mode == "edit-submit" and index then
        ok, message = blacklist_edit_entry(index, extra)
        if not ok and not message then open_blacklist_menu() return end  -- 无变更：静默返回主菜单
    end
    if message then show_message("[弹幕屏蔽规则] " .. message, ok and 2 or 3) end
    if ok then add_playback_timeout(0.05, open_blacklist_menu) end
end)
