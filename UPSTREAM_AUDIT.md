# 分叉后逐提交核查（2026-11-02）

共同基线：`4d9e54e1ade827d3f0963d9609dbd7658466491a`。本分支基线：`503174b3`；上游审查端点：`d896f17`（本次 fetch 后未前移）。

上游独有 **133** 个提交（82 个单父提交、51 个合并记录），本分支独有 **43** 个提交。下表列出全部 133 项，没有以“已移植几个大模块”代替逐项范围核对。采用最终功能移植，不把已撤销的中间状态或合并节点再次执行；Git 提交图不会因此显示上游 133 项全部合并。

“已实现/等价/适配”指代码能力已接入，证据包括文件入口及回归；不表示每个外部网站在任意网络均已实测。文档/版本、TMDB、更新源和哈希撤销有明确的保留或替代理由。上游站点模块逐文件比较，差异限于桥接、超时、代理和异常保护。

本轮补齐先前遗漏的自动失败搜索、服务器备注和 @备注、保存路径范围、搜索历史单条删除、数量消息、当前集定位和 mp.input 生命周期；默认后备服务及其 ac=dm 协议也已同步。原分支保留能力见末节。

## 上游全部提交

| 提交 | 原提交说明 | 处理 | 实现或核查证据 |
| --- | --- | --- | --- |
| `b605526` | Update README.md | 适配 | README.md、RELEASE_NOTES.md、main.lua；保留分支文档结构和版本序列，补充当前配置，未逐字覆盖上游文档。 |
| `ecd8d6a` | fix: the script update did not work correctly (#305) | 适配 | modules/update.lua；保留 Loukyuu1120 更新源，异步下载、校验、备份/回滚；tests/run.py 的真实 Windows 更新场景。 |
| `8783433` | fix: danmaku visibility is not saved correctly Fixes #307 | 已实现 | main.lua:get/set_danmaku_visibility；modules/render.lua:hide_danmaku_func(false) 不覆盖持久状态。 |
| `014aa10` | Merge pull request #310 from dyphire/fix | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `e2224c4` | 将tmdb改为国内大部分地区可以直连的域名 | 已有等价 | apis/extra.lua 保留 api.tmdb.org 和本分支异步查询。 |
| `6553a5c` | Merge pull request #311 from wan0ge/tmdb | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `44ead78` | feat: add danmaku source footnote in danmaku content menu | 适配 | modules/menu.lua:open_content_menu 按 event.source 标注源。 |
| `8386a99` | Merge pull request #313 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `f0fef85` | Update issue templates | 已实现 | .github/ISSUE_TEMPLATE/bug-反馈.md 使用最终模板。 |
| `e117856` | Update issue templates | 已实现 | .github/ISSUE_TEMPLATE/bug-反馈.md 使用最终模板。 |
| `4a621e6` | fix: ch_convert invalid for part of danmakus | 已实现 | modules/parse.lua 在解析源内容时转换并按模式失效缓存；tests/regression.lua 简繁和原始数据不变。 |
| `832576f` | Merge pull request #316 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `24bffb7` | fix: ch_convert invalid in danmaku content menu | 已实现 | modules/parse.lua 在解析源内容时转换并按模式失效缓存；tests/regression.lua 简繁和原始数据不变。 |
| `9bdc5f7` | Merge pull request #318 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `198ff7c` | fix: async command not killed when playback terminates | 增强实现 | modules/requests.lua 默认 playback_only=true，start/end-file 取消请求及定时器，代次拦截旧回调。 |
| `ffbd969` | Merge pull request #321 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `9c50bb1` | feat: add back to search result in episode menu | 适配 | modules/menu.lua:get_episodes 返回 original_query（含 @备注），同时保留分支单服务器搜索返回路径。 |
| `8446ee7` | Merge pull request #323 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `7977e2e` | refactor: Improved open_input_menu_get() menu to manage barrage urls | 等价实现 | modules/menu.lua:open_add_menu_get/open_danmaku_source_menu；原有增删、屏蔽与延迟管理入口保留。 |
| `3bbad2d` | Merge pull request #324 from MiKoto-Railgun/main | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `e5fb272` | feat: add back to search result in episode menu in mp.input | 适配 | modules/menu.lua:get_episodes 返回 original_query（含 @备注），同时保留分支单服务器搜索返回路径。 |
| `80bb226` | Merge pull request #325 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `83f8868` | feat: add Style menu is used as a fallback mp.input. | 已实现 | modules/menu.lua:open_style_menu_get；支持样式选择和数值/布尔编辑。 |
| `d9b3ad2` | updata: README.md | 适配 | README.md、RELEASE_NOTES.md、main.lua；保留分支文档结构和版本序列，补充当前配置，未逐字覆盖上游文档。 |
| `c13e0b8` | fix: wrong logic processing danmaku with negative timestamp #329 | 已实现 | modules/parse.lua 轨道空槽检查；tests/regression.lua 负时间戳占轨。 |
| `16fe797` | Merge pull request #331 from Tony15246/fix | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `7527749` | Merge pull request #330 from MiKoto-Railgun/main | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `ce087af` | feat: add delay menu is used as a fallback mp.input. | 等价实现 | modules/menu.lua:open_delay_menu_get；选源后支持秒数及 XmYs，保留分段延迟。 |
| `191acb6` | feat: add delay menu is used as a fallback mp.input. | 等价实现 | modules/menu.lua:open_delay_menu_get；选源后支持秒数及 XmYs，保留分段延迟。 |
| `73fde08` | Merge pull request #332 from MiKoto-Railgun/main | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `48d6fc5` | refactor: extract duplicate menu item configuration | 已实现 | modules/menu.lua:create_menu_props、menu_items_config 复用配置。 |
| `34a7087` | Merge pull request #333 from MiKoto-Railgun/main | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `f41528b` | fix: Repair unescaped character in bahamut danmaku #335 | 已实现 | sites/bahamut.lua 与 modules/parse.lua 实体解码及 ASS 转义。 |
| `7814d13` | Merge pull request #336 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `7b4bac4` | optimization: danmaku rendering with binary search #341 | 已实现 | modules/render.lua 二分时间窗口、time-pos observer、overlay_low/high；回归覆盖 seek、隐藏、暂停与分层。 |
| `193a976` | Merge pull request #342 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `905b487` | refactor: replace periodic timer with time-pos observer | 已实现 | modules/render.lua 二分时间窗口、time-pos observer、overlay_low/high；回归覆盖 seek、隐藏、暂停与分层。 |
| `cc2b2a4` | Merge pull request #346 from dyphire/render | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `8f2ef09` | feat: add danmaku content delay menu | 适配 | modules/menu.lua、main.lua:get_delay_for_time、modules/parse.lua；沿用 sources 分段延迟，仅应用一次且含边界。 |
| `13a18cf` | Merge pull request #347 from dyphire/delay | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `64e1c7d` | feat: refactor danmaku fetching with response normalization and add cookie support | 适配 | apis/dandanplay.lua:normalize_danmaku_response/get_base_curl_args；支持 comments/danmuku/xml、Cookie 与代理。 |
| `4a1085b` | Merge pull request #348 from dyphire/api | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `8d41eb6` | feat: support xml form blacklist(dandanplay) and support json form blacklist(bilibili) #334 | 已实现 | modules/blacklist.lua、modules/parse.lua；保留旧 TXT Lua 规则并支持 XML/JSON 开关。 |
| `a46817d` | Merge pull request #344 from Tony15246/blacklist | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `35efa6c` | feat: optimize the experience of custom API server | 适配 | apis/dandanplay.lua:get_api_server_list/get_api_servers；兼容单/多项 api_server、api_servers 优先、有序并发与来源备注。 |
| `4c84d5b` | Merge pull request #350 from dyphire/api_server | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `9ceefc0` | Update README.md | 适配 | README.md、RELEASE_NOTES.md、main.lua；保留分支文档结构和版本序列，补充当前配置，未逐字覆盖上游文档。 |
| `e3aeb8a` | Update version number | 适配 | README.md、RELEASE_NOTES.md、main.lua；保留分支文档结构和版本序列，补充当前配置，未逐字覆盖上游文档。 |
| `1017092` | feat: support multiple API servers with fallback and concurrency | 适配 | apis/dandanplay.lua:get_api_server_list/get_api_servers；兼容单/多项 api_server、api_servers 优先、有序并发与来源备注。 |
| `e82a1b3` | feat: add per-source delay lookup for danmaku processing | 适配 | modules/menu.lua、main.lua:get_delay_for_time、modules/parse.lua；沿用 sources 分段延迟，仅应用一次且含边界。 |
| `cdb05cc` | feat: support multiple overlay layers for danmaku rendering | 已实现 | modules/render.lua 二分时间窗口、time-pos observer、overlay_low/high；回归覆盖 seek、隐藏、暂停与分层。 |
| `d3e1e09` | Merge pull request #352 from dyphire/api_server | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `5c2e769` | misc: enhance progress messaging for multi-server requests in menu | 增强实现 | modules/menu.lua:get_animes/open_danmaku_source_menu 增量返回，pending/error 显示；共享查询避免重复请求。 |
| `1d2eba8` | Merge pull request #355 from dyphire/menu | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `a8cba3a` | feat: add option merge_without_style #340 | 已实现 | modules/parse.lua 与 options.merge_without_style。 |
| `6ba7503` | Merge pull request #356 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `2bf912b` | fix: showing spinner icon when not loading | 等价实现 | main.lua:set_danmaku_button、modules/requests.lua:update_running；不在无请求时保持加载状态。 |
| `8784030` | Merge pull request #357 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `de34608` | Update README | 适配 | README.md、RELEASE_NOTES.md、main.lua；保留分支文档结构和版本序列，补充当前配置，未逐字覆盖上游文档。 |
| `38399a7` | Merge pull request #360 from dyphire/misc | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `f779dc8` | feat: add property user-data/uosc_danmaku/danmaku-switch-on #362 | 已实现 | main.lua 与 modules/render.lua 维护 user-data/uosc_danmaku/danmaku-switch-on。 |
| `e3597e0` | Merge pull request #363 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `2929ee6` | docs: Add table of contents to README | 适配 | README.md、RELEASE_NOTES.md、main.lua；保留分支文档结构和版本序列，补充当前配置，未逐字覆盖上游文档。 |
| `180e555` | Merge pull request #364 from MiKoto-Railgun/main | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `7372741` | feat: support xml fallback danmaku file | 已有等价 | main.lua:init/file-loaded、add_danmaku_source_local；同名 XML 载入优先于网络匹配。 |
| `3d514af` | feat: add custom property for danmaku count #375 | 已实现 | main.lua:DANMAKU_COUNT、modules/render.lua 渲染/卸载更新；回归检查卸载归零。 |
| `4e5fe99` | Merge pull request #379 from Tony15246/property | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `9048f90` | Merge pull request #378 from Tony15246/xml | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `e3605a9` | fix: can not load bilibili partition video danmaku #370 | 已实现 | sites/bilibili.lua 分P列表/选集；tests/regression.lua 分P及站点入口回调。 |
| `2c3e956` | refactor: add sites module | 适配 | modules/sites.lua 桥接 sites/，按真实主机名分派，保持本分支 API 参数与数据格式。 |
| `cbf930f` | Merge pull request #377 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `3b2834f` | feat: add internal danmaku comment parses for iqiyi, mgtv, tencent and youku | 已实现 | sites/iqiyi.lua、mgtv.lua、tencentvideo.lua、youku.lua 及 modules/inflate.lua；完成模块接线，不代表各站点在线全覆盖。 |
| `c96130d` | fix: failed to obtain the `/v1/detail` interface of 360kan | 适配 | apis/extra.lua episodesv2、v1 后备和播放链接缓存；分支实现采用异步分页。 |
| `eab759d` | Merge pull request #383 from dyphire/extra | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `af47799` | Merge pull request #380 from dyphire/sites | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `39738ed` | fix: mp.input menu close event conflict #381 | 适配 | modules/menu.lua 的 input_open 队列按 opened/closed 分发；延迟旧 closed 不会清掉新菜单，回归实际模拟事件顺序。 |
| `ee8bbb9` | Merge pull request #384 from Tony15246/input | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `625d788` | chore: normalize line endings | 适配 | .gitattributes LF 与 .gitignore；未重排 aes/hash 等无功能差异文件。 |
| `dba7b73` | fix: callback failed with nil | 已实现 | modules/requests.lua、modules/sites.lua 与各站点对 nil/重复回调保护。 |
| `e88bb87` | Merge pull request #388 from dyphire/sites | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `4ff9e8a` | fix: wrong DELAY display #374 | 适配 | modules/menu.lua、main.lua:get_delay_for_time、modules/parse.lua；沿用 sources 分段延迟，仅应用一次且含边界。 |
| `6dbb132` | Merge pull request #389 from Tony15246/fix | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `8199807` | feat: support custom danmaku save path #390 | 已实现 | main.lua:get_danmaku_save_directory 支持 save_danmaku_path 与 local/url/all，兼容 danmaku_save_path；回归覆盖范围。 |
| `8fb2107` | Merge pull request #392 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `1115541` | fix: hash calculation skipped when when the file size is exactly 16 MB | 已有等价 | apis/dandanplay.lua >=16MiB；回归小于/等于/大于边界及已知摘要。 |
| `33c3b9a` | Merge pull request #396 from HosamaJJF/fix/hash_calculation_skipped | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `948f64e` | fix: use default danmaku API proxy | 已实现 | modules/options.lua 默认 danmaku-api.152468.xyz；catalog/signature 区分，load_more 不走代理不存在的 related。真实 mpv 搜索-选集-渲染验证。 |
| `bb45b5b` | fix: enhance return to search menu | 适配 | modules/menu.lua:get_episodes 返回 original_query（含 @备注），同时保留分支单服务器搜索返回路径。 |
| `beb5293` | fix: enhance return to search menu | 适配 | modules/menu.lua:get_episodes 返回 original_query（含 @备注），同时保留分支单服务器搜索返回路径。 |
| `b0f1b95` | fix: Add the previously existing danmaku-count attribute description to README.md | 适配 | README.md、RELEASE_NOTES.md、main.lua；保留分支文档结构和版本序列，补充当前配置，未逐字覆盖上游文档。 |
| `a702182` | feat: registration displays a danmakucount message | 已实现 | main.lua 注册 show_danmaku_count，show_loaded 处理空数据。 |
| `f48642a` | feat: add `auto_fallback_search` option | 适配 | options.auto_fallback_search；main.lua:auto_load_fallback 使用请求代次去重，匹配链最终失败/空弹幕触发，默认关闭；不引入大小写不一致的全局标记。 |
| `bcf2da2` | feat: add `auto_fallback_search` option | 适配 | options.auto_fallback_search；main.lua:auto_load_fallback 使用请求代次去重，匹配链最终失败/空弹幕触发，默认关闭；不引入大小写不一致的全局标记。 |
| `2fb7399` | feat: add `auto_fallback_search` option | 适配 | options.auto_fallback_search；main.lua:auto_load_fallback 使用请求代次去重，匹配链最终失败/空弹幕触发，默认关闭；不引入大小写不一致的全局标记。 |
| `1b9419e` | feat: add `auto_fallback_search` option | 适配 | options.auto_fallback_search；main.lua:auto_load_fallback 使用请求代次去重，匹配链最终失败/空弹幕触发，默认关闭；不引入大小写不一致的全局标记。 |
| `ecac7cf` | feat: add `auto_fallback_search` option | 适配 | options.auto_fallback_search；main.lua:auto_load_fallback 使用请求代次去重，匹配链最终失败/空弹幕触发，默认关闭；不引入大小写不一致的全局标记。 |
| `deae7d8` | feat: add `auto_fallback_search` option | 适配 | options.auto_fallback_search；main.lua:auto_load_fallback 使用请求代次去重，匹配链最终失败/空弹幕触发，默认关闭；不引入大小写不一致的全局标记。 |
| `67cdbb7` | feat: add `auto_fallback_search` option | 适配 | options.auto_fallback_search；main.lua:auto_load_fallback 使用请求代次去重，匹配链最终失败/空弹幕触发，默认关闭；不引入大小写不一致的全局标记。 |
| `f21e407` | feat：Search term uses `@note` to specify the server. | 已实现 | modules/menu.lua:get_animes 解析末尾 @备注，get_api_servers 按备注首个匹配筛选；请求参数回归确保备注不进入关键词或 URL。 |
| `92c7f3a` | feat: Add count text to unblock and block actions | 已实现 | modules/menu.lua 来源动作、hint 与屏蔽/解除反馈显示 #source.data。 |
| `9127b70` | feat: add `auto_fallback_search` option | 适配 | options.auto_fallback_search；main.lua:auto_load_fallback 使用请求代次去重，匹配链最终失败/空弹幕触发，默认关闭；不引入大小写不一致的全局标记。 |
| `d69c3e8` | Merge pull request #409 from MiKoto-Railgun/patch-6 | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `127db9d` | Merge pull request #408 from MiKoto-Railgun/patch-5 | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `7e4fc59` | Merge pull request #406 from MiKoto-Railgun/patch-2 | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `b4ef542` | Merge pull request #405 from MiKoto-Railgun/patch-1 | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `1ee2bfa` | Merge pull request #407 from MiKoto-Railgun/patch-3 | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `1e0baeb` | feat: optimize curl request configuration and extend request timeout | 适配 | get_base_curl_args 连接超时10秒、总超时 request_timeout（默认30秒）、压缩和错误状态；站点请求继承总超时，回归 HTTP/传输错误。 |
| `d8c1cd8` | Merge pull request #410 from dyphire/ssl | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `b45a8a4` | fix: Replace fallback_server | 已实现 | 默认 dmku.hls.one，get_danmaku_fallback 使用 ac=dm 与 URL 编码；回归验证请求和 XML 归一化。 |
| `47cf93a` | feat: dynamic merged danmaku fontsize increase #404 | 已实现 | modules/parse.lua 合并数量对数增大字号，options.merge_fontsize_growth/max；回归合并。 |
| `a107970` | Merge pull request #411 from MiKoto-Railgun/main | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `7e8ffe5` | Merge pull request #412 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `55f3aea` | Merge pull request #417 from Elongou44/fix-mp-input-menu | 适配 | modules/menu.lua 的 input_open 队列按 opened/closed 分发；延迟旧 closed 不会清掉新菜单，回归实际模拟事件顺序。 |
| `b632e06` | feat: add danmaku search history feature | 适配 | modules/menu.lua 独立 JSON、去重置顶、两套 UI 单条删除、空搜索不写入、0 不限；search_history_size 配置别名。 |
| `6f6d7a1` | feat: Refactor the file hash calculation process. | 不应重引入 | 上游已撤销 6f6d7a1；保留当前文件/URL 哈希匹配链及16MiB边界，不单独应用已撤销中间状态。 |
| `58b6d4a` | Merge pull request #421 from MiKoto-Railgun/patch-2 | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `763dcd3` | Revert "feat: Refactor the file hash calculation process." | 不应重引入 | 上游已撤销 6f6d7a1；保留当前文件/URL 哈希匹配链及16MiB边界，不单独应用已撤销中间状态。 |
| `d7bec80` | feat: 搜索历史支持删除单条记录，并修正回车搜索行为 | 适配 | modules/menu.lua 独立 JSON、去重置顶、两套 UI 单条删除、空搜索不写入、0 不限；search_history_size 配置别名。 |
| `b6ba473` | fix: restore danmaku history loading for streams #403 | 适配 | main.lua:read_danmaku_source_record/auto_load_danmaku/load_danmaku_for_url；保留 sources、server、episode_offset 与分段继承，修复未定义 path 和 ID/集数混用。 |
| `03b8705` | Merge pull request #427 from Tony15246/dev | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `3ca4709` | Merge pull request #418 from Elongou44/feat-search-history | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `029f976` | feat: title_replace supports importing rules using JSON files. | 已实现 | modules/utils.lua:title_replace 支持展开 JSON 路径，非法规则不抛错；回归文件与字符串规则。 |
| `77f70bc` | Updata options.lua | 适配 | README.md、RELEASE_NOTES.md、main.lua；保留分支文档结构和版本序列，补充当前配置，未逐字覆盖上游文档。 |
| `56e920b` | Merge pull request #429 from MiKoto-Railgun/title_replace | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `e1a5b06` | feat: Add a blacklist menu. (#426) | 已实现 | modules/menu_extensions.lua 两套 UI 编辑、启停与删除；modules/blacklist.lua 保留文件格式。 |
| `e56c385` | fix: resolve case mismatch of FALLBACK_TRIGGER causing fallback search failure | 适配 | options.auto_fallback_search；main.lua:auto_load_fallback 使用请求代次去重，匹配链最终失败/空弹幕触发，默认关闭；不引入大小写不一致的全局标记。 |
| `38b20e7` | fix(mgtv): add the missing callback(false) to the early exit path. | 已实现 | sites/mgtv.lua 所有提早退出路径 callback(false)。 |
| `d82539a` | feat: Parse current video episode for auto-positioning on menu open. (#432) | 适配 | modules/menu.lua:get_episodes 按 parse_title 和手动偏移标记唯一当前集，传 selected_index/default_item，包含返回行偏移；两套 UI 回归。 |
| `286d279` | fix: Search completion menu item shifting upward. (#433) | 等价实现 | get_animes 保持底部完成行；final callback 去重，首个加载菜单同步打开避免快速响应被旧菜单覆盖。 |
| `b2efa6d` | fix: resolve case mismatch of FALLBACK_TRIGGER causing fallback search failure (#434) | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `e49fb29` | Merge pull request #435 from MiKoto-Railgun/fix/mgtv_callback | 合并记录 | 无额外功能单独移植；审查该合并包含的最终文件状态与本表对应功能项。 |
| `2ad35e4` | Merge pull request #436 from MiKoto-Railgun/fix/iqiyi_callback | 已实现 | sites/iqiyi.lua 使用 ipairs 遍历 entries，失败回调保护；保留最终上游站点逻辑。 |
| `d896f17` | fix(iqiyi): change loop to iterate entries using ipairs | 已实现 | sites/iqiyi.lua 使用 ipairs 遍历 entries，失败回调保护；保留最终上游站点逻辑。 |

## 原分支的 43 个独有提交

以下提交全部已在本次修改的父历史中，不需要重新 cherry-pick。功能核对按最终状态完成：保留多 API 顺序匹配/并发、御坂重试与进度、匹配缓存和主动刷新、手动选源、异步 TMDB、URL 哈希、匹配历史 sources/server、集数偏移及分段延迟继承。请求生命周期由 modules/requests.lua 统一增强，菜单、历史与来源接口继续使用原分支格式。未恢复更早 ea0157a 前已淘汰的历史格式。

| 提交 | 原提交说明 |
| --- | --- |
| `548a43f` | 添加多弹幕API支持，优化弹幕匹配逻辑 |
| `accd274` | 修复搜索菜单剧集信息获取 |
| `b57e4d4` | 修复内容为空。 |
| `4b493e9` | 重写以支持api_servers顺序匹配。 |
| `5f13dbf` | 优化搜索菜单对多api的处理，新增选择弹幕来源控件配置（参照最新版uosc的控件配置步骤）。 |
| `65b4745` | 新增配置项match_cache_path |
| `f2872db` | 添加选择弹幕来源，更新新增功能说明，解决一些已知的问题。 |
| `84022d6` | Add GitHub Actions workflow for auto zip release |
| `fe4faef` | v2.0.2 |
| `505c13d` | 稍微提高更新脚本的安全性。 |
| `e43b09e` | 改为立即显示可用结果 |
| `66073e1` | 修复进入a剧集页后还会被b返回结果影响 |
| `206af93` | 修复当只有一个API返回一条结果时没有使用缓存的问题 |
| `1b6ce7f` | 定时清理手动搜索缓存 (60秒) |
| `c145bd8` | 将“正在加载”改为更准确的“正在搜索”描述 |
| `eb821e3` | 提高版本号 |
| `52c62fd` | Merge pull request #1 from wan0ge/Beta |
| `a70674b` | 减少可能的状态竞争，搜索添加延迟确保菜单打开稳定。 |
| `651ad48` | 并发管理器支持提前返回，以提升自动选择弹幕的速度。 |
| `eec0003` | 添加新参数hash_fot_url，优化自动获取弹幕的速度。添加弹幕请求失败日志，修复url视频只下载不计算hash。 |
| `55ac825` | Fix error message for fetching danmaku data |
| `c91c75e` | 修复御坂弹幕首次匹配无法正常在选择弹幕源里获取剧集 |
| `8de56d4` | 为御坂弹幕实现后备搜索时实时更新进度 |
| `554eb18` | 优化强制刷新逻辑，使其适配新的重试功能 |
| `3931a63` | 定时清理缓存改为直接对比items表适配新的强制刷新逻辑 |
| `86dea3e` | 修复LogVar为首时无法通过url获取外部弹幕 |
| `6288d8d` | Merge pull request #2 from wan0ge/misaka |
| `f79a5fc` | 同步原仓库更新显示弹幕行为。去掉加载弹幕后自动哈希减少阻塞以解决加载弹幕出现的卡顿。 |
| `8df2102` | 更新版本号 |
| `412f228` | 支持御坂弹幕为空时重试获取弹幕（需要token开启匹配后备授权），修正hash计算适配excluded_path。 |
| `14f7389` | 优化并发请求验证器，改进剧集匹配逻辑 |
| `c492ed4` | 对御坂API单服务器搜索也支持实时刷新进度 |
| `f8f911c` | 新增自动匹配弹幕服务器功能，默认禁用；优化错误信息 |
| `0cd7ba7` | Fixes #3: 优化自动加载匹配弹幕源数据，修改TMDB请求为异步实现。 |
| `2ad4310` | 自动匹配弹幕源功能改成默认启用；增加多服务器搜索返回结果的排序逻辑，提升用户体验 |
| `7d19a24` | 使用直连效果更好的tmdb api |
| `ea0157a` | 弹幕菜单：新增“屏蔽”“延迟”按钮；更改数据表 key，旧版 danmaku-history.json 不再兼容。 |
| `7acaf71` | 统一异步请求处理，简化错误信息输出。 |
| `9bde8f3` | Fix BGR to ASS color tag conversion |
| `c66f24c` | 修复读取历史。 |
| `ca528d8` | 修复本地视频历史不生效。 |
| `c385c71` | 支持延迟继承；支持在选择弹幕源菜单里添加弹幕源；修了一些已知存在的bug |
| `503174b` | 优化弹幕加载逻辑，添加防抖动机制；重构匹配历史 |

## 验证与边界

- `python tests/run.py`：Lua 5.1、Lua 5.2、LuaJIT 全量语法/加载/行为回归；包括新增路由、两套历史删除、当前集定位、延迟关闭事件、保存范围、自动失败搜索去重。Windows 实际执行平铺/嵌套包更新、缺文件拒绝、替换失败恢复。
- 真实 mpv，隔离配置和生成视频，使用用户 API 与 load_more 设置：12 集、第一集 2571 条，选集至渲染约 0.64 秒。来源菜单首个结果约 0.43 秒，其他来源仍在查询；三次打开共一轮7请求。
- Linux 与 Windows 发布矩阵全部通过后，工作流才允许创建 Release。
- 六站点真实 URL/Cookie 全覆盖、全部旧历史组合、Unix 更新回滚未作端到端证明；这些验证限制不会标为“全部线上功能已验证”。
