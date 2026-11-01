local function equal(actual, expected, label)
    assert(actual == expected, (label or '') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function source(data, delay)
    return parse_danmaku_sources({{type = 'memory', data = data, url = 'test'}},
        {{{start = 0, delay = delay or 0}}})
end

-- A delayed close from an old mp.input prompt must preserve the new prompt.
local old_closed, new_submit = 0, 0
input.get({closed=function() old_closed=old_closed+1 end})
messages['input-event']('opened','[]')
input.get({submit=function(value) if value=='kept' then new_submit=new_submit+1 end end})
messages['input-event']('closed','[]')
equal(old_closed, 0, 'old closed callback suppressed while replacement pending')
messages['input-event']('opened','[]')
messages['input-event']('submit','["kept"]')
equal(new_submit, 1, 'new prompt receives submit')
messages['input-event']('closed','[]')

-- Delay is applied once, at inclusive segment boundaries, without modifying sources.
local xml = '<i><d p="0,1,25,16711680">繁體 &amp; &#x4E2D;</d></i>'
local parsed = source(xml, 2)
equal(parsed[1].time, 2, 'XML delay applied once')
equal(parsed[1].text, '繁體 & 中', 'entities decoded')
equal(source('[{"c":"0,16777215,1,25","m":"test"}]', 3)[1].time, 3, 'JSON delay applied once')
local raw = {{time = 1, type = 1, color = 1, text = '體'}}
options.chConvert = 1
equal(source(raw)[1].text, '体', 'simplified conversion')
options.chConvert = 2
equal(source(raw)[1].text, '體', 'conversion cache invalidated')
equal(raw[1].text, '體', 'source text preserved')
equal(raw[1].time, 1, 'source timestamp preserved')
options.chConvert = 0
local delayed = parse_danmaku_sources({{type='memory',data=raw}}, {{{start=1,delay=2},{start=0,delay=3}}})
equal(delayed[1].time, 6, 'inclusive segmented delay')
equal(#parse_xml_danmaku("<i><d p='1,1,25,1'>a</d></i>"), 1, 'single quoted XML')
equal(#source({false, {time=0,text=false}, {time='bad',text='x'}}), 0, 'malformed entries')

-- Negative times reserve tracks; decoded text cannot inject ASS position tags.
ENABLED = true; set_danmaku_visibility(true)
render_danmaku(source({
    {time=-2,type=1,text='first',color=16711680},
    {time=-2,type=1,text='second',color=16777215},
    {time=0,type=4,text='bottom',color=16777215},
    {time=0,type=5,text='top',color=16777215},
}))
assert(COMMENTS[1].move[2] ~= COMMENTS[2].move[2], 'negative-time track collision')
assert(COMMENTS[1].text:find('H0000FF',1,true), 'RGB to BGR')
render(0)
assert(overlays[1].data ~= '' and overlays[2].data ~= '', 'two render layers')
hide_danmaku_func()
local updates = overlays[1].updates
render(1)
equal(overlays[1].updates, updates, 'hidden rendering stays stopped')
equal(get_danmaku_visibility(), false, 'visibility persisted')

-- Concurrent completions must keep the loading flag true until all finish.
local received = 0
call_cmd_async({'curl','one'},function() received=received+1 end)
local first = #pending
call_cmd_async({'curl','two'},function() received=received+1 end)
respond(first,'{}'); equal(async_running,true,'multiple active requests')
respond(first+1,'{}'); equal(async_running,false,'all requests finished')
call_cmd_async({'curl','old'},function() error('stale callback ran') end)
local stale=#pending
add_playback_timeout(1,function() error('stale timer ran') end)
fire('start-file')
respond(stale,'{}'); flush_timers()
equal(async_running,false,'cancelled state')
equal(pending[stale].aborted,true,'old request aborted')

-- Invalid HTTP and JSON responses complete their callback once.
local finished=0
fetch_danmaku_data({'curl'},function(data) equal(data,nil); finished=finished+1 end)
respond(#pending,'broken')
equal(finished,1,'invalid JSON callback')
fetch_danmaku_data({'curl'},function(data) equal(data,nil); finished=finished+1 end)
respond(#pending,'',22)
equal(finished,2,'HTTP failure callback')
local compatible=normalize_danmaku_response({danmuku={{1,'top','#FF0000',0,'top text'}, {2,'bottom','#FFFFFF',0,'bottom text'}}})
equal(compatible.comments[1].p,'1.000,5,16711680','normalized top mode')
equal(compatible.comments[2].p,'2.000,4,16777215','normalized bottom mode')
fetch_danmaku_data({'curl'},function(data) equal(data.count,1,'XML API fallback') end)
respond(#pending,'<i><d p="1,1,25,1">xml fallback</d></i>')
local signed=table.concat(make_danmaku_request_args('GET','https://api.dandanplay.net/api/v2/search/anime?keyword=test'),' ')
assert(signed:find('X-Signature:',1,true),'official API signing')

-- Normalization keeps legitimate quotes/backslashes, skipping malformed records.
local normalized=save_danmaku_json({{p='1,1,16711680',m='"a"\\b'}, {p='bad',m='x'}, {p='0,1,1'}})
equal(#normalized,1); equal(normalized[1].text,'"a"\\b')
options.api_servers=' https://example.test/ ,https://example.test, ,https://second.test///'
equal(#get_api_servers(),2); equal(get_api_servers()[1],'https://example.test')
options.api_servers=' , '; equal(get_api_servers()[1],options.api_server)

-- Site dispatch is host based and failures remain callable.
equal(load_site_danmaku('https://unrelated.test/?next=iqiyi.com',function() end),false)
local failed=false
load_site_danmaku('https://www.mgtv.com/invalid',function(ok) failed=not ok end)
equal(failed,true,'site early failure callback')
load_site_danmaku('https://www.bilibili.com/video/BV123?p=2',function() end)
local request=#pending
respond(request,'{"data":[{"cid":11},{"cid":22}]}')
assert(table.concat(pending[#pending].command.args,' '):find('22.xml',1,true),'bilibili selected partition')
respond(#pending,'<i><d p="1,1,25,1">site</d></i>')

-- Old history format and the mp.input fallback remain functional.
messages['open_blacklist_menu']()
open_input_menu()
assert(last_input and last_input.submit,'mp.input search')
options.blacklist_path=test_root .. '/black.txt'
assert(write_file(options.blacklist_path,'blocked\n[\n'))
get_blacklist_patterns(true)
equal(#source({{time=0,type=1,color=1,text='blocked'}}),0,'legacy blacklist')
assert(blacklist_add_entry('new rule'))
options.blacklist_path=test_root .. '/black.json'
assert(write_file(options.blacklist_path,'[{"type":0,"filter":"jsonblock","opened":true}]'))
get_blacklist_patterns(true)
equal(#source({{time=0,type=1,color=1,text='jsonblock'}}),0,'JSON blacklist')

options.title_replace='{"rules":[{"^Show":"Series"}]}'
equal(title_replace('Show 01'),'Series 01','title rules')
local title_rules_path = test_root .. '/title-rules.json'
assert(write_json_file(title_rules_path, {rules={{['^Show']='FromFile'}}}))
options.title_replace = title_rules_path
equal(title_replace('Show 01'), 'FromFile 01', 'title rules read from JSON file')
options.title_replace='[{"rules":[{"[":"broken"}]}]'
equal(title_replace('Show 01'),'Show 01','invalid pattern ignored')
options.blacklist_path=''
get_blacklist_patterns(true)

-- Merge style and fontsize controls affect the final ASS events.
local duplicates = {{time=1,type=1,color=1,text='repeat'}, {time=1,type=5,color=2,text='repeat'}}
options.merge_tolerance = 1; options.merge_without_style = false
convert_danmaku_to_ass_events(duplicates)
equal(#COMMENTS, 2, 'style-sensitive merge keeps separate modes')
options.merge_without_style = true
convert_danmaku_to_ass_events(duplicates)
equal(#COMMENTS, 1, 'cross-style duplicate merge')
assert(COMMENTS[1].text:find('repeat',1,true), 'merged text survives rendering')
options.merge_tolerance = -1; options.merge_without_style = false

-- Layout limits, seeking in both directions, and persisted source delays.
options.max_screen_danmaku=1
convert_danmaku_to_ass_events(source({{time=0,type=1,text='a'},{time=0,type=1,text='b'}}))
equal(#COMMENTS,1,'screen limit')
options.max_screen_danmaku=0
local ass='[Events]\nDialogue: 0,0:00:01.50,0:00:05.00,TOP,,0,0,0,,{\\c&H0000FF&}hello,world'
local ass_result=source(ass)
equal(ass_result[1].time,1.5); equal(ass_result[1].text,'hello,world'); equal(ass_result[1].color,16711680)
equal(ass_result[1].type,5)
set_danmaku_visibility(true)
render_danmaku(source({{time=1,type=1,text='one'}, {time=100,type=1,text='later'}}))
render(101); assert(overlays[1].data:find('later',1,true))
render(2); assert(overlays[1].data:find('one',1,true)); assert(not overlays[1].data:find('later',1,true))
render(80); equal(overlays[1].data,'','seek clears old text')

-- Related-source failures and retries complete without busy-waiting.
local calls=0
handle_related_danmaku(1,{{url='https://example.test'}},{url='https://example.test'},0,function() calls=calls+1 end)
respond(#pending,'',22)
flush_timers()
respond(#pending,'',22)
equal(calls,1,'related failure completes once')

-- Concurrent priority respects configured ordering, including empty responses.
local manager=ConcurrentManager:new()
local responders={}
for i=1,3 do manager:start_request('s'..i,i,function(cb) responders[i]=cb end) end
local chosen
manager:wait_priority(3,function(r) return r.data ~= nil end,function(results) chosen=results[1].index end)
responders[2]({data='second'}); equal(chosen,nil,'wait for higher priority')
responders[1](nil); equal(chosen,2,'select first successful server')
responders[2]({data='duplicate'}); responders[3]({data='third'}); equal(manager.active_requests,0,'duplicate completion ignored')

-- Hashing retains the 16 MiB boundary and respects excluded directories.
local original_md5=MD5
local read_bytes=0
MD5={new=function() return {
    update=function(_,bytes) read_bytes=read_bytes+#bytes end,
    finish=function() return 'hash' end,
} end}
options.excluded_path='[]'; options.api_servers='https://example.test'
for _,size in ipairs({16777215,16777216,16777217}) do
    read_bytes=0
    match_file_concurrent(test_root..'/'..size..'.mkv','Show 01',function() end)
    equal(read_bytes,size>=16777216 and 16777216 or 0,'16 MiB hash boundary')
end
read_bytes=0; options.excluded_path=py_format_json({test_root})
match_file_concurrent(test_root..'/16777216.mkv','Show 01',function() end)
equal(read_bytes,0,'excluded path skips hash')
MD5=original_md5; options.excluded_path='[]'
if type(MD5)=='table' and MD5.sum then equal(MD5.sum('abc'),'900150983cd24fb0d6963f7d28e17f72','MD5 compatibility') end

-- mp.input style/delay menus and uosc history serialization.
add_danmaku_setup(); assert(last_select and #last_select.items>0,'fallback style menu')
DANMAKU.sources={sample={from='user_custom',data={{time=0,type=1,text='x'}}}}
danmaku_delay_setup(); equal(last_select.items[1],'sample','fallback delay menu')
uosc_available=true
local menu=update_menu_uosc('test','title',{{title='x',value={'test'}}})
assert(type(menu)=='string','serialized menu retained for back navigation')
uosc_available=false

-- Additional search uses async requests even when pagination looks sequential.
query_extra('测试','ds')
assert(pending[#pending].command.name=='subprocess','extra search async')
respond(#pending,'{"data":{"longData":{"rows":[]}}}')
get_details('电视剧','123','qq','测试','2026',2)
respond(#pending,'{"code":0,"data":[{"seriesHTML":{"seriesPlaylinks":[{"url":"https://v.qq.com/1"},{"url":"https://v.qq.com/2"}]}}]}')
flush_timers()
assert(last_select and #last_select.items>=2,'episode list returned asynchronously')

-- History derives the playing episode from the filename, not the API identifier.
invalidate_playback_requests()
DANMAKU={sources={},anime='Show',episode='第42话',source='dandanplay'}
write_history(10042,'https://example.test')
local history=parse_json_table(read_file(HISTORY_PATH))
local key=get_cache_key()
equal(history[key].episodeNumber,1,'playing episode versus remote ID')
add_source_to_history('https://example.test/source',{from='user_custom',delay_segments={{start=0,delay=2},{start=10,delay=3}}})
history=parse_json_table(read_file(HISTORY_PATH))
equal(#history[key].sources['https://example.test/source'].delay_segments,2,'nearby delay boundaries preserved')
history[key].sources={['https://example.test/legacy']={from='user_custom',delay=-2}}
assert(write_json_file(HISTORY_PATH,history))
COMMENTS={}; options.auto_load=false; options.autoload_danmaku_matches=false
fire('file-loaded')
equal(DANMAKU.sources['https://example.test/legacy'].delay_segments[1].delay,-2,'legacy scalar delay migrated')
DANMAKU.sources={sample={from='user_custom',data={{time=1,type=1,text='offset'}}}}
ENABLED=true; set_danmaku_visibility(true)
messages['danmaku-delay']('2')
flush_timers()
equal(COMMENTS[1].start_time,3,'global delay applied once through sources')
messages['danmaku-delay']('0')
flush_timers()
equal(COMMENTS[1].start_time,1,'global delay reset')
clear_danmaku_render()
equal(overlays[1].removed,true,'empty source clears paused overlay')
equal(parse_json_table('true'),nil,'scalar JSON rejected')

-- Upstream proxy uses catalog search without official signing, alongside failed custom APIs.
local proxy='https://danmaku-api.152468.xyz'
equal(is_dandanplay_catalog(proxy),true,'proxy catalog routing')
equal(is_official_dandanplay_server(proxy),false,'proxy handles its own authentication')
local proxy_args=table.concat(make_danmaku_request_args('GET',proxy..'/api/v2/search/anime?keyword=Show'),' ')
assert(not proxy_args:find('X-Signature:',1,true),'no official signature sent to proxy')
options.api_servers=proxy..',https://failed.test'
uosc_available=true
local start=#pending
open_danmaku_source_menu(true)
local scan_requests = #pending
open_danmaku_source_menu(true)
open_danmaku_source_menu(false)
equal(#pending, scan_requests, 'reopening source menu shares in-flight scan')
assert(table.concat(pending[start+1].command.args,' '):find('/api/v2/search/anime?',1,true),'proxy searched as catalog')
respond(start+1,'{"animes":[{"animeTitle":"Show","bangumiId":12,"type":"tvseries"}]}\n__UOSC_HTTP_STATUS__:200')
local first_update = parse_json_table(commands[#commands][4])
assert(first_update and first_update.footnote:find('其余仍在查询',1,true),'fast source published before slow source finishes')
assert(commands[#commands][4]:find('Show',1,true),'fast source is selectable immediately')
respond(start+2,'\n__UOSC_HTTP_STATUS__:403',22)
flush_timers()
local menu_text=''
for _, command in ipairs(commands) do
    if command[3]=='update-menu' then menu_text=command[4] or '' end
end
assert(menu_text:find('Show',1,true),'successful source result survives another source failure')
assert(menu_text:find('HTTP 403',1,true),'source menu shows HTTP failure instead of no matches')
local result_text
call_cmd_async({'curl','test'},function(err) result_text=err end)
respond(#pending,'',28)
equal(result_text,'请求超时','transport error translated')

-- load_more must not route proxy users through the unsupported /related API.
options.load_more_danmaku = true
local before = #pending
fetch_danmaku_all(123, true, proxy)
equal(#pending, before + 1, 'proxy combined-comment request')
local request_args = table.concat(pending[#pending].command.args, ' ')
assert(request_args:find('/comment/123?withRelated=true',1,true),'load_more uses combined comments on proxy')
assert(not request_args:find('/related/',1,true),'unsupported related endpoint avoided')

-- Official related failures do not suppress the main comment request.
before = #pending
fetch_danmaku_all(123, true, 'https://api.dandanplay.net')
equal(#pending, before + 2, 'main comments and related lookup launched independently')
assert(table.concat(pending[before+1].command.args,' '):find('/comment/123',1,true),'main request starts first')
respond(before+2,'\n__UOSC_HTTP_STATUS__:404',22)
respond(before+1,'{"comments":[{"p":"0,1,16777215","m":"main survives"}],"count":1}')
local main_url='https://api.dandanplay.net/api/v2/comment/123?withRelated=false&chConvert=0'
equal(DANMAKU.sources[main_url].data[1].text,'main survives','related failure preserves primary comments')

-- Audit regressions: annotated multi-API configuration and filtered real requests.
fire('end-file')
options.api_servers = ' https://one.test/|主源,https://two.test/#备用,https://one.test/|重复 '
equal(#get_api_servers(), 2, 'annotated URLs deduplicated')
equal(get_api_servers()[1], 'https://one.test', 'notes never enter URL')
equal(get_api_servers('备用')[1], 'https://two.test', 'note selects matching API')
local saved_servers = options.api_servers
options.api_servers = ''
local saved_single = options.api_server
options.api_server = 'https://one.test|主源,https://two.test#备用'
equal(#get_api_servers(), 2, 'upstream comma list accepted in api_server')
options.api_server = saved_single; options.api_servers = saved_servers
local count = #pending
get_animes('Show @备用')
equal(#pending, count + 1, 'only selected source queried')
local args = table.concat(pending[#pending].command.args, ' ')
assert(args:find('https://two.test/api/v2/search/anime?keyword=Show',1,true),'query excludes note')
respond(#pending, '{"animes":[{"animeTitle":"Show","bangumiId":12}]}')
flush_timers()
local final_menu
for _,command in ipairs(commands) do
    local menu = command[4] and parse_json_table(command[4])
    if menu and menu.type == 'menu_anime' then final_menu = menu end
end
assert(final_menu and final_menu.items[#final_menu.items].title:find('搜索完成',1,true), 'completion row remains at bottom')

-- The new fallback service requires ac=dm and an encoded source URL.
get_danmaku_fallback('https://video.test/watch?a=1&b=2')
local fallback_args = table.concat(pending[#pending].command.args, ' ')
assert(fallback_args:find('/?ac=dm&url=https%%3A%%2F%%2Fvideo.test%%2Fwatch%%3Fa%%3D1%%26b%%3D2'), 'fallback preserves full source URL')
respond(#pending, '{"xml":"<i><d p=\"1,1,25,16777215\">fallback</d></i>"}')

-- Current episode focus works for both menu systems and keeps return row offset.
fire('end-file'); uosc_available = true
get_episodes('Show', 12, 'https://one.test', 'Show @主源')
respond(#pending, '{"bangumi":{"episodes":[{"episodeNumber":"1","episodeId":1,"episodeTitle":"one"},{"episodeNumber":"2","episodeId":2,"episodeTitle":"two"}]}}')
local episode_menu = parse_json_table(commands[#commands][4])
equal(episode_menu.selected_index, 2, 'uosc current episode focused after back row')
equal(episode_menu.items[2].active, true, 'one episode marked current')
uosc_available = false
get_episodes('Show', 12, 'https://one.test', 'Show')
respond(#pending, '{"bangumi":{"episodes":[{"episodeNumber":"1","episodeId":1,"episodeTitle":"one"}]}}')
flush_timers()
equal(last_select.default_item, 2, 'mp.input current episode focused')

-- Both kinds of search-history UI can remove one record without losing others.
options.search_history_path = test_root .. '/audit-search.json'
options.search_history_limit = 0
messages['search-anime-event']('First')
messages['search-anime-event']('Second')
messages['search-anime-event']('First')
local history = parse_json_table(read_file(options.search_history_path))
equal(#history, 2, 'unlimited history and duplicate promotion')
equal(history[1].keyword, 'First', 'recent keyword first')
uosc_available = true; open_search_history()
messages['search-history-action'](py_format_json({type='activate', action='delete',
    value={'script-message-to','uosc_danmaku','search-anime-event','First'}}))
history = parse_json_table(read_file(options.search_history_path))
equal(#history, 1, 'uosc removes only chosen history record')
equal(history[1].keyword, 'Second', 'other history retained')
uosc_available = false; open_search_history()
last_select.submit(1); last_select.submit(2)
equal(#parse_json_table(read_file(options.search_history_path)), 0, 'mp.input history deletion')

-- Save modes restrict destination selection; legacy alias remains valid.
options.save_danmaku_path = test_root .. '/custom'
options.save_danmaku_path_mode = 'local'
equal(get_danmaku_save_directory('https://video.test/movie'), nil, 'local mode excludes URL')
equal(get_danmaku_save_directory(test_root .. '/movie.mkv'), options.save_danmaku_path, 'local save destination')
options.save_danmaku_path_mode = 'url'
equal(get_danmaku_save_directory(test_root .. '/movie.mkv'), nil, 'url mode excludes local')
equal(get_danmaku_save_directory('https://video.test/movie'), options.save_danmaku_path, 'url save destination')
options.save_danmaku_path_mode = 'all'
equal(get_danmaku_save_directory(test_root .. '/movie.mkv'), options.save_danmaku_path, 'all save destination')
options.save_danmaku_path = ''; options.danmaku_save_path = test_root .. '/legacy'
equal(get_danmaku_save_directory('https://video.test/movie'), options.danmaku_save_path, 'legacy destination retained')
options.danmaku_save_path = ''

-- Failed automatic loads prompt once per generation, never after successful render.
fire('end-file'); COMMENTS = {}; options.auto_fallback_search = false
count = #commands; auto_load_fallback(); equal(#commands, count, 'fallback disabled by default')
options.auto_fallback_search = true
auto_load_fallback(); auto_load_fallback()
equal(#commands, count + 1, 'one fallback prompt per generation')
fire('end-file'); COMMENTS = {{time=0,text='present'}}
count = #commands; auto_load_fallback(); equal(#commands, count, 'successful load suppresses fallback')
options.auto_fallback_search = false; options.api_servers = ''

fire('end-file')
for _, callback in ipairs(hooks) do callback() end
equal(#DELAYS,0,'delay reset on unload')
equal(properties[DANMAKU_COUNT],0,'count reset on unload')
