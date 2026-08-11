-- scripts/tests/components/test_nikki_effect.lua
local TestUtils = require("tests/test_utils")

return function()
    local suite = TestUtils.CreateSuite("NikkiEffect Component (Deep)")
    local inst = suite:Track(CreateEntity())
    inst:AddComponent("nikki_effect")
    local cmp = inst.components.nikki_effect

    -- A. 深度 Mock 定时器
    local mock_timers = {}
    inst.DoTaskInTime = function(self, duration, fn)
        local timer = { canceled = false, fn = fn }
        timer.Cancel = function(t) t.canceled = true end
        table.insert(mock_timers, timer)
        return timer
    end

    -- 深度 Mock 适配最新架构的 Resolver
    local mock_resolver = {
        GetEffectConfig = function(self, id)
            if id == "eff_add" then return 10, 2, "add" end
            if id == "eff_toggle" then return nil, 1, "toggle" end
            if id == "eff_drain_death" then return 10, 1, "refresh" end
            return 10, 1, "ignore"
        end,
        OnEffectStart = function() end,
        OnEffectEnd = function() end,
        UpdateEffectLayers = function() end,
        HasFn = function() return false end,
        PayActivationCost = function() return true end,
        OnUpdateEffect = function(self, inst, id, dt, ctx, layers)
            -- 仅对模拟资源见底的 effect 返回 false
            return id ~= "eff_drain_death"
        end
    }
    cmp:SetResolver(mock_resolver)

    -- B. 测试层数叠加机制 (Add)
    cmp:Apply("eff_add")
    cmp:Apply("eff_add")
    suite:assert(cmp:GetLayers("eff_add") == 2, "Add 模式正常叠层")

    -- C. 测试全新 Toggle 模式 (核心防抖与闭环)
    cmp:Apply("eff_toggle")
    suite:assert(cmp:HasEffect("eff_toggle") == true, "Toggle 模式第一次 Apply，成功挂载")
    cmp:Apply("eff_toggle")
    suite:assert(cmp:HasEffect("eff_toggle") == false, "Toggle 模式已存在时再次 Apply，触发免单卸载机制")

    -- D. 测试帧更新自动卸载 (资源见底 / Fn 否定)
    cmp:Apply("eff_drain_death")
    suite:assert(cmp:HasEffect("eff_drain_death") == true, "准备自动注销测试")
    cmp:OnUpdate(0.033)
    suite:assert(cmp:HasEffect("eff_drain_death") == false, "OnUpdate 收到 Resolver 的 false 信号后，成功执行自我销毁")

    suite:Cleanup()
end
