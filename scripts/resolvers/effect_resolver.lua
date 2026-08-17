-- scripts/resolvers/effect_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")

local EffectResolver = Class(BaseResolver, function(self, defs)
    self._resolver_type = "effect"
    BaseResolver._ctor(self, defs)
end)

-- ============================================================
-- 纯查询接口
-- ============================================================

function EffectResolver:GetEffectConfig(id)
    local def = self:GetDef(id)
    if not def then return nil, 1, "refresh", false end
    local max = def.stack and def.stack.max or 1
    local mode = def.stack and def.stack.mode or "refresh"
    return def.duration, max, mode, def.bind_to_state
end

function EffectResolver:HasFn(id)
    local def = self:GetDef(id)
    return def and type(def.fn) == "function"
end

-- GetDef 继承自 BaseResolver
-- GetDisplayName 继承自 BaseResolver
-- GetAllIds 继承自 BaseResolver

return EffectResolver
