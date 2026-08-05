-- scripts/tests/utils/test_resource_adapter.lua
local TestUtils = require("tests/test_utils")
local ResourceAdapter = require("utils/resource_adapter")

return function()
    local suite = TestUtils.CreateSuite("ResourceAdapter (Deep)")
    local inst = suite:Track(CreateEntity())
    
    -- A. 测试 GetComponent 映射[cite: 39]
    inst:AddComponent("nikki_mana")
    inst:AddComponent("nikki_spark")
    inst:AddComponent("health")
    
    suite:assert(ResourceAdapter.GetComponent(inst, "mana") ~= nil, "成功映射 mana 到 nikki_mana")
    suite:assert(ResourceAdapter.GetComponent(inst, "spark") ~= nil, "成功映射 spark 到 nikki_spark")
    suite:assert(ResourceAdapter.GetComponent(inst, "health") ~= nil, "普通组件名直接返回")

    -- B. 准备 Mock 组件环境[cite: 39]
    local mock_health = { currenthealth = 50, AddRegenSource = function() end, RemoveRegenSource = function() end }
    local mock_sanity = { current = 60, externalmodifiers = { SetModifier = function() end, RemoveModifier = function() end } }
    local mock_custom = { 
        current = 10, 
        GetCurrent = function(self) return 20 end, 
        DoDelta = function(self, val) self.current = self.current + val end,
        SetRegenMod = function() end, RemoveRegenMod = function() end
    }

    -- C. 测试 GetCurrent 全分支[cite: 39]
    suite:assert(ResourceAdapter.GetCurrent(mock_health, "health") == 50, "Health 直读 currenthealth")
    suite:assert(ResourceAdapter.GetCurrent(mock_sanity, "sanity") == 60, "Sanity 直读 current")
    suite:assert(ResourceAdapter.GetCurrent(mock_custom, "custom") == 20, "自定义组件优先调用 GetCurrent() 方法")
    
    -- D. 测试 DoDelta[cite: 39]
    ResourceAdapter.DoDelta(mock_custom, 5)
    suite:assert(mock_custom.current == 15, "成功调用组件自身的 DoDelta")

    -- E. 测试 AddRegen / RemoveRegen (饥荒特化逻辑)[cite: 39]
    -- Mock 饥荒原生 DoPeriodicTask 防止引擎任务泄露
    local task_canceled = false
    inst.DoPeriodicTask = function(self, time, fn)
        return { Cancel = function() task_canceled = true end }
    end

    -- Hunger 走 Task 分支
    ResourceAdapter.AddRegen(inst, mock_sanity, "hunger", 1, "test_buff")
    suite:assert(inst._nikki_hunger_tasks["test_buff"] ~= nil, "饥饿度 Regen 成功创建了 Task 任务")
    
    ResourceAdapter.RemoveRegen(inst, mock_sanity, "hunger", "test_buff")
    suite:assert(task_canceled == true, "饥饿度 Regen 移除时，成功 Cancel 了 Task")
    suite:assert(inst._nikki_hunger_tasks["test_buff"] == nil, "任务表清理干净")

    suite:Cleanup()
end