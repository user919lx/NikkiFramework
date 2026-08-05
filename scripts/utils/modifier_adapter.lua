-- scripts/utils/modifier_adapter.lua
local log = require("utils/log")

local ModifierAdapter = {}

-- 属性修饰策略表，彻底解耦 if/elseif 分支
local MODIFIER_STRATEGIES = {
    -- 攻击倍率增量 (正数为加攻)
    atk = {
        apply = function(inst, val, src)
            if inst.components.combat and inst.components.combat.externaldamagemultipliers then
                inst.components.combat.externaldamagemultipliers:SetModifier(inst, val, src)
            end
        end,
        remove = function(inst, src)
            if inst.components.combat and inst.components.combat.externaldamagemultipliers then
                inst.components.combat.externaldamagemultipliers:RemoveModifier(inst, src)
            end
        end
    },
    -- 承受伤害倍率增量 (正数为易伤，负数为减伤，在防具结算后生效)
    dmg_taken = {
        apply = function(inst, val, src)
            if inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
                inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, val, src)
            end
        end,
        remove = function(inst, src)
            if inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
                inst.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, src)
            end
        end
    },
    -- 移速倍率增量 (正数为加速)
    spd = {
        apply = function(inst, val, src)
            if inst.components.locomotor then
                -- 完美抹平引擎差异：locomotor 的参数顺序与 combat 是反的 (先 src, 后 val)
                inst.components.locomotor:SetExternalSpeedMultiplier(inst, src, val)
            end
        end,
        remove = function(inst, src)
            if inst.components.locomotor then
                inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, src)
            end
        end
    }
}

function ModifierAdapter.Apply(inst, mod_type, value, source_id, layers)
    -- 计算基于层数的总增量，并转换为饥荒底层的绝对倍率 (如 0.2 -> 1.2)
    local total_offset = value * (layers or 1)
    local final_multiplier = 1 + total_offset

    local strategy = MODIFIER_STRATEGIES[mod_type]
    if strategy then
        strategy.apply(inst, final_multiplier, source_id)
    else
        log.warn("[ModifierAdapter] Unsupported mod_type or missing component: " .. tostring(mod_type))
    end
end

function ModifierAdapter.Remove(inst, mod_type, source_id)
    local strategy = MODIFIER_STRATEGIES[mod_type]
    if strategy then
        strategy.remove(inst, source_id)
    end
end

return ModifierAdapter
