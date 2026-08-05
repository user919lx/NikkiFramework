-- scripts/tests/components/test_nikki_skill.lua
local TestUtils = require("tests/test_utils")

return function()
    local suite = TestUtils.CreateSuite("NikkiSkill Component (Deep)")
    local inst = suite:Track(CreateEntity())
    inst:AddComponent("nikki_skill")
    local cmp = inst.components.nikki_skill

    -- A. 准备深度 Mock (修复版)
    local event_pushed, replica_range_set = nil, nil
    
    -- 【修复点1】：绝对不要覆盖 inst.PushEvent！使用合法的监听器捕获事件
    inst:ListenForEvent("skill_max_range_dirty", function(_inst, data)
        event_pushed = "skill_max_range_dirty"
    end)
    
    -- 【修复点2】：安全地合并 replica 表，不要粗暴覆盖整个表
    inst.replica = inst.replica or {}
    inst.replica.nikki_skill = { 
        SetMaxRange = function(self, r) replica_range_set = r end 
    }
    
    local mock_resolver = {
        OnSkillAdd = function() end, OnSkillRemove = function() end,
        GetSkillRange = function(self, id) return id == "skill_long" and 10 or (id == "skill_mid" and 5 or nil) end,
        ExecuteServerTrigger = function() return true, "SUCCESS" end
    }

    -- B. 测试拦截与空安全
    cmp:AddSkills(nil) 
    suite:assert(cmp:IsAdded("any") == false, "AddSkills(nil) 安全拦截")
    
    -- C. 测试添加与射程更新逻辑
    cmp:SetResolver(mock_resolver)
    cmp:AddSkills({ "skill_mid" })
    suite:assert(cmp.max_range == 5, "添加后射程更新为 5")
    suite:assert(event_pushed == "skill_max_range_dirty" and replica_range_set == 5, "事件抛出与 Replica 同步正常")
    
    cmp:AddSkills({ "skill_mid" }) 
    suite:assert(#cmp._active_skills == 1, "重复添加技能被正确去重拦截")

    cmp:AddSkills({ "skill_long" })
    suite:assert(cmp.max_range == 10, "射程正确扩张为 10")

    -- D. 测试移除与射程收缩逻辑
    cmp:RemoveSkills({ "non_exist" })
    suite:assert(cmp.max_range == 10, "移除不存在的技能不影响状态")
    
    cmp:RemoveSkills({ "skill_long" })
    suite:assert(cmp.max_range == 5, "移除最大射程技能后，射程正确回落到 5")

    -- E. 测试 Trigger 执行分支
    local res, err = cmp:ExecuteTrigger("not_added_skill", "keys", "KEY_V", {})
    suite:assert(res == false and err == "NOT_ADDED", "拦截：未添加的技能不允许执行")

    res, err = cmp:CastSkill("skill_mid", {})
    suite:assert(res == true, "CastSkill 快捷调用正常执行")

    -- 现在 Cleanup() 可以安全调用 inst:Remove() 了
    suite:Cleanup()
end