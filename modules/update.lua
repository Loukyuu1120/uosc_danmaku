local msg = require('mp.msg')
local utils = require("mp.utils")

local repo = "Loukyuu1120/uosc_danmaku"
local zip_file = utils.join_path(os.getenv("TEMP") or "/tmp/", "uosc_danmaku.zip")

local local_version = VERSION or "0.0.0"
local platform = mp.get_property("platform")

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
    local cmd = { "curl", "-sL", url }
    local res = mp.command_native({
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

local function unzip_overwrite(zip_path)
    local cmd = {}
    local outpath = mp.get_script_directory()

    msg.info("正在解压到: " .. outpath)
    -- ohno妈咪何意味，覆盖代替先删除
    if platform == "windows" then
        -- 1. Windows PowerShell
        local ps_script = string.format(
            "Expand-Archive -LiteralPath '%s' -DestinationPath '%s' -Force",
            zip_path:gsub("/", "\\"),
            outpath:gsub("/", "\\")
        )

        cmd = {
            "powershell", "-NoProfile", "-Command", ps_script
        }
    else
        -- Linux/Mac
        cmd = { "unzip", "-o", zip_path, "-d", outpath }
    end

    local res = mp.command_native({
        name = "subprocess",
        args = cmd,
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    })
    if res.status ~= 0 then
        msg.error("解压命令输出: " .. (res.stdout or "") .. (res.stderr or ""))
    end

    return res and res.status == 0
end

function check_for_update()
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

    local cmd = { "curl", "-L", "-o", zip_file, download_url }
    local res = mp.command_native({
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
