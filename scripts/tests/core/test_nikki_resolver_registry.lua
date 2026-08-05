-- scripts/tests/core/test_nikki_resolver_registry.lua
local TestUtils = require("tests/test_utils")
local ResolverRegistry = require("nikki_resolver_registry")

return function()
    local suite = TestUtils.CreateSuite("ResolverRegistry (Deep)")

    -- A. 测试正常注册与获取[cite: 42]
    local mock_resolvers = { skill = {}, effect = {} }
    ResolverRegistry.Register("test_prefab", mock_resolvers)
    
    local get_res = ResolverRegistry.Get("test_prefab")
    suite:assert(get_res == mock_resolvers, "Get 成功返回了注册的引用")

    -- B. 测试空保护拦截[cite: 42]
    ResolverRegistry.Register(nil, mock_resolvers)
    suite:assert(ResolverRegistry.Get(nil) == nil, "Register 拦截了 nil prefab 注册")

    ResolverRegistry.Register("test_prefab2", nil)
    suite:assert(ResolverRegistry.Get("test_prefab2") == nil, "Register 拦截了 nil resolver 注册")

    suite:Cleanup()
end