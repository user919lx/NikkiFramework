local TestUtils = require("tests/test_utils")
local ResourceAdapter = require("utils/resource_adapter")

return function()
    local suite = TestUtils.CreateSuite("ResourceAdapter (Deep)")
    local inst = suite:Track(CreateEntity())

    -- A. 测试 GetComponent 映射
    inst:AddComponent("nikki_mana")
    inst:AddComponent("nikki_spark")
    inst:AddComponent("health")

    suite:assert(ResourceAdapter.GetComponent(inst, "mana") ~= nil, "成功映射 mana 到 nikki_mana")
    suite:assert(ResourceAdapter.GetComponent(inst, "spark") ~= nil, "成功映射 spark 到 nikki_spark")
    suite:assert(ResourceAdapter.GetComponent(inst, "health") ~= nil, "普通组件名直接返回")

    -- B. 准备 Mock 组件环境 (补全 hunger Mock)
    inst.components.health = { currenthealth = 50, AddRegenSource = function() end, RemoveRegenSource = function() end }
    inst.components.sanity = { current = 60, externalmodifiers = { SetModifier = function() end, RemoveModifier = function() end } }
    inst.components.hunger = { current = 100, DoDelta = function() end } -- 修复点：添加 hunger 组件
    inst.components.custom_res = {
        current = 10,
        GetCurrent = function(self) return 20 end,
        DoDelta = function(self, val) self.current = self.current + val end,
        SetRegenMod = function() end,
        RemoveRegenMod = function() end
    }

    ResourceAdapter.RegisterStrategy("custom", { name = "custom_res" })

    -- C. 测试 GetCurrent 全分支
    suite:assert(ResourceAdapter.GetCurrent(inst, "health") == 50, "Health 直读 currenthealth")
    suite:assert(ResourceAdapter.GetCurrent(inst, "sanity") == 60, "Sanity 直读 current")
    suite:assert(ResourceAdapter.GetCurrent(inst, "custom") == 20, "自定义组件优先调用 GetCurrent() 方法")

    -- D. 测试 DoDelta
    ResourceAdapter.DoDelta(inst, "custom", 5)
    suite:assert(inst.components.custom_res.current == 15, "成功调用组件自身的 DoDelta")

    -- E. 测试 AddRegen / RemoveRegen (饥荒特化逻辑)
    local task_canceled = false
    inst._nikki_hunger_tasks = {}
    inst.DoPeriodicTask = function(self, time, fn)
        return { Cancel = function() task_canceled = true end }
    end

    ResourceAdapter.AddRegen(inst, "hunger", 1, "test_buff")
    suite:assert(inst._nikki_hunger_tasks["test_buff"] ~= nil, "饥额度 Regen 成功创建了 Task 任务")

    ResourceAdapter.RemoveRegen(inst, "hunger", "test_buff")
    suite:assert(task_canceled == true, "饥饿度 Regen 移除时，成功 Cancel 了 Task")
    suite:assert(inst._nikki_hunger_tasks["test_buff"] == nil, "任务表清理干净")

    suite:Cleanup()
end
