-- scripts/tests/components/test_nikki_skill_trigger.lua
local TestUtils = require("tests/test_utils")

return function()
    local suite = TestUtils.CreateSuite("NikkiSkillTrigger Component (Deep)")
    local inst = suite:Track(CreateEntity())
    inst:AddComponent("nikki_skill_trigger")
    local cmp = inst.components.nikki_skill_trigger

    -- A. 测试缺失前置组件的极值拦截[cite: 33]
    local res = cmp:CastKey(KEY_A, {})
    suite:assert(res == false, "未注册 nikki_skill 时，CastKey 安全返回 false")
    res = cmp:CastAction("ACTION_MINE", {})
    suite:assert(res == false, "未注册 nikki_skill 时，CastAction 安全返回 false")

    -- B. 注入 nikki_skill 并 Mock 执行[cite: 33]
    inst:AddComponent("nikki_skill")
    local executed_counts = { keys = 0, actions = 0, events = 0 }
    inst.components.nikki_skill.ExecuteTrigger = function(self, skill, type, key, params)
        executed_counts[type] = executed_counts[type] + 1
    end

    -- C. 测试 SetTriggers 编译数据解析[cite: 33]
    local mock_compiled = {
        keys = { [KEY_A] = { skill_1 = true, skill_2 = true } },
        actions = { ["MINE"] = { skill_3 = true } },
        events = { ["onhit"] = { skill_4 = true } }
    }
    cmp:SetTriggers(mock_compiled)
    suite:assert(#cmp._active_event_listeners == 1, "事件监听器成功挂载 1 个")

    -- D. 测试多发路由与事件流转[cite: 33]
    cmp:CastKey(KEY_A, {})
    suite:assert(executed_counts.keys == 2, "1个按键绑定2个技能，触发器调用2次")
    
    cmp:CastAction("MINE", {})
    suite:assert(executed_counts.actions == 1, "动作触发路由正常")

    inst:PushEvent("onhit", {})
    suite:assert(executed_counts.events == 1, "事件捕获路由正常")

    -- E. 测试 Clear 彻底解绑防内存泄漏[cite: 33]
    cmp:Clear()
    suite:assert(#cmp._active_event_listeners == 0, "监听器列表清空")
    suite:assert(next(cmp.key_triggers) == nil, "按键字典清空")
    
    inst:PushEvent("onhit", {})
    suite:assert(executed_counts.events == 1, "Clear 后，事件完全解绑，不再增加")

    suite:Cleanup()
end