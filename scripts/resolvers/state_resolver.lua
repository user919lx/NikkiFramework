-- scripts/resolvers/state_resolver.lua
local BaseResolver = require("resolvers/base_resolver")

local StateResolver = Class(BaseResolver, function(self, defs)
    self._resolver_type = "state"
    BaseResolver._ctor(self, defs)

    -- 新增：存储 basic 和 default 状态名
    self._basic_state = nil
    self._default_state = nil
end)

function StateResolver:OnDefAdded(state_name, def)
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

function StateResolver:GetStateDef(state_name)
    return self:GetDef(state_name) or {}
end

function StateResolver:GetAllStates()
    return self:GetAllDefs()
end

function StateResolver:GetBadges(state)
    local def = self:GetStateDef(state)
    return def and def.badges or nil
end

function StateResolver:GetSkills(state_name)
    local def = self:GetStateDef(state_name)
    return def and def.skills or {}
end

-- ============================================================
-- 新增：basic / default 状态管理
-- ============================================================
function StateResolver:SetBasicState(state_name)
    self._basic_state = state_name
end

function StateResolver:GetBasicState()
    return self._basic_state or "basic"
end

function StateResolver:SetDefaultState(state_name)
    self._default_state = state_name
end

function StateResolver:GetDefaultState()
    return self._default_state or "default"
end

return StateResolver
