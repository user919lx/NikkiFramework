local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")
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

-- ============================================================
-- 光环辅助函数：根据 selector 筛选目标
-- ============================================================
local function GetAuraTargets(inst, selector, radius, exclude_owner)
    local x, y, z = inst.Transform:GetWorldPosition()

    local must_have = selector and selector.must_have or nil
    local must_have_one_of = selector and selector.must_have_one_of or nil
    local cant_have = selector and selector.cant_have or nil

    local targets = TheSim:FindEntities(x, y, z, radius, must_have, cant_have, must_have_one_of)

    if exclude_owner then
        local filtered = {}
        for _, target in ipairs(targets) do
            if target ~= inst then
                table.insert(filtered, target)
            end
        end
        return filtered
    end

    return targets
end

-- ============================================================
-- 光环辅助函数：表差集（检测进入/离开）
-- 注：table.contains 来自 utils/util.lua
-- ============================================================
local function DetectEnterLeave(prev_targets, current_targets, on_enter, on_leave, owner, def, context)
    if on_leave then
        for _, target in ipairs(prev_targets) do
            if not table.contains(current_targets, target) then
                pcall(on_leave, owner, target, def, context)
            end
        end
    end

    if on_enter then
        for _, target in ipairs(current_targets) do
            if not table.contains(prev_targets, target) then
                pcall(on_enter, owner, target, def, context)
            end
        end
    end
end

-- ============================================================
-- 光环核心：执行单次脉冲
-- ============================================================
local function PerformAuraPulse(inst, def, context)
    local aura = def.aura
    local radius = aura.radius or 8
    local exclude_owner = aura.exclude_owner or false

    local current_targets = GetAuraTargets(inst, aura.selector, radius, exclude_owner)
    local prev_targets = context._aura_prev_targets or {}

    DetectEnterLeave(prev_targets, current_targets,
        aura.on_enter,
        aura.on_leave,
        inst, def, context
    )

    context.target_count = #current_targets

    if type(aura.on_pulse) == "function" then
        for _, target in ipairs(current_targets) do
            pcall(aura.on_pulse, inst, target, def, context)
        end
    end

    context._aura_prev_targets = current_targets
end

-- ============================================================
-- 光环特效：创建并挂载
-- ============================================================
local function SpawnAuraFx(inst, def, context)
    local aura = def.aura
    local fx = SpawnPrefab("nikki_aura_fx")
    if not fx then return end
    fx:Attach(inst)
    fx:SetRange(aura.radius)
    fx:SetPulseInterval(aura.pulse_interval)
    if type(aura.shader) == "string" then
        fx:SetShader(aura.shader)
    end
    context._aura_fx = fx
    return fx
end


local EffectResolver = Class(BaseResolver, function(self, defs)
    BaseResolver._ctor(self, defs)
end)

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

function EffectResolver:OnEffectStart(inst, id, context)
    local def = self:GetDef(id)
    if not def then return end
    if def.tags then for _, tag in ipairs(def.tags) do inst:AddTag(tag) end end
    if def.on_apply then pcall(def.on_apply, inst, def, context) end

    if def.aura and def.aura.shader ~= false then
        SpawnAuraFx(inst, def, context)
    end
end


function EffectResolver:OnEffectEnd(inst, id, context)
    local def = self:GetDef(id)
    if not def then return end

    -- 清理特效
    if context._aura_fx and context._aura_fx:IsValid() then
        context._aura_fx:Remove()
        context._aura_fx = nil
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
        for mod_type, value in pairs(def.mods) do
            ModifierAdapter.Apply(inst, mod_type, value, id)
        end
    end
    ApplyResourceRate(inst, id, def, context, layers, "regen")
    ApplyResourceRate(inst, id, def, context, layers, "drain")

    if def.aura then
        context._aura_timer = 0
        PerformAuraPulse(inst, def, context)
    end

    if type(def.on_layer_update) == "function" then
        pcall(def.on_layer_update, inst, layers, def, context)
    end
end

-- ========================================================
-- 验资扣除 Effect 的单次激活手续费 (cost.amount)
-- ========================================================
function EffectResolver:PayActivationCost(inst, id)
    local def = self:GetDef(id)
    if not def or not def.cost or not def.cost.res or not def.cost.amount or def.cost.amount <= 0 then
        return true
    end

    local current = ResourceAdapter.GetCurrent(inst, def.cost.res)
    if current < def.cost.amount then
        log.debug("[EffectResolver] Activation failed: %s lacks %s for effect '%s'", tostring(inst), def.cost.res, id)
        return false
    end

    ResourceAdapter.DoDelta(inst, def.cost.res, -def.cost.amount)
    return true
end

-- ========================================================
-- 每帧更新：drain 检查 -> aura 脉冲 -> fn 执行
-- ========================================================
function EffectResolver:OnUpdateEffect(inst, id, dt, context, layers)
    local def = self:GetDef(id)
    if not def then return false end

    -- ========================================================
    -- 阶段 1：drain 资源耗尽检查
    -- ========================================================
    if def.drain and def.drain.res and context and context.drain_rate and context.drain_rate > 0 then
        local current = ResourceAdapter.GetCurrent(inst, def.drain.res)
        if current <= 0.01 then
            local on_deplete = def.drain.on_deplete or "remove"
            if on_deplete == "remove" then
                log.debug("[EffectResolver] Effect '%s' on %s auto-removed due to insufficient %s (current: %.2f)", id,
                    tostring(inst), def.drain.res, current)
                return false
            end
            context.is_depleted = true
        else
            context.is_depleted = false
        end
    end

    -- ========================================================
    -- 阶段 2：Aura 光环脉冲处理
    -- ========================================================
    if def.aura then
        local interval = def.aura.pulse_interval or 1.0

        context._aura_timer = (context._aura_timer or 0) + dt

        if context._aura_timer >= interval then
            context._aura_timer = 0
            PerformAuraPulse(inst, def, context)
        end

        return true
    end

    -- ========================================================
    -- 阶段 3：fn 自定义逻辑（仅当无 aura 时执行）
    -- ========================================================
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
