-- scripts/tests/components/test_nikki_effect.lua
local TestUtils = require("tests/test_utils")

return function()
    local suite = TestUtils.CreateSuite("NikkiEffect Component (Deep)")
    local inst = suite:Track(CreateEntity())
    inst:AddComponent("nikki_effect")
    local cmp = inst.components.nikki_effect

    -- A. 深度 Mock 定时器，用于验证是否被取消[cite: 36]
    local mock_timers = {}
    inst.DoTaskInTime = function(self, duration, fn)
        local timer = { canceled = false, fn = fn }
        timer.Cancel = function(t) t.canceled = true end
        table.insert(mock_timers, timer)
        return timer
    end

    local mock_resolver = {
        GetEffectConfig = function(self, id)
            if id == "eff_ignore" then return 10, 2, "ignore" end
            if id == "eff_refresh" then return 10, 2, "refresh" end
            if id == "eff_add" then return 10, 2, "add" end -- 上限为 2
        end,
        OnEffectStart = function() end, OnEffectEnd = function() end,
        UpdateEffectLayers = function() end, HasFn = function() return false end
    }
    cmp:SetResolver(mock_resolver)

    -- B. 测试 Apply 分支：Ignore[cite: 36]
    suite:assert(cmp:Apply("eff_ignore") == true, "首次添加成功")
    suite:assert(cmp:Apply("eff_ignore") == false, "Ignore 模式下再次添加直接返回 false")

    -- C. 测试 Apply 分支：Refresh[cite: 36]
    cmp:Apply("eff_refresh")
    local first_timer = mock_timers[#mock_timers]
    cmp:Apply("eff_refresh")
    suite:assert(first_timer.canceled == true, "Refresh 模式下，旧定时器被成功 Cancel")
    suite:assert(cmp:GetLayers("eff_refresh") == 1, "Refresh 模式下层数不变")

    -- D. 测试 Apply 分支：Add 及溢出[cite: 36]
    cmp:Apply("eff_add")
    cmp:Apply("eff_add")
    suite:assert(cmp:GetLayers("eff_add") == 2, "Add 模式下层数叠加至 2")
    
    local old_timer_idx = #mock_timers - 1
    cmp:Apply("eff_add") -- 触发溢出上限极值
    suite:assert(cmp:GetLayers("eff_add") == 2, "超过 max 上限，层数锁定")
    suite:assert(mock_timers[old_timer_idx].canceled == true, "达到上限时，最老的定时器被正确移除")

    -- E. 测试 Remove 分支：按层降级 vs 强制清除[cite: 36]
    cmp:Remove("eff_add", false)
    suite:assert(cmp:GetLayers("eff_add") == 1, "非强制 Remove，层数 -1")
    cmp:Remove("eff_add", true)
    suite:assert(cmp:HasEffect("eff_add") == false, "强制 Remove，彻底清空")

    -- F. 测试 OnUpdate 分支[cite: 36]
    cmp:Apply("eff_ignore")
    suite:assert(pcall(function() cmp:OnUpdate(0.033) end), "OnUpdate 轮询在无 Fn 时安全放行")

    suite:Cleanup()
end