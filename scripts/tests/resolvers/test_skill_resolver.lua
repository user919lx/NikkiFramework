---@diagnostic disable: duplicate-set-field
local TestUtils = require("tests/test_utils")
local SkillResolver = require("resolvers/skill_resolver")
local ResourceAdapter = require("utils/resource_adapter")

return function()
    local suite = TestUtils.CreateSuite("SkillResolver")

    local inst = suite:Track(CreateEntity())
    inst:AddComponent("nikki_effect")

    -- 修复点：Toggle 绑定的 Buff 必须无 duration (即返回 nil 代表永久 Effect)
    inst.components.nikki_effect:SetResolver({
        GetEffectConfig = function() return nil, 1, "refresh" end,
        OnEffectStart = function() end,
        OnEffectEnd = function() end,
        UpdateEffectLayers = function() end
    })

    local old_get_cur = ResourceAdapter.GetCurrent
    local old_delta = ResourceAdapter.DoDelta
    ResourceAdapter.GetCurrent = function(inst, res) return inst._mock_sanity or 0 end
    ResourceAdapter.DoDelta = function(inst, res, v) inst._mock_sanity = (inst._mock_sanity or 0) + v end

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
    inst._mock_sanity = 0
    res, err = resolver:ExecuteServerTrigger(inst, "test_toggle", "keys", "V", {})
    suite:assert(res == true, "空蓝时 Toggle 依然成功关闭，绕过验资")
    suite:assert(not inst.components.nikki_effect:HasEffect("test_buff"), "Buff 成功卸载")
    suite:assert(inst._mock_sanity == 0, "蓝量未变，触发免单逻辑")

    ResourceAdapter.GetCurrent = old_get_cur
    ResourceAdapter.DoDelta = old_delta

    suite:Cleanup()
end
