-- rett-auto-updater.lua
-- Windower addon: Automatically updates specified addons based on a remote manifest
-- Author: Rettgp

_addon.name = 'rett-auto-updater'
_addon.version = '1.0.0'
_addon.author = 'Rettgp'
_addon.commands = {'rettautoupdater', 'rettau'}

local json = require('json')
local http = require('socket.http')
local ltn12 = require('ltn12')
local files = require('files')

local MANIFEST_URL = 'https://raw.githubusercontent.com/Rettgp/ffxi-addons/main/manifest.json'
local ADDONS_BASE_URL = 'https://github.com/Rettgp/ffxi-addons/archive/refs/heads/main.zip' -- Example: for zip download

local function download_file(url, output_path)
    local file = io.open(output_path, 'wb')
    if not file then return false, 'Cannot open file for writing: ' .. output_path end
    local _, code, headers, status = http.request{
        url = url,
        sink = ltn12.sink.file(file)
    }
    if code ~= 200 then
        return false, 'HTTP error: ' .. tostring(code)
    end
    return true
end

local function get_local_version(addon_name)
    local version_file = windower.addon_path .. '../' .. addon_name .. '/version.lua'
    local f = io.open(version_file, 'r')
    if not f then return nil end
    local content = f:read('*a')
    f:close()
    local version = content:match("version%s*=%s*['\"]([%d%.]+)['\"]")
    return version
end

local function update_addon(addon_name, download_url)
    -- TODO: Download and extract the addon, replace local folder
   notice(207, ('[rett-auto-updater] Would update %s from %s'):format(addon_name, download_url))
end

windower.register_event('load', function()
    windower.add_to_chat(207, '[rett-auto-updater] Checking for addon updates...')
    local manifest_data = {}
    local response = {}
    local _, code = http.request{
        url = MANIFEST_URL,
        sink = ltn12.sink.table(response)
    }
    if code ~= 200 then
        error(123, '[rett-auto-updater] Failed to fetch manifest: HTTP ' .. tostring(code))
        return
    end
    local manifest_json = table.concat(response)
    local success, manifest = pcall(json.decode, manifest_json)
    if not success or not manifest then
        error(123, '[rett-auto-updater] Failed to parse manifest.json')
        return
    end
    for addon_name, remote_info in pairs(manifest.addons or {}) do
        local local_version = get_local_version(addon_name)
        if local_version and local_version ~= remote_info.version then
            windower.add_to_chat(207, ('[rett-auto-updater] %s is outdated (local: %s, remote: %s)'):format(addon_name, local_version, remote_info.version))
            update_addon(addon_name, remote_info.download_url or ADDONS_BASE_URL)
        end
    end
    notice(207, '[rett-auto-updater] Update check complete.')
end)

-- Command: Manual update check
windower.register_event('addon command', function(cmd)
    if cmd == 'check' then
        windower.send_command('lua reload rett-auto-updater')
    end
end)
