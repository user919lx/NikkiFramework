---@diagnostic disable: duplicate-set-field
-- scripts/tests/resolvers/test_skill_resolver.lua
local TestUtils = require("tests/test_utils")
local SkillResolver = require("resolvers/skill_resolver")
local ResourceAdapter = require("utils/resource_adapter")

return function()
    local suite = TestUtils.CreateSuite("SkillResolver (Deep)")
    local inst = suite:Track(CreateEntity())

    -- 深度 Mock 资源
    local old_get_cur = ResourceAdapter.GetCurrent
    local old_delta = ResourceAdapter.DoDelta
    ResourceAdapter.GetCurrent = function(inst, res) return inst._mock_mana or 0 end
    ResourceAdapter.DoDelta = function(inst, res, v) inst._mock_mana = (inst._mock_mana or 0) + v end

    local fn_called = false
    local resolver = SkillResolver({
        ["test_skill"] = {
            cost = { res = "mana", amount = 20 },
            fn = function()
                fn_called = true; return true
            end
        }
    })

    -- 测试 1: 满蓝成功施放与瞬间扣费
    inst._mock_mana = 100
    fn_called = false
    local res, err = resolver:ExecuteServerTrigger(inst, "test_skill", "keys", "V", {})
    suite:assert(res == true, "满资源时单次技能成功执行")
    suite:assert(fn_called == true, "业务逻辑 fn 被成功调用")
    suite:assert(inst._mock_mana == 80, "瞬间精确扣除了 cost.amount 费用")

    -- 测试 2: 资源不足时被严格拦截
    inst._mock_mana = 10
    fn_called = false
    res, err = resolver:ExecuteServerTrigger(inst, "test_skill", "keys", "V", {})
    suite:assert(res == false and err == "NOT_ENOUGH_RESOURCE", "资源不足时被系统静默拦截")
    suite:assert(fn_called == false, "拦截时绝不执行 fn")
    suite:assert(inst._mock_mana == 10, "拦截时绝不扣除剩余资源")

    ResourceAdapter.GetCurrent = old_get_cur
    ResourceAdapter.DoDelta = old_delta

    suite:Cleanup()
end
