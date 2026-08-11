-- scripts/tests/components/test_nikki_state.lua
local TestUtils = require("tests/test_utils")

return function()
    local suite = TestUtils.CreateSuite("NikkiState Component (Deep)")
    local inst = suite:Track(CreateEntity())
    
    -- A. 挂载测试组件
    inst:AddComponent("nikki_state")
    local cmp = inst.components.nikki_state

    -- B. 安全地 Mock 外部依赖与视觉组件
    inst.AnimState = {
        _build = "", _bank = "",
        SetBuild = function(self, b) self._build = b end,
        SetBank = function(self, b) self._bank = b end
    }
    
    local replica_state = nil
    -- 【修复点 1】：绝对不要重写 inst.replica 表！只追加需要的属性
    inst.replica.nikki_state = { 
        SetState = function(self, s) replica_state = s end 
    }
    
    local event_pushed = nil
    -- 【修复点 2】：使用原生监听器，绝不覆盖 inst.PushEvent！
    inst:ListenForEvent("nikki_state_dirty", function(_inst, data)
        event_pushed = data.state
    end)

    -- C. 测试 ApplyStateDef 缺失前置组件的极值拦截
    cmp:ApplyStateDef({ skills = {"test"} })
    suite:assert(next(cmp._active_overlay_skills) == nil, "缺少 nikki_skill/trigger 组件时，ApplyStateDef 必须安全返回，不应用任何数据")

    -- 补全依赖组件并设置 Mock 函数
    inst:AddComponent("nikki_skill")
    inst:AddComponent("nikki_effect")
    inst:AddComponent("nikki_skill_trigger")
    
    local added_skills, removed_skills = {}, {}
    inst.components.nikki_skill.AddSkills = function(self, s) added_skills = s end
    inst.components.nikki_skill.RemoveSkills = function(self, s) removed_skills = s end
    
    local applied_effects, removed_effects = {}, {}
    inst.components.nikki_effect.Apply = function(self, e) applied_effects[e] = true end
    inst.components.nikki_effect.Remove = function(self, e, force) removed_effects[e] = force end

    local trigger_cleared, trigger_set = false, nil
    inst.components.nikki_skill_trigger.Clear = function(self) trigger_cleared = true end
    inst.components.nikki_skill_trigger.SetTriggers = function(self, t) trigger_set = t end

    -- D. Mock Resolver
    local mock_def = {
        visuals = { build = "new_build", bank = "new_bank" },
        skills = { "skill_1" },
        effects = { "eff_1" },
        tags = { "TAG_1" },
        compiled_triggers = { keys = { KEY_A = true } },
        wheel = { "wheel_1" }
    }
    cmp:SetResolver({
        GetStateDef = function(self, state) return state == "mock_state" and mock_def or nil end
    })

    -- E. 测试 Init 与默认回退
    cmp:Init(cmp.resolver, "default_state")
    suite:assert(cmp.default_state == "default_state", "Init 必须正确覆盖 default_state")

    -- F. 测试 SetState 全量数据挂载
    cmp:SetState("mock_state")
    suite:assert(replica_state == "mock_state", "SetState 必须同步调用 Replica:SetState")
    suite:assert(event_pushed == "mock_state", "SetState 必须向外抛出 nikki_state_dirty 事件")
    suite:assert(inst.AnimState._build == "new_build" and inst.AnimState._bank == "new_bank", "视觉数据(Build/Bank)成功应用")
    suite:assert(added_skills[1] == "skill_1", "新技能被派发给 nikki_skill")
    suite:assert(applied_effects["eff_1"] == true, "新效果被派发给 nikki_effect")
    suite:assert(inst:HasTag("TAG_1"), "新 Tag 成功挂载到 inst")
    suite:assert(trigger_set ~= nil, "触发器数据成功派发给 Trigger 组件")

    -- G. 测试 SetState 重复切换的静默拦截与 force
    event_pushed = nil
    cmp:SetState("mock_state")
    suite:assert(event_pushed == nil, "切换相同状态时，必须直接 return，不重复执行")
    
    cmp:SetState("mock_state", true)
    suite:assert(event_pushed == "mock_state", "传入 force=true 时，无视重复状态，强制执行")

    -- H. 测试切回空状态时的数据清空
    trigger_cleared = false
    cmp:SetState("empty_state")
    suite:assert(removed_skills[1] == "skill_1", "离开状态时，必须通知 nikki_skill 移除旧技能")
    suite:assert(removed_effects["eff_1"] == true, "离开状态时，必须通知 nikki_effect 强制移除旧效果")
    suite:assert(not inst:HasTag("TAG_1"), "离开状态时，旧 Tag 必须被移除")
    suite:assert(trigger_cleared == true, "离开状态时，必须调用 Trigger 的 Clear 方法")

    suite:Cleanup()
end