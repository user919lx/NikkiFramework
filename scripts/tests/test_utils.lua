local TestUtils = {
    global_test_count = 0,
    global_success_count = 0,
}

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
        TestUtils.global_test_count = TestUtils.global_test_count + 1

        if condition then
            self.success_count = self.success_count + 1
            TestUtils.global_success_count = TestUtils.global_success_count + 1
            print(string.format("[✓] %s", message))
        else
            print(string.format("[x] 测试失败: %s", message))
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

        -- 区分全部通过与存在失败的明确状态
        local is_all_passed = (self.success_count == self.test_count) and (self.test_count > 0)
        local status_str = is_all_passed and "[✓ 全部通过]" or
        string.format("[x 存在失败 (%d 项未通过)]", self.test_count - self.success_count)
        print(string.format("=== %s 测试汇总: %s (%d/%d) ===\n", self.name, status_str, self.success_count, self.test_count))
    end

    return suite
end

return TestUtils
