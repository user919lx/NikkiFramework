-- scripts/resolvers/state_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")

local StateResolver = Class(BaseResolver, function(self, defs)
    BaseResolver._ctor(self, defs or {})
    if defs then
        for state_name, def in pairs(defs) do
            -- 核心修改：由于我们引入了预编译，按键的转换应该作用于 compiled_triggers
            if def.compiled_triggers and def.compiled_triggers.keys then
                local numeric_keys = {}
                for k, v in pairs(def.compiled_triggers.keys) do
                    -- 【核心修复】：使用 rawget 绕过饥荒的 strict.lua 拦截！
                    local global_env = _G
                    if type(k) == "string" and rawget(global_env, k) ~= nil then
                        numeric_keys[rawget(global_env, k)] = v
                    else
                        numeric_keys[k] = v
                    end
                end
                def.compiled_triggers.keys = numeric_keys
            end
        end
    end
end)

function StateResolver:GetStateDef(state_name)
    return self:GetDef(state_name) or {}
end

function StateResolver:GetAllStates()
    return self:GetAllDefs()
end

function StateResolver:GetStateBadges(state)
    local def = self:GetStateDef(state)
    return def and def.badges or nil
end

-- 封装：直接返回该形态下绑定在某按键上的所有技能列表
function StateResolver:GetSkillsForKey(state_name, key_code)
    local def = self:GetStateDef(state_name)
    if def and def.compiled_triggers and def.compiled_triggers.keys then
        return def.compiled_triggers.keys[key_code]
    end
    return nil
end

function StateResolver:GetWheelSkills(state_name)
    local def = self:GetStateDef(state_name)
    return def and def.wheel or {}
end

return StateResolver