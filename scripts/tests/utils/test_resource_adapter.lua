-- scripts/tests/utils/test_resource_adapter.lua
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

    -- B. 准备 Mock 组件环境 (使用原生组件的属性，不直接覆盖对象表)
    inst.components.health.currenthealth = 50
    inst.components.sanity = { current = 60, externalmodifiers = { SetModifier = function() end, RemoveModifier = function() end } }
    inst.components.hunger = { current = 100, DoDelta = function() end }

    -- 规范的自定义组件
    inst.components.custom_res = {
        current = 10,
        GetCurrent = function(self) return 20 end,
        DoDelta = function(self, val) self.current = self.current + val end,
        SetRegenMod = function() end,
        RemoveRegenMod = function() end
    }

    -- 不规范的自定义组件
    inst.components.weird_res = {
        current = 10,
        FetchValue = function(self) return 30 end,
        ChangeValue = function(self, val) self.current = self.current + val end
    }

    -- 【关键修复】：安全扩充 inst.replica 字段，绝对不整体重置 inst.replica
    inst.replica.custom_res = {
        GetPercent = function() return 0.5 end,
        GetMax = function() return 200 end,
        GetRateScale = function() return 1 end
    }
    inst.replica.weird_res = {
        FetchPct = function() return 0.9 end,
        FetchMax = function() return 500 end,
        FetchRate = function() return 3 end
    }

    -- C. 执行 Adapter 注册
    ResourceAdapter.RegisterStrategy("custom", { component = { name = "custom_res" } })
    ResourceAdapter.RegisterStrategy("weird", {
        component = {
            name = "weird_res",
            get_current = "FetchValue",
            do_delta = "ChangeValue"
        },
        replica = {
            get_percent = "FetchPct",
            get_max = "FetchMax",
            get_rate_scale = "FetchRate"
        }
    })

    -- D. 测试 Server 端核心逻辑 (GetCurrent / DoDelta)
    suite:assert(ResourceAdapter.GetCurrent(inst, "health") == 50, "Health 直读 currenthealth")
    suite:assert(ResourceAdapter.GetCurrent(inst, "sanity") == 60, "Sanity 直读 current")

    suite:assert(ResourceAdapter.GetCurrent(inst, "custom") == 20, "规范组件使用默认 GetCurrent 成功")
    suite:assert(ResourceAdapter.GetCurrent(inst, "weird") == 30, "不规范组件成功重定向至 FetchValue")

    ResourceAdapter.DoDelta(inst, "custom", 5)
    suite:assert(inst.components.custom_res.current == 15, "规范组件成功调用默认 DoDelta")

    ResourceAdapter.DoDelta(inst, "weird", 5)
    suite:assert(inst.components.weird_res.current == 15, "不规范组件成功重定向至 ChangeValue")

    -- E. 测试 Client/UI 端数据通道 (GetUIValue)
    suite:assert(ResourceAdapter.GetUIValue(inst, "custom", "percent") == 0.5, "UI 取值: 默认 GetPercent 成功")
    suite:assert(ResourceAdapter.GetUIValue(inst, "custom", "max") == 200, "UI 取值: 默认 GetMax 成功")
    suite:assert(ResourceAdapter.GetUIValue(inst, "custom", "rate_scale") == 1, "UI 取值: 默认 GetRateScale 成功")

    suite:assert(ResourceAdapter.GetUIValue(inst, "weird", "percent") == 0.9, "UI 取值: 重定向 FetchPct 成功")
    suite:assert(ResourceAdapter.GetUIValue(inst, "weird", "max") == 500, "UI 取值: 重定向 FetchMax 成功")
    suite:assert(ResourceAdapter.GetUIValue(inst, "weird", "rate_scale") == 3, "UI 取值: 重定向 FetchRate 成功")

    -- F. 测试 SetRegen / RemoveRegen
    local task_canceled = false
    inst._nikki_hunger_tasks = {}
    inst.DoPeriodicTask = function(self, time, fn)
        return { Cancel = function() task_canceled = true end }
    end

    ResourceAdapter.SetRegen(inst, "hunger", 1, "test_buff")
    suite:assert(inst._nikki_hunger_tasks["test_buff"] ~= nil, "饥额度 Regen 成功创建了 Task 任务")

    ResourceAdapter.RemoveRegen(inst, "hunger", "test_buff")
    suite:assert(task_canceled == true, "饥额度 Regen 移除时，成功 Cancel 了 Task")
    suite:assert(inst._nikki_hunger_tasks["test_buff"] == nil, "任务表清理干净")

    suite:Cleanup()
end
