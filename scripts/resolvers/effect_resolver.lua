-- scripts/resolvers/effect_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")

-- 【1. 引入独立的适配器】
local ResourceAdapter = require("utils/resource_adapter")
local ModifierAdapter = require("utils/modifier_adapter")

local EffectResolver = Class(BaseResolver, function(self, defs)
    BaseResolver._ctor(self, defs)
end)

function EffectResolver:GetEffectConfig(id)
    local def = self:GetDef(id)
    if not def then return nil, 1, "refresh" end
    local max = def.stack and def.stack.max or 1
    local mode = def.stack and def.stack.mode or "refresh"
    return def.duration, max, mode
end

function EffectResolver:HasFn(id)
    local def = self:GetDef(id)
    return def and type(def.fn) == "function"
end

function EffectResolver:OnEffectStart(inst, id, context)
    local def = self:GetDef(id)
    if not def then return end
    if def.tags then for _, tag in ipairs(def.tags) do inst:AddTag(tag) end end
    if def.on_apply then pcall(def.on_apply, inst, def, context) end
end

function EffectResolver:OnEffectEnd(inst, id, context)
    local def = self:GetDef(id)
    if not def then return end
    if def.tags then for _, tag in ipairs(def.tags) do inst:RemoveTag(tag) end end
    if def.mods then for mod_type, _ in pairs(def.mods) do ModifierAdapter.Remove(inst, mod_type, id) end end
    if def.cost and def.cost.res then
        ResourceAdapter.RemoveRegen(inst, def.cost.res, "effect_" .. id)
    end
    if def.on_remove then pcall(def.on_remove, inst, def, context) end
end

function EffectResolver:UpdateEffectLayers(inst, id, layers)
    local def = self:GetDef(id)
    if not def then return end
    if def.mods then
        for mod_type, value in pairs(def.mods) do ModifierAdapter.Apply(inst, mod_type, value, id, layers) end
    end
    if def.cost and def.cost.res and def.cost.rate then
        ResourceAdapter.AddRegen(inst, def.cost.res, -def.cost.rate * layers, "effect_" .. id)
    end
end

function EffectResolver:ExecuteFn(inst, id, dt, context)
    local def = self:GetDef(id)
    if def and def.fn then pcall(def.fn, inst, dt, def, context) end
end

return EffectResolver
