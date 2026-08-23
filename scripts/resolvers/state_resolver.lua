-- scripts/resolvers/state_resolver.lua
local BaseResolver = require("resolvers/base_resolver")

local StateResolver = Class(BaseResolver, function(self, defs)
    self._resolver_type = "state"
    BaseResolver._ctor(self, defs)
end)

function StateResolver:OnDefAdded(state, def)
    if def.keys then
        local bindings = {}
        for k, v in pairs(def.keys) do
            local key_code = k
            if type(k) == "string" and rawget(_G, k) ~= nil then
                key_code = rawget(_G, k)
            end
            bindings[key_code] = v
        end
        def.keys = bindings
    end
end

function StateResolver:GetBadges(state)
    local def = self:GetDef(state)
    return def and def.badges or nil
end

function StateResolver:GetSkills(state)
    local def = self:GetDef(state)
    return def and def.skills or {}
end


return StateResolver