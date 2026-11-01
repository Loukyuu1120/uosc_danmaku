local opt = require("mp.options")

-- 选项
options = {
    -- 单个服务器地址（保留，用于向后兼容或单服务器情况）
    api_server = "https://danmaku-api.152468.xyz",
    -- 多个服务器地址，用于并发请求
    api_servers = "",
    -- 指定 b 站和爱腾优的弹幕获取的兜底服务器地址，主要用于获取非动画弹幕
    -- 服务器可以自托管：https://github.com/lyz05/danmaku
    fallback_server = "https://dmku.hls.one",
    -- 设置 tmdb 的 API Key，用于获取非动画条目的中文信息(当搜索内容非中文时)
    -- 可以在 https://www.themoviedb.org 注册后去个人账号设置界面获取
    -- 注意：自定义此参数时还需要对获取到的 API Key 进行 base64 编码
    tmdb_api_key = "NmJmYjIxOTZkNzIyN2UyMTIzMGM3Y2YzZjQ4MDNkZGM=",
    load_more_danmaku = false,
    auto_load = false,
    auto_fallback_search = false,
    autoload_local_danmaku = false,
    autoload_for_url = false,
    -- 弹幕加载完成后开始自动匹配所有API，默认启用
    autoload_danmaku_matches = true,
    -- 下载部分url视频文件用于hash计算，默认启用
    hash_for_url = true,
    save_danmaku = false,
    danmaku_save_path = "", -- compatibility alias, applies to all media
    save_danmaku_path = "",
    save_danmaku_path_mode = "local",
    cookie_file = "",
    request_timeout = 30,
    search_history_path = "~~/danmaku-search-history.json",
    search_history_limit = 50,
    search_history_size = -1, -- upstream alias; -1 keeps search_history_limit
    message_alignment = -1, -- upstream spelling; -1 keeps message_anlignment
    user_agent = "mpv_danmaku/1.0",
    proxy = "",
    -- 使用 fps 视频滤镜，大幅提升弹幕平滑度。默认禁用
    vf_fps = false,
    -- 设置要使用的 fps 滤镜参数
    fps = "60/1.001",
    -- 指定合并重复弹幕的时间间隔的容差值，单位为秒。默认值: -1，表示禁用
    merge_tolerance = -1,
    merge_without_style = false,
    merge_fontsize_growth = 8,
    merge_fontsize_max = 100,
    -- 指定弹幕关联历史记录文件的路径，支持绝对路径和相对路径
    history_path = "~~/danmaku-history.json",
    -- 指定匹配结果缓存文件的路径，支持绝对路径和相对路径
    match_cache_path = "~~/uosc_danmaku_match_cache.json",
    open_search_danmaku_menu_key = "Ctrl+d",
    show_danmaku_keyboard_key = "j",
    -- 中文简繁转换。0-不转换，1-转换为简体，2-转换为繁体
    chConvert = 0,
    --滚动弹幕的显示时间
    scrolltime = 15,
    --固定弹幕的显示时间
    fixtime = 5,
    --字体
    fontname = "sans-serif",
    --字体大小
    fontsize = 50,
    --字体阴影
    shadow = 0,
    --字体粗体
    bold = true,
    -- 透明度：0（完全透明）到 1（不透明）
    opacity = 0.7,
    --全部弹幕的显示范围(0.0-1.0)
    displayarea = 0.85,
    --描边 0-4
    outline = 1.0,
    -- 限制屏幕中同时显示的最大弹幕数量，0 表示不限制
    max_screen_danmaku = 0,
    --指定弹幕屏蔽词文件路径(black.txt)，支持绝对路径和相对路径。文件内容以换行分隔
    --支持 lua 的正则表达式写法
    blacklist_path = "",
    --指定脚本相关消息显示的消息的对齐方式
    message_anlignment = 7,
    --指定脚本相关消息显示的消息的x轴坐标
    message_x = 30,
    --指定脚本相关消息显示的消息的y轴坐标
    message_y = 30,
    -- 自定义标题解析中的额外替换规则，内容格式为 JSON 字符串，替换模式为 lua 的 string.gsub 函数
    --! 注意：由于 mpv 的 lua 版本限制，自定义规则只支持形如 %n 的捕获组写法，即示例用法，不支持直接替换字符的写法
    title_replace = [[
       [{
           "rules": [{ "^〔(.-)〕": "%1"},{ "^.*《(.-)》": "%1" }]
       }]
    ]],
    -- 指定哈希匹配中需忽略的共享盘（挂载盘）的路径/目录。支持绝对路径和相对路径，多个路径用逗号分隔
    -- 示例：["X:", "Z:", "F:/Download/", "Download"]
    excluded_path = [[
        []
    ]],
    -- 排除指定平台的弹幕源，支持域名关键词匹配。多个平台用逗号分隔
    -- 示例：["bilibili.com", "gamer.com.tw"]
    excluded_platforms = [[
        []
    ]],
}

opt.read_options(options, mp.get_script_name(), function() end)

if options.message_alignment ~= -1 then options.message_anlignment = options.message_alignment end
if options.search_history_size >= 0 then options.search_history_limit = options.search_history_size end
if options.save_danmaku_path_mode ~= 'local' and options.save_danmaku_path_mode ~= 'url'
    and options.save_danmaku_path_mode ~= 'all' then options.save_danmaku_path_mode = 'local' end

-- Invalid configuration must not produce division by zero or invalid ASS tags.
local limits = {
    fontsize = {1, 300}, scrolltime = {0.1, 600}, fixtime = {0.1, 600},
    opacity = {0, 1}, displayarea = {0.01, 1}, outline = {0, 20}, shadow = {0, 20},
    request_timeout = {1, 300}, max_screen_danmaku = {0, 10000},
    merge_fontsize_growth = {1, 100}, merge_fontsize_max = {1, 300},
    search_history_limit = {0, 1000000}, message_anlignment = {1, 9},
}
for key, range in pairs(limits) do
    local value = tonumber(options[key])
    if not value or value ~= value then value = range[1] end
    options[key] = math.max(range[1], math.min(range[2], value))
end
