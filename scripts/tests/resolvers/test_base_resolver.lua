-- scripts/tests/resolvers/test_base_resolver.lua
local TestUtils = require("tests/test_utils")
local BaseResolver = require("resolvers/base_resolver")

return function()
    local suite = TestUtils.CreateSuite("BaseResolver (Deep)")

    -- A. 测试初始化容错[cite: 41]
    local empty_resolver = BaseResolver(nil)
    suite:assert(next(empty_resolver:GetAllDefs()) == nil, "传入 nil 时安全初始化为空表")

    -- B. 准备数据
    local mock_data = {
        skill_1 = { name = "Fireball" },
        skill_2 = { name = "Frostbolt" }
    }
    local resolver = BaseResolver(mock_data)

    -- C. 测试获取方法[cite: 41]
    suite:assert(resolver:GetDef("skill_1").name == "Fireball", "GetDef 精准查表")
    suite:assert(resolver:GetDef("skill_3") == nil, "查询不存在的 key 时安全返回 nil")
    
    local all_defs = resolver:GetAllDefs()
    suite:assert(all_defs.skill_2.name == "Frostbolt", "GetAllDefs 完整返回数据表")

    -- D. 测试 ID 提取[cite: 41]
    local ids = resolver:GetAllIds()
    local has_s1, has_s2 = false, false
    for _, id in ipairs(ids) do
        if id == "skill_1" then has_s1 = true end
        if id == "skill_2" then has_s2 = true end
    end
    suite:assert(#ids == 2 and has_s1 and has_s2, "GetAllIds 成功提取并遍历所有主键")

    suite:Cleanup()
end