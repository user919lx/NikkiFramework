-- scripts/utils/modifier_adapter.lua
local log = require("utils/log")

local ModifierAdapter = {}

-- 提取共有的倍率增量计算逻辑 (用于官方原生的乘数型属性)
local function CalcMultiplier(value, layers)
    local total_offset = value * (layers or 1)
    return 1 + total_offset
end

-- 属性修饰策略表，彻底解耦 if/elseif 分支
local MODIFIER_STRATEGIES = {
    -- 攻击倍率增量 (正数为加攻)
    atk = {
        apply = function(inst, val, effect_id, layers)
            local final_multiplier = CalcMultiplier(val, layers)
            if inst.components.combat and inst.components.combat.externaldamagemultipliers then
                inst.components.combat.externaldamagemultipliers:SetModifier(inst, final_multiplier, effect_id)
            end
        end,
        remove = function(inst, effect_id)
            if inst.components.combat and inst.components.combat.externaldamagemultipliers then
                inst.components.combat.externaldamagemultipliers:RemoveModifier(inst, effect_id)
            end
        end
    },
    -- 承受伤害倍率增量 (正数为易伤，负数为减伤，在防具结算后生效)
    dmg_taken = {
        apply = function(inst, val, effect_id, layers)
            local final_multiplier = CalcMultiplier(val, layers)
            if inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
                inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, final_multiplier, effect_id)
            end
        end,
        remove = function(inst, effect_id)
            if inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
                inst.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, effect_id)
            end
        end
    },
    -- 移速倍率增量 (正数为加速)
    spd = {
        apply = function(inst, val, effect_id, layers)
            local final_multiplier = CalcMultiplier(val, layers)
            if inst.components.locomotor then
                -- 完美抹平引擎差异：locomotor 的参数顺序与 combat 是反的 (先 src, 后 val)
                inst.components.locomotor:SetExternalSpeedMultiplier(inst, effect_id, final_multiplier)
            end
        end,
        remove = function(inst, effect_id)
            if inst.components.locomotor then
                inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, effect_id)
            end
        end
    },
    fire_damage_scale = {
        apply = function(inst, val, effect_id, layers)
            if inst.components.health then
                inst.components.health.fire_damage_scale = val
            end
        end,
        remove = function(inst, effect_id)
            if inst.components.health then
                inst.components.health.fire_damage_scale = 1
            end
        end
    },
}

-- 对外开放的注册接口，允许配置字典注入新的属性算法
function ModifierAdapter.RegisterStrategy(mod_type, strategy)
    if not strategy or type(strategy.apply) ~= "function" or type(strategy.remove) ~= "function" then
        log.warn("[ModifierAdapter] Cannot register strategy for '%s': missing apply or remove function", tostring(mod_type))
        return
    end
    MODIFIER_STRATEGIES[mod_type] = strategy
    log.debug("[ModifierAdapter] Registered custom modifier strategy: %s", tostring(mod_type))
end

function ModifierAdapter.Apply(inst, mod_type, value, effect_id, layers)
    local strategy = MODIFIER_STRATEGIES[mod_type]
    if strategy then
        -- 核心改动：不再越俎代庖进行数学计算，直接下放给策略自身
        strategy.apply(inst, value, effect_id, layers)
    else
        log.warn("[ModifierAdapter] Unsupported mod_type or missing component: " .. tostring(mod_type))
    end
end

function ModifierAdapter.Remove(inst, mod_type, effect_id)
    local strategy = MODIFIER_STRATEGIES[mod_type]
    if strategy then
        strategy.remove(inst, effect_id)
    end
end

return ModifierAdapter