-- scripts/resolvers/effect_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")

-- 【1. 引入独立的适配器】
local ResourceAdapter = require("utils/resource_adapter")
local ModifierAdapter = require("utils/modifier_adapter")

local function GetResourceRate(inst, id, def, context, layers, source, kind)
    local rate = source.rate or 0
    if type(rate) == "function" then
        local ok, result = pcall(rate, inst, def, context)
        if not ok then
            log.error("[EffectResolver] Error in %s rate func for '%s': %s", kind, id, tostring(result))
            return 0
        end
        return result or 0
    end

    return rate * layers
end

local function ApplyResourceRate(inst, id, def, context, layers, kind)
    local source = def[kind]
    if not source then return end

    local rate = GetResourceRate(inst, id, def, context, layers, source, kind)
    if context then
        context[kind .. "_rate"] = rate
    end
    log.debug("[EffectResolver] Updated %s rate for effect '%s' on %s: %s", kind, id, tostring(inst), tostring(rate))

    if kind == "regen" then
        ResourceAdapter.SetRegen(inst, source.res, rate, id)
    else
        ResourceAdapter.SetDrain(inst, source.res, rate, id)
    end
end

local function RemoveResourceRate(inst, id, def, context, kind)
    local source = def[kind]
    if not source then return end

    local rate = context and context[kind .. "_rate"] or 0
    if kind == "regen" then
        ResourceAdapter.RemoveRegen(inst, source.res, rate, id)
    else
        ResourceAdapter.RemoveDrain(inst, source.res, rate, id)
    end

    log.debug("[EffectResolver] %s removed for effect '%s' on %s (rate: %.2f)", kind == "regen" and "Regen" or "Drain",
        tostring(id), tostring(inst), rate)
end

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
    if not def then
        return
    end
    if def.tags then
        for _, tag in ipairs(def.tags) do inst:RemoveTag(tag) end
    end
    if def.mods then
        for mod_type, _ in pairs(def.mods) do ModifierAdapter.Remove(inst, mod_type, id) end
    end
    RemoveResourceRate(inst, id, def, context, "regen")
    RemoveResourceRate(inst, id, def, context, "drain")
    if def.on_remove then
        pcall(def.on_remove, inst, def, context)
    end
end

function EffectResolver:UpdateEffectLayers(inst, id, layers, context)
    local def = self:GetDef(id)
    if not def then return end
    if def.mods then
        for mod_type, value in pairs(def.mods) do ModifierAdapter.Apply(inst, mod_type, value, id, layers) end
    end
    ApplyResourceRate(inst, id, def, context, layers, "regen")
    ApplyResourceRate(inst, id, def, context, layers, "drain")

    if type(def.on_layer_update) == "function" then
        pcall(def.on_layer_update, inst, layers, def, context)
    end
end

-- ========================================================
-- 新增：验资扣除 Effect 的单次激活手续费 (cost.amount)
-- ========================================================
function EffectResolver:PayActivationCost(inst, id)
    local def = self:GetDef(id)
    if not def or not def.cost or not def.cost.res or not def.cost.amount or def.cost.amount <= 0 then
        return true -- 无激活消耗，直接通过
    end

    local current = ResourceAdapter.GetCurrent(inst, def.cost.res)
    if current < def.cost.amount then
        log.debug("[EffectResolver] Activation failed: %s lacks %s for effect '%s'", tostring(inst), def.cost.res, id)
        return false -- 资源不足，拒绝开启
    end

    -- 成功扣除激活费
    ResourceAdapter.DoDelta(inst, def.cost.res, -def.cost.amount)
    return true
end

-- ========================================================
-- 每帧更新：验资(退出) -> 执行fn(退出) -> 结算扣费 -> return true
-- ========================================================
function EffectResolver:OnUpdateEffect(inst, id, dt, context, layers)
    local def = self:GetDef(id)
    if not def then return false end

    -- 验资阶段 (仅针对消耗型 Effect：如果余额枯竭，自我卸载)
    if def.drain and def.drain.res and context and context.drain_rate and context.drain_rate > 0 then
        local current = ResourceAdapter.GetCurrent(inst, def.drain.res)
        if current <= 0.01 then
            log.debug("[EffectResolver] Effect '%s' on %s auto-removed due to insufficient %s (current: %.2f)", id, tostring(inst), def.drain.res, current)
            return false
        end
    end

    -- 执行阶段 (仅在显式返回 boolean false 时终止退出)
    if def.fn then
        local ok, result = pcall(def.fn, inst, dt, def, context)
        if not ok then
            log.error("[EffectResolver] Error in effect function for '%s': %s", id, tostring(result))
        elseif result == false then
            log.debug("[EffectResolver] Effect function for '%s' returned false, auto-removing effect", id)
            return false
        end
    end

    return true
end

return EffectResolver
