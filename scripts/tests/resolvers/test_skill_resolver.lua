-- scripts/tests/resolvers/test_skill_resolver.lua
local TestUtils = require("tests/test_utils")
local SkillResolver = require("resolvers/skill_resolver")
local ResourceAdapter = require("utils/resource_adapter")

return function()
    local suite = TestUtils.CreateSuite("SkillResolver")
    print("[Test] 开始 SkillResolver (Toggle互斥/免单) 测试...")

    local inst = suite:Track(CreateEntity())
    inst:AddComponent("nikki_effect")
    
    -- 【修正】：必须给 nikki_effect 注入一个替身 Resolver，否则它的 Apply() 会直接返回 false！
    inst.components.nikki_effect:SetResolver({
        GetEffectConfig = function() return 10, 1, "refresh" end,
        OnEffectStart = function() end,
        OnEffectEnd = function() end,
        UpdateEffectLayers = function() end
    })
    
    -- Mock ResourceAdapter 避免依赖真实的饥荒属性组件
    local old_get_comp = ResourceAdapter.GetComponent
    local old_get_cur = ResourceAdapter.GetCurrent
    local old_delta = ResourceAdapter.DoDelta
    ResourceAdapter.GetComponent = function() return true end
    ResourceAdapter.GetCurrent = function() return inst._mock_sanity or 0 end
    ResourceAdapter.DoDelta = function(c, v) inst._mock_sanity = (inst._mock_sanity or 0) + v end

    local resolver = SkillResolver({
        ["test_toggle"] = {
            cost = { resource = "sanity", amount = 10 },
            toggle = { "test_buff" }
        }
    })

    -- 测试 1: 正常扣费开启 Toggle
    inst._mock_sanity = 100
    local res, err = resolver:ExecuteServerTrigger(inst, "test_toggle", "keys", "V", {})
    suite:assert(res == true, "满蓝时 Toggle 成功开启")
    suite:assert(inst.components.nikki_effect:HasEffect("test_buff"), "Buff 成功挂载")
    suite:assert(inst._mock_sanity == 90, "成功扣除 10 点消耗")

    -- 测试 2: 漏洞修复验证 (空蓝时，依然能免费关闭 Toggle)
    inst._mock_sanity = 0 -- 强制空蓝
    res, err = resolver:ExecuteServerTrigger(inst, "test_toggle", "keys", "V", {})
    suite:assert(res == true, "空蓝时 Toggle 依然成功关闭，绕过验资")
    suite:assert(not inst.components.nikki_effect:HasEffect("test_buff"), "Buff 成功卸载")
    suite:assert(inst._mock_sanity == 0, "蓝量未变，触发免单逻辑")

    -- 还原环境
    ResourceAdapter.GetComponent = old_get_comp
    ResourceAdapter.GetCurrent = old_get_cur
    ResourceAdapter.DoDelta = old_delta

    suite:Cleanup()
end