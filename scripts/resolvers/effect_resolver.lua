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
    if def.on_remove then pcall(def.on_remove, inst, def, context) end
end

function EffectResolver:UpdateEffectLayers(inst, id, layers)
    local def = self:GetDef(id)
    if not def then return end
    if def.mods then
        for mod_type, value in pairs(def.mods) do ModifierAdapter.Apply(inst, mod_type, value, id, layers) end
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

    local res = def.drain and def.drain.res
    local rate = def.drain and def.drain.rate or 0
    local drain_amount = rate * dt * (layers or 1)

    -- 1. 验资阶段 (仅 rate > 0 时预检，不足则直接终止退出)
    if res and drain_amount > 0 then
        local current = ResourceAdapter.GetCurrent(inst, res)
        if current < drain_amount then
            log.debug("[EffectResolver] Resource depleted (%s), auto-removing effect '%s'", res, id)
            return false
        end
    end

    -- 2. 执行阶段 (仅在显式返回 boolean false 时终止退出)
    if def.fn then
        local ok, result = pcall(def.fn, inst, dt, def, context)
        if not ok then
            log.error("[EffectResolver] Error in effect function for '%s': %s", id, tostring(result))
        elseif result == false then
            log.debug("[EffectResolver] Effect function for '%s' returned false, auto-removing effect", id)
            return false
        end
    end

    -- 3. 结算扣费阶段 (两关都过了，执行实扣/回复)
    if drain_amount ~= 0 and res then
        ResourceAdapter.DoDelta(inst, res, -drain_amount)
    end

    return true
end

return EffectResolver
