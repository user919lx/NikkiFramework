local TestUtils = require("tests/test_utils")
local ModifierAdapter = require("utils/modifier_adapter")

return function()
    local suite = TestUtils.CreateSuite("ModifierAdapter (Deep)")
    local inst = suite:Track(CreateEntity())

    -- A. 注入伪造的饥荒底层组件
    local atk_mod, def_mod, spd_mod = 0, 0, 1
    inst:AddComponent("combat")
    inst.components.combat.externaldamagemultipliers = {
        SetModifier = function(self, owner, val, src) atk_mod = val end,
        RemoveModifier = function(self, owner, src) atk_mod = 0 end
    }
    inst.components.combat.externaldamagetakenmultipliers = {
        SetModifier = function(self, owner, val, src) def_mod = val end,
        RemoveModifier = function(self, owner, src) def_mod = 0 end
    }

    inst:AddComponent("locomotor")
    inst.components.locomotor.SetExternalSpeedMultiplier = function(self, owner, src, val) spd_mod = val end
    inst.components.locomotor.RemoveExternalSpeedMultiplier = function(self, owner, src) spd_mod = 1 end

    -- B. 测试 Apply 叠加计算 (绝对倍率公式: 1 + value * layers)
    ModifierAdapter.Apply(inst, "atk", 0.5, "test_src", 2)
    suite:assert(atk_mod == 2.0, "Atk 修饰器层数叠加正确 (1 + 0.5 * 2 = 2.0)")

    -- 修复点：键名改为 "dmg_taken"，期望结果为 1 + (-0.25 * 3) = 0.25
    ModifierAdapter.Apply(inst, "dmg_taken", -0.25, "test_src", 3)
    suite:assert(def_mod == 0.25, "DmgTaken 修饰器层数叠加正确 (1 - 0.25 * 3 = 0.25)")

    ModifierAdapter.Apply(inst, "spd", 0.2, "test_src", 1)
    suite:assert(spd_mod == 1.2, "Spd 修饰器基础值转换正确 (1 + 0.2 = 1.2)")

    -- C. 测试不支持的类型拦截
    local success = pcall(function() ModifierAdapter.Apply(inst, "unknown", 1, "src") end)
    suite:assert(success == true, "未知的 mod_type 应当安全输出 warning，而不导致崩溃")

    -- D. 测试 Remove 清理
    ModifierAdapter.Remove(inst, "dmg_taken", "test_src")
    suite:assert(def_mod == 0, "DmgTaken 修饰器被成功移除")

    suite:Cleanup()
end
