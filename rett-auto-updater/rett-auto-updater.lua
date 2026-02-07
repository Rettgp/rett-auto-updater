-- rett-auto-updater.lua
-- Windower addon: Automatically updates specified addons based on a remote manifest
-- Author: Rettgp

_addon.name = 'rett-auto-updater'
_addon.version = '1.1.0'
_addon.author = 'Rettgp'
_addon.commands = { 'rettautoupdater', 'rettau' }

local json = require('json')
local https = require('ssl.https')
local ltn12 = require('ltn12')
local files = require('files')

local GITHUB_USER = 'Rettgp'
local GITHUB_REPO = 'ffxi-addons'
local MANIFEST_URL = string.format('https://github.com/%s/%s/releases/download/latest/manifest.json', GITHUB_USER,
    GITHUB_REPO)

local function download_file(url, output_path)
    local max_redirects = 5
    local redirects = 0

    while redirects < max_redirects do
        local file = io.open(output_path, 'wb')
        if not file then return false, 'Cannot open file for writing: ' .. output_path end

        local _, code, headers = https.request {
            url = url,
            sink = ltn12.sink.file(file)
        }
        -- Note: ltn12.sink.file() closes the file automatically

        if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
            url = headers.location or headers.Location
            if not url then
                return false, 'Redirect without location header'
            end
            redirects = redirects + 1
        elseif code == 200 then
            return true
        else
            return false, 'HTTP error: ' .. tostring(code)
        end
    end

    return false, 'Too many redirects'
end

local function get_local_version(addon_name)
    local version_file = windower.addon_path .. '../' .. addon_name .. '/' .. addon_name .. '.lua'
    local f = io.open(version_file, 'r')
    if not f then return nil end
    local content = f:read('*a')
    f:close()
    local version = content:match("version%s*=%s*['\"]([%d%.]+)['\"]")
    return version
end

local function update_addon(addon_name, download_url, is_new_install)
    windower.add_to_chat(207, ('[rett-auto-updater] Downloading %s'):format(addon_name, download_url))

    local temp_zip = windower.addon_path .. 'temp_' .. addon_name .. '.zip'
    local temp_extract = windower.addon_path .. 'temp_extract_' .. addon_name .. '\\'
    local addon_path = windower.addon_path .. '..\\' .. addon_name .. '\\'

    local success, err = download_file(download_url, temp_zip)

    if not success then
        windower.add_to_chat(123, ('[rett-auto-updater] Failed to download %s: %s'):format(addon_name, err))
        return
    end

    windower.add_to_chat(207, ('[rett-auto-updater] Extracting %s...'):format(addon_name))

    os.execute('mkdir "' .. temp_extract .. '" 2>nul')

    local extract_cmd = string.format('powershell -command "Expand-Archive -Path \'%s\' -DestinationPath \'%s\' -Force"',
        temp_zip, temp_extract)
    local extract_result = os.execute(extract_cmd)

    if extract_result ~= 0 then
        windower.add_to_chat(123, ('[rett-auto-updater] Failed to extract %s'):format(addon_name))
        os.remove(temp_zip)
        os.execute('rmdir /S /Q "' .. temp_extract .. '" 2>nul')
        return
    end

    os.execute('mkdir "' .. addon_path .. '" 2>nul')

    windower.add_to_chat(207, ('[rett-auto-updater] Installing %s...'):format(addon_name))
    local copy_result = os.execute('xcopy "' ..
        temp_extract .. addon_name .. '\\*" "' .. addon_path .. '" /E /Y /I >nul 2>&1')

    if copy_result ~= 0 then
        windower.add_to_chat(123, ('[rett-auto-updater] Failed to install %s'):format(addon_name))
        os.remove(temp_zip)
        os.execute('rmdir /S /Q "' .. temp_extract .. '" 2>nul')
        return
    end

    os.remove(temp_zip)
    os.execute('rmdir /S /Q "' .. temp_extract .. '" 2>nul')

    if is_new_install then
        windower.send_command('lua load ' .. addon_name)
    else
        windower.send_command('lua reload ' .. addon_name)
    end
end

local function get_manifest()
    local response = {}
    local url = MANIFEST_URL
    local max_redirects = 10
    local redirects = 0
    local previous_url = nil

    while redirects < max_redirects do
        response = {}
        local _, code, headers = https.request {
            url = url,
            sink = ltn12.sink.table(response)
        }

        if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
            local new_url = headers.location or headers.Location
            if not new_url then
                error('[rett-auto-updater] Redirect without location header')
                return nil
            end

            if new_url == url or new_url == previous_url then
                error(
                    '[rett-auto-updater] Redirect loop detected - socket.http may not support HTTPS. Try using a different manifest URL.')
                return nil
            end

            previous_url = url
            url = new_url
            redirects = redirects + 1
        elseif code == 200 then
            break
        else
            error('[rett-auto-updater] Failed to fetch manifest: HTTP ' .. tostring(code))
            return nil
        end
    end

    if redirects >= max_redirects then
        error('[rett-auto-updater] Too many redirects fetching manifest')
        return nil
    end

    local manifest_json = table.concat(response)
    local success, manifest = pcall(json.parse, manifest_json)
    if not success then
        windower.add_to_chat(123, ('[rett-auto-updater] JSON parse error: %s'):format(tostring(manifest)))
        return nil
    end
    if not manifest then
        windower.add_to_chat(123, '[rett-auto-updater] Manifest is nil after parsing')
        return nil
    end
    return manifest
end

windower.register_event('load', function()
    windower.add_to_chat(207, '[rett-auto-updater] Checking for addon updates...')
    local manifest = get_manifest()
    if not manifest then return end

    for addon_name, remote_info in pairs(manifest.addons or {}) do
        local local_version = get_local_version(addon_name)
        local download_url = string.format('https://github.com/%s/%s/releases/download/latest/%s-v%s.zip', GITHUB_USER,
            GITHUB_REPO, addon_name, remote_info.version)

        if not local_version then
            windower.add_to_chat(207,
                ('[rett-auto-updater] %s not found locally. Installing version %s'):format(addon_name,
                    remote_info.version))
            update_addon(addon_name, download_url, true)
        elseif local_version ~= remote_info.version then
            windower.add_to_chat(207,
                ('[rett-auto-updater] %s is outdated (local: %s, remote: %s)'):format(addon_name, local_version,
                    remote_info.version))
            update_addon(addon_name, download_url, false)
        end
    end

    windower.add_to_chat(207, '[rett-auto-updater] Loading all addons from manifest...')
    for addon_name, _ in pairs(manifest.addons or {}) do
        windower.send_command('lua load ' .. addon_name)
    end
    windower.add_to_chat(207, '[rett-auto-updater] Update check complete.')
end)

-- Command: Manual update check
windower.register_event('addon command', function(cmd, ...)
    if cmd == 'check' then
        windower.send_command('lua reload rett-auto-updater')
    elseif cmd == 'unload' then
        local args = { ... }
        if args[1] == 'all' then
            local manifest = get_manifest()
            if not manifest then return end
            windower.add_to_chat(207, '[rett-auto-updater] Unloading all addons from manifest...')
            for addon_name, _ in pairs(manifest.addons or {}) do
                windower.send_command('lua unload ' .. addon_name)
            end
            windower.add_to_chat(207, '[rett-auto-updater] All addons unloaded.')
        end
    elseif cmd == 'load' then
        local args = { ... }
        if args[1] == 'all' then
            local manifest = get_manifest()
            if not manifest then return end
            windower.add_to_chat(207, '[rett-auto-updater] Loading all addons from manifest...')
            for addon_name, _ in pairs(manifest.addons or {}) do
                windower.send_command('lua load ' .. addon_name)
            end
            windower.add_to_chat(207, '[rett-auto-updater] All addons loaded.')
        end
    elseif cmd == 'reload' then
        local args = { ... }
        if args[1] == 'all' then
            local manifest = get_manifest()
            if not manifest then return end
            windower.add_to_chat(207, '[rett-auto-updater] Reloading all addons from manifest...')
            for addon_name, _ in pairs(manifest.addons or {}) do
                windower.send_command('lua reload ' .. addon_name)
            end
            windower.add_to_chat(207, '[rett-auto-updater] All addons reloaded.')
        end
    end
end)
