local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")
log.set_level("debug")

local StateResolver = Class(BaseResolver, function(self, defs)
    BaseResolver._ctor(self, defs or {})
    if defs then
        for state_name, def in pairs(defs) do
            if def.triggers and def.triggers.keys then
                local numeric_keys = {}
                for k, v in pairs(def.triggers.keys) do
                    if type(k) == "string" and _G[k] ~= nil then
                        numeric_keys[_G[k]] = v
                    else
                        numeric_keys[k] = v
                    end
                end
                def.triggers.keys = numeric_keys
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
    return def.badges
end

function StateResolver:GetSkillForKey(state_name, key_code)
    local def = self:GetStateDef(state_name)
    if def and def.triggers and def.triggers.keys then
        return def.triggers.keys[key_code]
    end
    return nil
end

function StateResolver:GetWheelSkills(state_name)
    local def = self:GetStateDef(state_name)
    if def and def.triggers and def.triggers.wheel then
        return def.triggers.wheel
    end
    return {}
end

return StateResolver
