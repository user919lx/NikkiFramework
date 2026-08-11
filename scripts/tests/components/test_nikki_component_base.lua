-- scripts/tests/components/test_nikki_component_base.lua
local TestUtils = require("tests/test_utils")
local NikkiComponentBase = require("components/nikki_component_base")

return function()
    local suite = TestUtils.CreateSuite("NikkiComponentBase (Deep)")
    local inst = suite:Track(CreateEntity())
    
    -- A. 测试实例化与默认状态[cite: 39]
    local base_comp = NikkiComponentBase(inst)
    suite:assert(base_comp.inst == inst, "必须正确持有 inst 引用")
    suite:assert(base_comp:GetResolver() == nil, "初始状态下 Resolver 必须为 nil")

    -- B. 测试依赖注入 (Set/Get)[cite: 39]
    local mock_resolver = { is_mock = true }
    base_comp:SetResolver(mock_resolver)
    suite:assert(base_comp:GetResolver() == mock_resolver, "SetResolver 后，GetResolver 必须返回完全相同的引用")

    suite:Cleanup()
end