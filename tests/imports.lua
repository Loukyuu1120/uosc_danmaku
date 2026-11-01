local function equal(actual, expected, label)
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function parsed(data)
    return parse_danmaku_sources({{type='memory', data=data, url='fixture'}}, {})
end
local function args_for_last_request() return pending[#pending].command.args end
local function option(args, key)
    for i, value in ipairs(args) do if value == key then return args[i + 1] end end
end

-- All curl callers share proxy injection, including absolute curl.exe paths,
-- retries, site segment requests, and non-playback update requests.
fire('end-file')
options.proxy = 'http://127.0.0.1:18234'
options.cookie_file = test_root .. '/cookies.txt'
local original = {'curl', '--', 'https://example.test'}
call_cmd_async(original, function() end)
equal(option(args_for_last_request(), '--proxy'), options.proxy, 'generic curl proxy')
equal(#original, 3, 'caller arguments not mutated')
call_cmd_async({'C:\\Windows\\System32\\curl.exe', 'https://example.test'}, function() end)
equal(option(args_for_last_request(), '--proxy'), options.proxy, 'absolute curl.exe proxy')
call_cmd_async({'curl', '-x', 'http://explicit.test', 'https://example.test'}, function() end)
equal(option(args_for_last_request(), '-x'), 'http://explicit.test', 'explicit proxy retained')
equal(option(args_for_last_request(), '--proxy'), nil, 'no duplicate proxy option')
call_cmd_async({'powershell', '-Command', 'test'}, function() end)
equal(option(args_for_last_request(), '--proxy'), nil, 'non-curl subprocess untouched')

load_danmaku_for_tencent('https://v.qq.com/x/cover/show/vid.html', function() end)
equal(option(args_for_last_request(), '--proxy'), options.proxy, 'Tencent proxy')
equal(option(args_for_last_request(), '-b'), options.cookie_file, 'Tencent cookie')
respond(#pending, '{"segment_index":{"0":{"segment_start":0,"segment_end":30000}}}')
equal(option(args_for_last_request(), '--proxy'), options.proxy, 'Tencent follow-up proxy')

load_danmaku_for_mgtv('https://www.mgtv.com/b/123/456.html', function() end)
equal(option(args_for_last_request(), '--proxy'), options.proxy, 'Mango metadata proxy')
equal(option(args_for_last_request(), '-b'), options.cookie_file, 'Mango metadata cookie')
local info_request = #pending
respond(info_request, '{"code":200,"data":{"info":{"time":120}}}')
equal(#pending, info_request + 2, 'Mango creates two segment requests')
-- If the response created segments, those must retain both options too.
equal(option(args_for_last_request(), '--proxy'), options.proxy, 'Mango segment proxy')
equal(option(args_for_last_request(), '-b'), options.cookie_file, 'Mango segment cookie')

check_for_update()
equal(option(args_for_last_request(), '--proxy'), options.proxy, 'update lookup proxy')
equal(option(args_for_last_request(), '-b'), nil, 'site cookies not attached to GitHub')
respond(#pending, '{"tag_name":"v99.0.0","assets":[{"browser_download_url":"https://example.test/update.zip"}]}')
equal(option(args_for_last_request(), '--proxy'), options.proxy, 'update download proxy')
equal(pending[#pending].command.playback_only, false, 'updater survives playback changes')
equal(option(args_for_last_request(), '-b'), nil, 'download excludes site cookie file')
respond(#pending, '', 22)
options.proxy, options.cookie_file = '', ''
fire('end-file')

-- Exported text rules are literal; TXT rules remain Lua patterns.
options.blacklist_path = test_root .. '/typed.json'
assert(write_json_file(options.blacklist_path, {
    {type=0, filter='a.b[1]%', opened=true},
    {type=1, filter='^(?:广告|推广)[0-9]{2,3}$', opened=true},
    {type=2, filter='42', opened=true},
    {type=3, filter='#FF0000', opened=true},
    {type=0, filter='disabled', opened=false},
    {type=99, filter='unknown', opened=true},
}))
get_blacklist_patterns(true)
equal(#parsed({{time=0,text='xa.b[1]%y'}}), 0, 'literal JSON text match')
equal(#parsed({{time=0,text='aXb1'}}), 1, 'literal text is not Lua pattern')
equal(#parsed({{time=0,text='推广123'}}), 0, 'imported regex alternation and quantifier')
equal(#parsed({{time=0,text='推广1'}}), 1, 'regex non-match')
equal(#parsed({{time=0,text='ordinary',user_id='42'}}), 0, 'JSON user ID rule')
equal(#parsed({{time=0,text='ordinary'}}), 1, 'missing author metadata does not hide comments')
equal(#parsed({{time=0,text='ordinary',color=0xFF0000}}), 0, 'JSON color rule')
equal(#parsed({{time=0,text='disabled unknown'}}), 1, 'disabled and unknown rules do not match')

local rules = require('modules/block_rules')
equal(rules.user_hash('123456789'), 'cbf43926', 'CRC32 known answer')
local white_rule = assert(rules.compile({kind='color',pattern='#FFFFFF'}))
equal(rules.matches(white_rule,'default color',{}),true,'color rules use renderer default')
equal(rules.matches(assert(rules.compile({kind='user',pattern='0'})),'anonymous',{user_id='0',user_hash='0'}),false,'anonymous sentinel is not a real user')
local user_hash = rules.user_hash('42')
local xml = '<i><d p="0,1,25,16777215,123,0,' .. user_hash .. ',9">sender</d></i>'
equal(#parsed(xml), 0, 'Bilibili XML user hash matches exported numeric UID')
local xml_normalized = normalize_danmaku_response({xml=xml})
local api_normalized = save_danmaku_json(xml_normalized.comments)
equal(api_normalized[1].user_hash, user_hash, 'XML API normalization retains author hash')
equal(#parsed(api_normalized), 0, 'user rule still works after API normalization')
local api_record = save_danmaku_json({{p='1,1,16777215,42',m='API author'}})
equal(api_record[1].user_id, '42', 'API p field user ID retained')
equal(#parsed(api_record), 0, 'API user rule')
local factory = parse_json_danmaku('[{"c":"0,16777215,1,25,,,abc123","m":"factory author"}]')
equal(factory[1].user_hash, 'abc123', 'factory CSV preserves empty columns')
local acfun = parse_json_danmaku('[{"c":"0,16777215,1,25,abcdef,123456","m":"AcFun author"}]')
equal(acfun[1].user_hash, 'abcdef', 'AcFun CSV fifth column is author hash')

-- Editing any known type preserves its type, enable state, and unknown nodes.
local state = blacklist_get_state(true)
equal(#state.entries, 5, 'all supported JSON rule types editable')
assert(blacklist_edit_entry(3, '43'))
assert(blacklist_toggle_entry(4))
local saved = parse_json_table(read_file(options.blacklist_path))
equal(saved[3].type, 2, 'edited user rule remains user type')
equal(saved[3].filter, '43', 'user rule edit saved')
equal(saved[4].opened, false, 'color toggle saved')
equal(saved[6].type, 99, 'unknown JSON type preserved')
assert(blacklist_add_entry('r=foo|bar'))
saved = parse_json_table(read_file(options.blacklist_path))
equal(saved[#saved].type, 1, 'typed regex addition')
equal(blacklist_add_entry('r=['), false, 'invalid regex rejected without writing')

options.blacklist_path = test_root .. '/wrapped.json'
assert(write_json_file(options.blacklist_path, {['$schema']='fixture-schema', rules={
    {type=1,filter='(.+)\\1{2,}',opened=true}, {type=2,filter='42',opened=true},
}}))
get_blacklist_patterns(true)
equal(#parsed({{time=0,text='哈哈哈哈'}}),0,'wrapped JSON and regex backreference')
equal(#parsed({{time=0,text='other',user_id='42'}}),0,'wrapped user rule')
state = blacklist_get_state(true)
assert(blacklist_edit_entry(2,'43'))
local wrapped = parse_json_table(read_file(options.blacklist_path))
equal(wrapped['$schema'],'fixture-schema','wrapped JSON metadata retained')
equal(wrapped.rules[2].type,2,'wrapped JSON user type retained')
assert(blacklist_delete_entry(1)); blacklist_get_state(true); assert(blacklist_delete_entry(1))
assert(read_file(options.blacklist_path):find('"rules":%s*%[%]'),'empty wrapped rules remain an array')


options.blacklist_path = test_root .. '/typed.xml'
assert(write_file(options.blacklist_path, [[<filters>
<item enabled='true' note="keep">t=a.b</item><item enabled="true">r=^推广\d+$</item>
<item enabled="true">u=42</item><item enabled="true">c=FF0000</item>
<item enabled="false">t=disabled</item><item enabled="true">z=unknown</item>
</filters>]]))
get_blacklist_patterns(true)
equal(#parsed({{time=0,text='a.b'}}), 0, 'XML literal text')
equal(#parsed({{time=0,text='aXb'}}), 1, 'XML text punctuation stays literal')
equal(#parsed({{time=0,text='推广123'}}), 0, 'XML regex')
equal(#parsed({{time=0,text='ordinary',user_hash=user_hash}}), 0, 'XML user rule')
equal(#parsed({{time=0,text='ordinary',color=0xFF0000}}), 0, 'XML color rule')
state = blacklist_get_state(true)
equal(#state.entries, 5, 'multiple XML items per line and both quote styles')
assert(blacklist_edit_entry(2, '^广告\\d+$'))
assert(blacklist_toggle_entry(1))
assert(blacklist_add_entry('u=77'))
local saved_xml = read_file(options.blacklist_path)
assert(saved_xml:find('r=^广告\\d+$',1,true), 'XML regex prefix preserved')
assert(saved_xml:find('u=77',1,true), 'XML user prefix added')
assert(saved_xml:find('note="keep"',1,true), 'unknown XML attribute preserved')
assert(saved_xml:find('z=unknown',1,true), 'unknown XML rule preserved')
assert(blacklist_delete_entry(4))
saved_xml = read_file(options.blacklist_path)
assert(not saved_xml:find('c=FF0000',1,true), 'color rule deleted')

-- Local XML export preserves author metadata instead of losing user rules.
options.blacklist_path = ''; get_blacklist_patterns(true)
local original_user = {time=1,type=1,color=1,text='kept',user_id='42',user_hash=user_hash}
local exported = test_root .. '/authors.xml'
assert(convert_danmaku_to_xml({original_user}, exported))
local roundtrip = parse_xml_danmaku(read_file(exported))
equal(roundtrip[1].user_id, '42', 'XML export user ID round-trip')
equal(roundtrip[1].user_hash, user_hash, 'XML export user hash round-trip')

-- Time-based adjustment affects one source from the raw boundary onward.
fire('end-file')
DANMAKU.sources = {
    first = {data={{time=9,type=1,text='before'},{time=10,type=1,text='boundary'},{time=11,type=1,text='after'}}},
    second = {data={{time=10,type=1,text='other'}}, delay_segments={{start=0,delay=3}}},
}
DELAYS, DELAY = {}, 0
messages['danmaku-delay']('2', '10', 'first')
local shifted = parse_danmaku_sources({{data=DANMAKU.sources.first.data,url='first'},{data=DANMAKU.sources.second.data,url='second'}},
    {DANMAKU.sources.first.delay_segments,DANMAKU.sources.second.delay_segments})
local times = {}; for _, record in ipairs(shifted) do times[record.text] = record.time end
equal(times.before,9,'earlier comment unchanged')
equal(times.boundary,12,'raw boundary included')
equal(times.after,13,'later comment adjusted')
equal(times.other,13,'other source delay unchanged')
equal(DELAY,0,'per-source adjustment does not change global delay')
equal(parse_delay_input('-0m15s'),-15,'negative sub-minute delay')
equal(parse_delay_input('1m02s'),62,'minute and second input')
equal(parse_delay_input('nan'),nil,'non-finite delay rejected')
local old_count = #DANMAKU.sources.first.delay_segments
messages['danmaku-delay']('3','nan','first')
equal(#DANMAKU.sources.first.delay_segments,old_count,'invalid boundary does not mutate delay')

uosc_available = true
open_delay_from_time('first',10)
local menu = parse_json_table(commands[#commands][4])
equal(menu.on_search[3], 'setup-content-delay', 'uosc time-based delay input')
equal(menu.on_search[4], '10', 'raw timestamp in delay input')
uosc_available = false
open_delay_from_time('first',10); flush_timers()
assert(last_input and last_input.submit, 'mp.input time-based delay input')
last_input.submit('1m02s')
local command = commands[#commands]
equal(command[3],'setup-content-delay','mp.input emits time-based delay action')
equal(command[4],'10','mp.input preserves raw boundary')

-- HTTP failures and empty results must proceed through the API list, then fallback.
fire('end-file')
options.api_servers='https://first.test,https://second.test'
add_danmaku_source_online('https://video.test/watch?a=1&b=2',true,true)
respond(#pending,'',22)
assert(table.concat(args_for_last_request(),' '):find('https://second.test/api/v2/extcomment',1,true), 'failed first API reaches second API')
respond(#pending,'{"comments":[],"count":0}')
flush_timers()
respond(#pending,'{"comments":[],"count":0}')
assert(table.concat(args_for_last_request(),' '):find('/?ac=dm&url=',1,true), 'empty last API reaches fallback')
options.api_servers = ''; options.blacklist_path = ''
fire('end-file')

-- Closing an old search menu cannot cancel a newer episode request.
fire('end-file'); uosc_available = true
options.api_servers = 'https://one.test,https://two.test'
get_animes('Show')
local stale_search = #pending - 1
local search_props
for _, command in ipairs(commands) do
    local menu = command[4] and parse_json_table(command[4])
    if menu and menu.type == 'menu_anime' then search_props = menu end
end
get_episodes('Show',12,'https://one.test','Show')
local episode_request = #pending
assert(pending[stale_search].aborted, 'episode selection cancels old search requests')
messages['cancel-active-request'](search_props.on_close[4])
equal(pending[episode_request].aborted,nil,'old on_close does not cancel new request')
local before = #commands
respond(stale_search,'{"animes":[{"animeTitle":"stale","bangumiId":12}]}')
equal(#commands,before,'cancelled search cannot overwrite episode menu')
respond(episode_request,'{"bangumi":{"episodes":[{"episodeId":1,"episodeNumber":"1","episodeTitle":"one"}]}}')
messages['cancel-active-request']()
assert(messages['open_danmaku_style_menu'] and messages['open-latest-menu-anime'] and messages['setup-danmaku-search-history'], 'upstream control aliases registered')
options.api_servers = ''; uosc_available = false
fire('end-file')

-- Cache expiry still works after selecting an episode cancelled its old timer.
fire('end-file'); options.api_servers = 'https://one.test'; uosc_available = true
get_animes('Cache Show')
respond(#pending,'{"animes":[{"animeTitle":"Cache Show","bangumiId":12}]}')
invalidate_playback_requests()
local clock = mp.get_time
mp.get_time = function() return clock() + 61 end
local cache_start = #pending
get_animes('Cache Show')
equal(#pending,cache_start+1,'expired search cache queried after timer cancellation')
mp.get_time = clock; options.api_servers = ''; uosc_available = false
fire('end-file')
