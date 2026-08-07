-- scripts/nikki_client_settings.lua
local json = require("json")

local FILE_NAME = "nikki_skill_framework_client_settings"

local NikkiClientSettings = {}
-- 默认设置（以后加新配置只需在这里加一行，下面代码全通用）
local settings = {
    show_range = true,
}

function NikkiClientSettings.Save()
    local success, str = pcall(json.encode, settings)
    if success then
        TheSim:SetPersistentString(FILE_NAME, str, false)
    else
        print("[NikkiClientSettings] Failed to encode JSON.")
    end
end

function NikkiClientSettings.Load()
    TheSim:GetPersistentString(FILE_NAME, function(load_success, str)
        if load_success and type(str) == "string" and str ~= "" then
            local success, data = pcall(json.decode, str)
            if success and type(data) == "table" then
                for k, v in pairs(data) do
                    settings[k] = v
                end
            else
                print("[NikkiClientSettings] Failed to decode JSON.")
            end
        end
    end)
end

-- ========================================================
-- 暴露通用 API (动态 Key 访问)
-- ========================================================
function NikkiClientSettings.Get(key)
    return settings[key]
end

function NikkiClientSettings.Set(key, val)
    settings[key] = val
    NikkiClientSettings.Save() -- 状态改变即刻落盘
end

function NikkiClientSettings.Toggle(key)
    -- 仅对 boolean 类型的配置进行反转
    if type(settings[key]) == "boolean" then
        NikkiClientSettings.Set(key, not settings[key])
    end
    return settings[key]
end

-- 模块在游戏启动 require 时，立刻异步加载磁盘存档
NikkiClientSettings.Load()

return NikkiClientSettings
