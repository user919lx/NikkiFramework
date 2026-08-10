-- scripts/utils/modifier_adapter.lua
local log = require("utils/log")

local ModifierAdapter = {}

-- 属性修饰策略表，彻底解耦 if/elseif 分支
local MODIFIER_STRATEGIES = {
    -- 攻击倍率增量 (正数为加攻)
    atk = {
        apply = function(inst, val, key)
            if inst.components.combat and inst.components.combat.externaldamagemultipliers then
                inst.components.combat.externaldamagemultipliers:SetModifier(inst, val, key)
            end
        end,
        remove = function(inst, key)
            if inst.components.combat and inst.components.combat.externaldamagemultipliers then
                inst.components.combat.externaldamagemultipliers:RemoveModifier(inst, key)
            end
        end
    },
    -- 承受伤害倍率增量 (正数为易伤，负数为减伤，在防具结算后生效)
    dmg_taken = {
        apply = function(inst, val, key)
            if inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
                inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, val, key)
            end
        end,
        remove = function(inst, key)
            if inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
                inst.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, key)
            end
        end
    },
    -- 移速倍率增量 (正数为加速)
    spd = {
        apply = function(inst, val, key)
            if inst.components.locomotor then
                -- 完美抹平引擎差异：locomotor 的参数顺序与 combat 是反的 (先 src, 后 val)
                inst.components.locomotor:SetExternalSpeedMultiplier(inst, key, val)
            end
        end,
        remove = function(inst, key)
            if inst.components.locomotor then
                inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, key)
            end
        end
    },
    fire_damage_scale = {
        apply = function(inst, val, key)
            if inst.components.health then
                inst.components.health.fire_damage_scale = val
            end
        end,
        remove = function(inst, key)
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

function ModifierAdapter.Apply(inst, mod_type, value, effect_id)
    local strategy = MODIFIER_STRATEGIES[mod_type]
    if strategy then
        log.debug("[ModifierAdapter] Applying modifier '%s' with value %.2f to %s (effect_id: %s)", tostring(mod_type), value, tostring(inst), tostring(effect_id))
        strategy.apply(inst, value, effect_id)
    else
        log.warn("[ModifierAdapter] Unsupported mod_type or missing component: " .. tostring(mod_type))
    end
end

function ModifierAdapter.Remove(inst, mod_type, effect_id)
    local strategy = MODIFIER_STRATEGIES[mod_type]
    if strategy then
        log.debug("[ModifierAdapter] Removing modifier '%s' with effect_id '%s' from %s", tostring(mod_type), tostring(effect_id), tostring(inst))
        strategy.remove(inst, effect_id)
    end
end

return ModifierAdapter