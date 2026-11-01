local msg = require('mp.msg')
local utils = require("mp.utils")

local repo = "Loukyuu1120/uosc_danmaku"
local zip_file = utils.join_path(os.getenv("TEMP") or "/tmp/", "uosc_danmaku-" .. tostring(utils.getpid()) .. ".zip")

local local_version = VERSION or "0.0.0"
local platform = mp.get_property("platform")
local updating = false

local function await_update_command(command)
    local worker = coroutine.running()
    call_cmd_async(command.args, function(err, output)
        local ok, detail = coroutine.resume(worker, {status = err and 1 or 0, stdout = output or '', stderr = err or ''})
        if not ok then updating = false; msg.error(tostring(detail)); show_message('更新失败，查看控制台', 3) end
    end, {playback_only = false})
    return coroutine.yield()
end

local function version_greater(v1, v2)
    local function parse(ver)
        local a, b, c = ver:match("v?(%d+)%.(%d+)%.(%d+)")
        return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
    end
    local a1, a2, a3 = parse(v1)
    local b1, b2, b3 = parse(v2)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

local function get_latest_release(repo)
    local url = "https://api.github.com/repos/" .. repo .. "/releases/latest"
    local cmd = { "curl", "--fail", "--connect-timeout", "10", "--max-time", "30", "-sL", url }
    local res = await_update_command({
        name = "subprocess",
        args = cmd,
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    })
    if not res or res.status ~= 0 then return nil end
    local tag = res.stdout:match([["tag_name"%s*:%s*"([^"]+)"]])
    local zip_url = res.stdout:match([["browser_download_url"%s*:%s*"([^"]+%.zip)"]])
    return tag, zip_url
end

local function escape_ps(str)
    return tostring(str):gsub("'", "''")
end

local function unzip_overwrite(archive)
    local outpath = mp.get_script_directory()
    local backup = outpath .. '.backup-' .. tostring(utils.getpid()) .. '-' .. tostring(os.time())
    local staging = backup .. '-staging'
    local script, args
    if platform == 'windows' then
        script = string.format([[
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath('%s')
$backup = [IO.Path]::GetFullPath('%s')
$stage = [IO.Path]::GetFullPath('%s')
if ((Split-Path -Parent $target) -ne (Split-Path -Parent $stage)) { throw 'Invalid staging path' }
if ((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $stage)) { throw 'Update path already exists' }
Expand-Archive -LiteralPath '%s' -DestinationPath $stage
if (-not (Test-Path -LiteralPath (Join-Path $stage 'main.lua'))) {
    $children = @(Get-ChildItem -LiteralPath $stage -Directory)
    if ($children.Count -ne 1) { throw 'Invalid update layout' }
    $stage = $children[0].FullName
}
foreach ($required in @('main.lua','modules/options.lua','modules/render.lua','apis/dandanplay.lua')) {
    if (-not (Test-Path -LiteralPath (Join-Path $stage $required) -PathType Leaf)) { throw 'Incomplete update archive' }
}
Move-Item -LiteralPath $target -Destination $backup
try { Move-Item -LiteralPath $stage -Destination $target }
catch {
    if (-not (Test-Path -LiteralPath $target)) { Move-Item -LiteralPath $backup -Destination $target }
    throw
}
]], escape_ps(outpath), escape_ps(backup), escape_ps(staging), escape_ps(archive))
        args = {'powershell', '-NoProfile', '-NonInteractive', '-Command', script}
    else
        script = [[
set -eu
target=$1
backup=$2
stage=$3
archive=$4
[ ! -e "$backup" ] && [ ! -e "$stage" ]
mkdir "$stage"
unzip -q "$archive" -d "$stage"
if [ ! -f "$stage/main.lua" ]; then
    set -- "$stage"/*
    [ "$#" -eq 1 ] && [ -d "$1" ]
    stage=$1
fi
for required in main.lua modules/options.lua modules/render.lua apis/dandanplay.lua; do
    [ -f "$stage/$required" ]
done
mv "$target" "$backup"
if ! mv "$stage" "$target"; then
    mv "$backup" "$target"
    exit 1
fi
]]
        args = {'sh', '-c', script, 'uosc-update', outpath, backup, staging, archive}
    end
    local result = await_update_command({name = 'subprocess', args = args,
        capture_stdout = true, capture_stderr = true, playback_only = false})
    if not result or result.status ~= 0 then
        msg.error('更新失败，原目录或备份已保留：' .. backup .. ' ' .. (result and result.stderr or ''))
        return false
    end
    msg.info('更新完成，原版本备份：' .. backup)
    return true
end

local function perform_update()
    msg.info("正在检查更新...")
    local latest_version, download_url = get_latest_release(repo)
    if not latest_version or not download_url then
        show_message("❌ 无法获取最新版本信息")
        msg.warn("❌ 无法获取最新版本信息")
        return
    end

    if not version_greater(latest_version, local_version) then
        show_message("✅ 已是最新版本 ("..local_version..")")
        msg.info("✅ 已是最新版本")
        return
    end

    show_message("⬇️ 发现新版本: " .. latest_version .. "，正在下载...")
    msg.info("⬇️ 发现新版本: " .. latest_version .. "，地址: " .. download_url)

    local cmd = { "curl", "--fail", "--connect-timeout", "10", "--max-time", "120", "-L", "-o", zip_file, download_url }
    local res = await_update_command({
        name = "subprocess",
        args = cmd,
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    })
    if not res or res.status ~= 0 then
        show_message("❌ 下载失败！")
        msg.warn("❌ 下载失败！")
        return
    end

    show_message("📦 下载完成，开始安装...")
    msg.info("📦 下载完成，开始安装...")

    if unzip_overwrite(zip_file) then
        os.remove(zip_file)
        show_message("✅ 更新成功！请重启 mpv")
        msg.info("✅ 更新成功，当前版本为：" .. latest_version)
    else
        os.remove(zip_file)
        show_message("❌ 解压失败！请查看控制台日志")
        msg.warn("❌ 解压失败！")
    end
end

function check_for_update()
    if updating then show_message('更新正在进行中', 2); return end
    updating = true
    local worker = coroutine.create(function() perform_update(); updating = false end)
    local ok, detail = coroutine.resume(worker)
    if not ok then updating = false; msg.error(tostring(detail)) end
end
