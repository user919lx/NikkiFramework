-- scripts/components/nikki_skill_trigger.lua
local NikkiComponentBase = require("components/nikki_component_base")
local log = require("utils/log")

local NikkiSkillTrigger = Class(NikkiComponentBase, function(self, inst)
    NikkiComponentBase._ctor(self, inst)

    self.key_triggers = {}
    self.action_triggers = {}

    -- 【新增】用于记录动态绑定的事件监听器，以便在切形态时清理
    self._active_event_listeners = {}

    self:AttachCombatEvents()
end)

function NikkiSkillTrigger:SetTriggers(triggers_def)
    self:Clear()
    if not triggers_def then return end

    -- 1. 装配按键映射
    if triggers_def.keys then
        for key_code, skill_id in pairs(triggers_def.keys) do
            self.key_triggers[key_code] = skill_id
        end
    end

    -- 2. 装配动作映射
    if triggers_def.actions then
        for action_id, skill_id in pairs(triggers_def.actions) do
            self.action_triggers[action_id] = skill_id
        end
    end

    -- 3. 【新增】装配事件映射
    if triggers_def.events then
        for event_name, skill_id in pairs(triggers_def.events) do
            -- 创建一个闭包处理函数，把 event 抛出的 data 当作 params 传给技能
            local handler = function(inst, data)
                if self.inst.components.nikki_skill then
                    log.debug("[NikkiSkillTrigger] Event '%s' triggered -> routing to skill '%s'", tostring(event_name),
                        tostring(skill_id))
                    self.inst.components.nikki_skill:CastSkill(skill_id, data)
                end
            end

            -- 监听事件
            self.inst:ListenForEvent(event_name, handler)

            -- 记录下来，方便以后注销
            table.insert(self._active_event_listeners, { event = event_name, fn = handler })
        end
    end

    log.debug("[NikkiSkillTrigger] Triggers updated. Keys: %d, Actions: %d, Events: %d",
        table.count(self.key_triggers), table.count(self.action_triggers), #self._active_event_listeners)
end

function NikkiSkillTrigger:Clear()
    self.key_triggers = {}
    self.action_triggers = {}

    -- 【新增】安全注销所有动态监听的事件，防止切形态后技能还在触发！
    for _, listener in ipairs(self._active_event_listeners) do
        self.inst:RemoveEventCallback(listener.event, listener.fn)
    end
    self._active_event_listeners = {}
end

-- ========================================================
-- 触发执行入口 (由外部 RPC 或 Action Handler 呼叫)
-- ========================================================

function NikkiSkillTrigger:CastKey(key_code, params)
    local skill_id = self.key_triggers[key_code]
    if not skill_id then return false end
    if self.inst.components.nikki_skill then
        return self.inst.components.nikki_skill:CastSkill(skill_id, params)
    end
    return false
end

function NikkiSkillTrigger:CastAction(action_id, params)
    local skill_id = self.action_triggers[action_id]
    if not skill_id then return false end
    if self.inst.components.nikki_skill then
        return self.inst.components.nikki_skill:CastSkill(skill_id, params)
    end
    return false
end

-- ========================================================
-- 内置战斗事件回调转发 (保持不变)
-- ========================================================

function NikkiSkillTrigger:AttachCombatEvents()
    self.inst:ListenForEvent("onhitother", function(owner, data)
        if not data or not data.target then return end
        self:OnHit(data)
    end)

    self.inst:ListenForEvent("attacked", function(owner, data)
        if not data or not data.attacker then return end
        self:OnHurt(data)
    end)
end

function NikkiSkillTrigger:OnHit(params)
    if self.inst.components.nikki_skill then
        self.inst.components.nikki_skill:OnHit(params)
    end
end

function NikkiSkillTrigger:OnHurt(params)
    if self.inst.components.nikki_skill then
        self.inst.components.nikki_skill:OnHurt(params)
    end
end

-- 遗留设置
function NikkiSkillTrigger:SetRangeTarget(target)
    self.range_target = target
end

function NikkiSkillTrigger:GetRangeTarget()
    return self.range_target
end

return NikkiSkillTrigger
