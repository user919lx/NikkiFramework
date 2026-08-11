---@diagnostic disable: duplicate-set-field
-- scripts/tests/resolvers/test_effect_resolver.lua
local TestUtils = require("tests/test_utils")
local EffectResolver = require("resolvers/effect_resolver")
local ModifierAdapter = require("utils/modifier_adapter")
local ResourceAdapter = require("utils/resource_adapter")

return function()
    local suite = TestUtils.CreateSuite("EffectResolver (Deep)")
    local inst = suite:Track(CreateEntity())

    local mods_applied, mods_removed = {}, {}
    local regen_set, regen_removed = nil, nil
    local drain_set, drain_removed = nil, nil
    local old_mod_apply = ModifierAdapter.Apply
    local old_mod_remove = ModifierAdapter.Remove
    local old_set_regen = ResourceAdapter.SetRegen
    local old_set_drain = ResourceAdapter.SetDrain
    local old_remove_regen = ResourceAdapter.RemoveRegen
    local old_remove_drain = ResourceAdapter.RemoveDrain
    ModifierAdapter.Apply = function(i, t, v, id, l) mods_applied[t] = v * l end
    ModifierAdapter.Remove = function(i, t, id) mods_removed[t] = true end
    ResourceAdapter.SetRegen = function(i, res, rate, id) regen_set = rate end
    ResourceAdapter.SetDrain = function(i, res, rate, id) drain_set = rate end
    ResourceAdapter.RemoveRegen = function(i, res, rate, id) regen_removed = rate end
    ResourceAdapter.RemoveDrain = function(i, res, rate, id) drain_removed = rate end

    -- Mock 资源适配器，用于测试 cost.amount 和 drain.rate
    local old_get_cur = ResourceAdapter.GetCurrent
    local old_delta = ResourceAdapter.DoDelta
    local mock_res = 100
    local delta_amount = 0
    ResourceAdapter.GetCurrent = function(inst, res) return mock_res end
    ResourceAdapter.DoDelta = function(inst, res, v)
        delta_amount = delta_amount + v; mock_res = mock_res + v
    end

    local fn_called = false
    local return_false_in_fn = false
    local resolver = EffectResolver({
        ["eff_full"] = {
            tags = { "BURNING" },
            mods = { atk = 2.0 },
            cost = { res = "health", amount = 10 }, -- 启动费
            regen = { res = "health", rate = 4 },   -- 回复费
            drain = { res = "health", rate = 5 },   -- 维持费
            fn = function()
                fn_called = true
                if return_false_in_fn then return false end
            end
        }
    })

    -- A. 测试启动验资 PayActivationCost
    mock_res = 100; delta_amount = 0
    suite:assert(resolver:PayActivationCost(inst, "eff_full") == true, "充足资源时 PayActivationCost 成功放行")
    suite:assert(delta_amount == -10, "启动成功时精准扣除 cost.amount")

    mock_res = 5; delta_amount = 0
    suite:assert(resolver:PayActivationCost(inst, "eff_full") == false, "资源不足以支付启动费时被拦截")

    -- B. 测试层级更新 UpdateEffectLayers (regen / drain 同步更新)
    local context = {}
    resolver:UpdateEffectLayers(inst, "eff_full", 2, context)
    suite:assert(context.regen_rate == 8, "regen rate 会按 layers 正确计算")
    suite:assert(context.drain_rate == 10, "drain rate 会按 layers 正确计算")
    suite:assert(regen_set == 8, "regen 会走 SetRegen")
    suite:assert(drain_set == 10, "drain 会走 SetDrain")

    -- C. 测试持续更新 OnUpdateEffect (资源维持)
    mock_res = 100; delta_amount = 0; fn_called = false
    local keep = resolver:OnUpdateEffect(inst, "eff_full", 1, context, 2) -- layers = 2
    suite:assert(keep == true, "充足资源时 OnUpdateEffect 维持")
    suite:assert(delta_amount == 0, "OnUpdateEffect 只做足额检查，不直接扣资源")
    suite:assert(fn_called == true, "验资通过后业务 fn 被成功执行")

    -- D. 测试持续更新 OnUpdateEffect (资源见底卸载)
    mock_res = 2; delta_amount = 0; fn_called = false
    keep = resolver:OnUpdateEffect(inst, "eff_full", 1, context, 1)
    suite:assert(keep == false, "资源不足以支付 drain 时返回 false 通知卸载")
    suite:assert(delta_amount == 0, "见底时不扣成负数")
    suite:assert(fn_called == false, "见底时不执行后续 fn")

    -- E. 测试持续更新 OnUpdateEffect (fn 主动终止)
    mock_res = 100; return_false_in_fn = true
    keep = resolver:OnUpdateEffect(inst, "eff_full", 1, context, 1)
    suite:assert(keep == false, "fn 内部主动返回 false 时，返回 false 提前终止 Effect")

    -- F. 测试结束清理 OnEffectEnd (regen / drain 同步移除)
    resolver:OnEffectEnd(inst, "eff_full", context)
    suite:assert(regen_removed == 8, "regen 会走 RemoveRegen")
    suite:assert(drain_removed == 10, "drain 会走 RemoveDrain")

    -- 还原环境
    ModifierAdapter.Apply = old_mod_apply
    ModifierAdapter.Remove = old_mod_remove
    ResourceAdapter.SetRegen = old_set_regen
    ResourceAdapter.SetDrain = old_set_drain
    ResourceAdapter.RemoveRegen = old_remove_regen
    ResourceAdapter.RemoveDrain = old_remove_drain
    ResourceAdapter.GetCurrent = old_get_cur
    ResourceAdapter.DoDelta = old_delta

    suite:Cleanup()
end
