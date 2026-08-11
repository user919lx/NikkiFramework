-- scripts/tests/init.lua
--[[
    用法：
        1. 游戏中控制台执行: ut = require("tests/init")
        2. 运行所有: ut.RunAll()
        3. 单独运行某类: ut.components.nikki_state()
]]

-- 引入 TestUtils 来控制全局数据
local TestUtils = require("tests/test_utils")

local init = {
    core = {
        nikki_resolver_registry = require("tests/core/test_nikki_resolver_registry"),
        nikki_framework_manager = require("tests/core/test_nikki_framework_manager"),
    },
    utils = {
        resource_adapter = require("tests/utils/test_resource_adapter"),
        modifier_adapter = require("tests/utils/test_modifier_adapter"),
    },
    components = {
        nikki_state = require("tests/components/test_nikki_state"),
        nikki_skill = require("tests/components/test_nikki_skill"),
        nikki_skill_trigger = require("tests/components/test_nikki_skill_trigger"),
        nikki_effect = require("tests/components/test_nikki_effect"),
    },
    resolvers = {
        base_resolver = require("tests/resolvers/test_base_resolver"),
        skill_resolver = require("tests/resolvers/test_skill_resolver"),
        effect_resolver = require("tests/resolvers/test_effect_resolver"),
        state_resolver = require("tests/resolvers/test_state_resolver"),
    }
}

-- 安全执行单组测试，实现异常隔离
local function SafeRunCategory(category_name, test_group)
    print(string.format("\n================ %s 测试 ================", category_name))
    for name, test_fn in pairs(test_group) do
        local success, err_msg = xpcall(test_fn, debug.traceback)
        if not success then
            print(string.format("\n[x] 模块 [%s/%s] 运行时崩溃中断:\n%s\n", category_name, name, tostring(err_msg)))
        end
    end
end

function init.RunAll()
    TestUtils.ResetGlobalStats()

    print("\n\n>>>>>>> 启动全局自动化测试 <<<<<<<")

    SafeRunCategory("Core 核心层", init.core)
    SafeRunCategory("Utils", init.utils)
    SafeRunCategory("Components", init.components)
    SafeRunCategory("Resolvers", init.resolvers)

    print("\n>>>>>>> 全局测试结束 <<<<<<<")

    local total = TestUtils.global_test_count
    local pass = TestUtils.global_success_count
    local fail = total - pass

    print(string.format(" 终极汇总: 共执行 %d 个断言 | 成功: %d | 失败: %d", total, pass, fail))

    if total > 0 and fail == 0 then
        print("==================================================")
        print(" ALL TESTS PASSED! 完美满绿！框架稳如磐石！")
        print("==================================================\n\n")
    else
        print("==================================================")
        print(" SOME TESTS FAILED! 请往上翻阅日志排查 [x] 标记！")
        print("==================================================\n\n")
    end
end

return init
