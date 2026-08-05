-- scripts/tests/test_utils.lua
local TestUtils = {
    -- 新增：全局状态追踪
    global_test_count = 0,
    global_success_count = 0,
}

-- 新增：重置全局统计（防止玩家在游戏里多次执行 ut.RunAll() 导致数据无限叠加）
function TestUtils.ResetGlobalStats()
    TestUtils.global_test_count = 0
    TestUtils.global_success_count = 0
end

function TestUtils.CreateSuite(name)
    local suite = {
        name = name,
        test_count = 0,
        success_count = 0,
        entities = {}
    }

    function suite:assert(condition, message)
        self.test_count = self.test_count + 1
        TestUtils.global_test_count = TestUtils.global_test_count + 1 -- 累加到全局[cite: 37]

        if condition then
            self.success_count = self.success_count + 1
            TestUtils.global_success_count = TestUtils.global_success_count + 1 -- 累加到全局[cite: 37]
            print(string.format("[✓] %s", message))
        else
            print(string.format("[x] 测试失败: %s", message))
            -- 可以选择在这里加上 error() 中断测试，或者继续执行
        end
        return condition
    end

    function suite:Track(ent)
        if ent then table.insert(self.entities, ent) end
        return ent
    end

    function suite:Cleanup()
        for _, ent in ipairs(self.entities) do
            if ent and ent:IsValid() then
                ent:Remove()
            end
        end
        self.entities = {}
        print(string.format("=== %s 测试汇总: %d/%d 通过 ===\n", self.name, self.success_count, self.test_count))
    end

    return suite
end

return TestUtils
