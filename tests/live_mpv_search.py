"""Run the configured search requests in a separate, headless mpv instance.

The report omits API paths, tokens, response bodies and signing headers.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


LUA = r'''
local utils = require('mp.utils')
local results = {}
local finished = false
local function finish()
    if finished then return end
    finished = true
    local output = assert(io.open(WORK .. '/results.json', 'wb'))
    output:write(utils.format_json(results)); output:close()
    mp.commandv('quit')
end
mp.add_timeout(40, finish)
package.path = ROOT .. '/?.lua;' .. package.path
local ok, failure = pcall(dofile, ROOT .. '/main.lua')
if not ok then results[1] = {startup_error = tostring(failure)}; finish(); return end
local f = assert(io.open(WORK .. '/settings.json', 'rb'))
local settings = utils.parse_json(f:read('*a')); f:close()
for k,v in pairs(settings) do options[k] = v end
if LEGACY then dofile(WORK .. '/baseline.lua') end
local servers = get_api_servers()
local remaining = #servers
for i,server in ipairs(servers) do
  if not ONLY_HOST or server:match('^https?://([^/]+)') == ONLY_HOST then
    local search = MODE == 'search' or server:find('api%.dandanplay%.')
    local url = server .. (search and '/api/v2/search/anime?keyword=' .. url_encode(QUERY) or '/api/v2/match')
    local body = not search and {fileName = QUERY .. ' S1E1', matchMode = 'fileNameOnly',
        fileHash = 'a1b2c3d4e5f67890abcd1234ef567890'} or nil
    local args = make_danmaku_request_args(search and 'GET' or 'POST', url, nil, body)
    args[#args + 1] = '-S'
    args[#args + 1] = '--write-out'
    args[#args + 1] = '\nUOSC_HTTP_STATUS:%{http_code}'
    mp.command_native_async({name = 'subprocess', args = args, capture_stdout = true,
        capture_stderr = true, playback_only = false}, function(success, result, err)
        local raw = result and result.stdout
        local http_status = type(raw) == 'string' and raw:match('\nUOSC_HTTP_STATUS:(%d+)') or nil
        if type(raw) == 'string' then
            raw = raw:gsub('\nUOSC_HTTP_STATUS:%d+', ''):gsub('\n__UOSC_HTTP_STATUS__:%d+', '')
        end
        local parsed = type(raw) == 'string' and utils.parse_json(raw) or nil
        local item = {index = i, host = server:match('^https?://([^/]+)'), success = success,
            status = result and result.status, stdout_type = type(raw),
            bytes = type(raw) == 'string' and #raw or -1, parsed_type = type(parsed),
            stderr_bytes = result and type(result.stderr) == 'string' and #result.stderr or -1}
        item.http_status = http_status
        local stderr = result and result.stderr or ''
        item.transport_error = stderr:gsub('https?://[^%s]+', '[URL omitted]'):sub(1, 350)
        if type(parsed) == 'table' then
            item.keys = {}; for key in pairs(parsed) do item.keys[#item.keys + 1] = tostring(key) end
            item.animes = type(parsed.animes) == 'table' and #parsed.animes or nil
            item.matches = type(parsed.matches) == 'table' and #parsed.matches or nil
            item.isMatched = parsed.isMatched
            item.errorCode = parsed.errorCode
            item.errorMessage = parsed.errorMessage
            item.titles = {}
            for _,anime in ipairs(parsed.animes or parsed.matches or {}) do
                item.titles[#item.titles + 1] = anime.animeTitle
            end
        end
        results[#results + 1] = item
        remaining = remaining - 1
        if remaining == 0 then finish() end
    end)
  else
    remaining = remaining - 1
  end
end
'''


def run(mpv_dir, plugin_dir, query, baseline=False, only_host=None, mode='match', server=None):
    config = {}
    config_path = mpv_dir / 'portable_config/script-opts/uosc_danmaku.conf'
    for line in config_path.read_text(encoding='utf-8-sig').splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            if key.strip() in ('api_server', 'api_servers', 'proxy', 'user_agent', 'cookie_file', 'request_timeout'):
                config[key.strip()] = value.strip()
    if server:
        config['api_servers'] = server
    with tempfile.TemporaryDirectory(prefix='uosc-live-probe-') as directory:
        work = Path(directory)
        (work / 'settings.json').write_text(json.dumps(config, ensure_ascii=False), encoding='utf-8')
        if baseline:
            (work / 'baseline.lua').write_bytes(subprocess.check_output(
                ['git', 'show', 'origin/main:apis/dandanplay.lua'], cwd=Path(__file__).resolve().parents[1]))
        bindings = '\n'.join('local ' + key + '=' + json.dumps(value, ensure_ascii=False)
                             for key, value in [('ROOT', plugin_dir.as_posix()), ('WORK', work.as_posix()), ('QUERY', query)])
        bindings += '\nlocal LEGACY=' + ('true' if baseline else 'false')
        bindings += '\nlocal ONLY_HOST=' + (json.dumps(only_host) if only_host else 'nil')
        bindings += '\nlocal MODE=' + json.dumps(mode)
        (work / 'probe.lua').write_text(bindings + '\n' + LUA, encoding='utf-8')
        try:
            result = subprocess.run([str(mpv_dir / 'mpv.exe'), '--no-config', '--load-scripts=no',
                                     '--idle=yes', '--force-window=no', '--vo=null', '--ao=null',
                                     '--script=' + str(work / 'probe.lua')], cwd=mpv_dir,
                                    capture_output=True, timeout=50,
                                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b'').decode('utf-8', errors='replace')
            return {'timeout': True, 'errors': [line for line in output.splitlines()
                                               if '.lua:' in line or 'stack traceback' in line]}
        report = work / 'results.json'
        if report.exists():
            return json.loads(report.read_text(encoding='utf-8'))
        return {'exit_code': result.returncode, 'report_missing': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mpv-dir', type=Path, required=True)
    parser.add_argument('--plugin-dir', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--query', required=True)
    parser.add_argument('--baseline', action='store_true')
    parser.add_argument('--only-host')
    parser.add_argument('--mode', choices=['match', 'search'], default='match')
    parser.add_argument('--server')
    arguments = parser.parse_args()
    print(json.dumps(run(arguments.mpv_dir, arguments.plugin_dir, arguments.query,
                         arguments.baseline, arguments.only_host, arguments.mode, arguments.server), ensure_ascii=True, indent=2))
