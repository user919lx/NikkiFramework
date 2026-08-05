-- scripts/tests/resolvers/test_effect_resolver.lua
local TestUtils = require("tests/test_utils")
local EffectResolver = require("resolvers/effect_resolver")
local ModifierAdapter = require("utils/modifier_adapter")
local ResourceAdapter = require("utils/resource_adapter")

return function()
    local suite = TestUtils.CreateSuite("EffectResolver (Deep)")
    local inst = suite:Track(CreateEntity())
    
    -- A. 拦截全局 Adapter 以测试挂载逻辑[cite: 38]
    local mods_applied, mods_removed = {}, {}
    local regen_added, regen_removed = {}, {}
    
    local old_mod_apply = ModifierAdapter.Apply
    local old_mod_remove = ModifierAdapter.Remove
    ModifierAdapter.Apply = function(i, t, v, id, l) mods_applied[t] = v * l end
    ModifierAdapter.Remove = function(i, t, id) mods_removed[t] = true end

    local old_res_get = ResourceAdapter.GetComponent
    local old_res_add = ResourceAdapter.AddRegen
    local old_res_rem = ResourceAdapter.RemoveRegen
    ResourceAdapter.GetComponent = function(i, res) return true end -- 强制返回有效组件
    ResourceAdapter.AddRegen = function(i, c, res, rate, id) regen_added[res] = rate end
    ResourceAdapter.RemoveRegen = function(i, c, res, id) regen_removed[res] = true end

    -- B. 准备数据
    local apply_called, remove_called, fn_called = false, false, false
    local resolver = EffectResolver({
        ["eff_full"] = {
            tags = { "BURNING" }, mods = { atk = 2.0 }, cost = { res = "health", rate = -5 },
            on_apply = function() apply_called = true end,
            on_remove = function() remove_called = true end,
            fn = function() fn_called = true end
        },
        ["eff_empty"] = {}
    })

    -- C. 测试 Config 默认值补全[cite: 38]
    local dur, max, mode = resolver:GetEffectConfig("eff_empty")
    suite:assert(dur == nil and max == 1 and mode == "refresh", "缺省配置自动补全默认值")
    suite:assert(resolver:HasFn("eff_empty") == false, "HasFn 正确识别无 fn")
    suite:assert(resolver:HasFn("eff_full") == true, "HasFn 正确识别有 fn")

    -- D. 测试 Start 生命周期[cite: 38]
    resolver:OnEffectStart(inst, "eff_full", {})
    suite:assert(inst:HasTag("BURNING"), "OnEffectStart 正确添加 Tag")
    suite:assert(apply_called == true, "OnEffectStart 成功回调 on_apply")

    -- E. 测试 Layers 生命周期 (Mods与Regen)[cite: 38]
    resolver:UpdateEffectLayers(inst, "eff_full", 3)
    suite:assert(mods_applied["atk"] == 6.0, "UpdateEffectLayers 成功向 ModAdapter 分发倍增层数 (2.0 * 3)")
    suite:assert(regen_added["health"] == 15, "UpdateEffectLayers 成功向 ResAdapter 施加反向扣除 (-(-5) * 3)")

    -- F. 测试 Fn 轮询与空安全[cite: 38]
    resolver:ExecuteFn(inst, "eff_empty", 0.033, {})
    suite:assert(fn_called == false, "空 Fn 安全放行")
    resolver:ExecuteFn(inst, "eff_full", 0.033, {})
    suite:assert(fn_called == true, "ExecuteFn 成功执行")

    -- G. 测试 End 生命周期与清场[cite: 38]
    resolver:OnEffectEnd(inst, "eff_full", {})
    suite:assert(not inst:HasTag("BURNING"), "OnEffectEnd 清理 Tag")
    suite:assert(mods_removed["atk"] == true, "OnEffectEnd 清理 Mods")
    suite:assert(regen_removed["health"] == true, "OnEffectEnd 清理 Regen")
    suite:assert(remove_called == true, "OnEffectEnd 成功回调 on_remove")

    -- H. 还原环境
    ModifierAdapter.Apply = old_mod_apply
    ModifierAdapter.Remove = old_mod_remove
    ResourceAdapter.GetComponent = old_res_get
    ResourceAdapter.AddRegen = old_res_add
    ResourceAdapter.RemoveRegen = old_res_rem

    suite:Cleanup()
end