-- scripts/components/nikki_skill_trigger.lua
local log = require("utils/log")

-- ==========================================================
-- 状态同步监听器：当 self.range_target 改变时，自动同步给 Replica
-- ==========================================================
local function on_range_target(self, target)
    if self.inst.replica.nikki_skill_trigger then
        self.inst.replica.nikki_skill_trigger:SetRangeTarget(target)
    end
    -- 可选：如果你后续需要服务端监听目标改变，可以直接解开下面这行
    -- self.inst:PushEvent("skill_range_target_dirty", { target = target })
end

local NikkiSkillTrigger = Class(function(self, inst)
    self.inst = inst
    self.range_target = nil -- 内部管理的数据字段

    self.key_triggers = {}
    self.action_triggers = {}
    self._active_event_listeners = {}
end,
nil,
{
    -- 绑定监听器：每当 self.range_target = xxx 时，触发 on_range_target
    range_target = on_range_target
})

function NikkiSkillTrigger:SetTriggers(compiled_triggers)
    self:Clear()
    if not compiled_triggers then return end

    self.key_triggers = compiled_triggers.keys or {}
    self.action_triggers = compiled_triggers.actions or {}

    if compiled_triggers.events then
        for event_name, skills_dict in pairs(compiled_triggers.events) do
            if next(skills_dict) then
                local handler = function(inst, data)
                    if self.inst.components.nikki_skill then
                        for skill_id, _ in pairs(skills_dict) do
                            self.inst.components.nikki_skill:ExecuteTrigger(skill_id, "events", event_name, data)
                        end
                    end
                end
                self.inst:ListenForEvent(event_name, handler)
                table.insert(self._active_event_listeners, { event = event_name, fn = handler })
            end
        end
    end
end

function NikkiSkillTrigger:Clear()
    self.key_triggers = {}
    self.action_triggers = {}
    for _, listener in ipairs(self._active_event_listeners) do
        self.inst:RemoveEventCallback(listener.event, listener.fn)
    end
    self._active_event_listeners = {}
end

-- ==========================================================
-- 数据读写接口
-- ==========================================================
function NikkiSkillTrigger:SetRangeTarget(target)
    -- 直接修改内部字段，由 Class 的元表魔法自动触发 on_range_target
    self.range_target = target
end

function NikkiSkillTrigger:GetRangeTarget()
    return self.range_target
end

-- ==========================================================
-- 统一执行网关：拦截 target，并向 nikki_skill 分发
-- ==========================================================

-- 接收来自 RPC 或内部系统的单发技能请求
function NikkiSkillTrigger:CastSkill(skill_id, params)
    if params and params.target and params.target:IsValid() then
        self:SetRangeTarget(params.target)
    end

    if self.inst.components.nikki_skill then
        return self.inst.components.nikki_skill:ExecuteTrigger(skill_id, "cast", "default", params)
    end
    return false
end

-- 接收原生 Action 系统的触发
function NikkiSkillTrigger:CastAction(action_id, params)
    if params and params.target and params.target:IsValid() then
        self:SetRangeTarget(params.target)
    end

    local skills = self.action_triggers[action_id]
    if not skills or not self.inst.components.nikki_skill then return false end

    for skill_id, _ in pairs(skills) do
        self.inst.components.nikki_skill:ExecuteTrigger(skill_id, "actions", action_id, params)
    end
    return true
end

-- 保留给纯服务端逻辑（如 NPC 模拟按键），接收按键触发
function NikkiSkillTrigger:CastKey(key_code, params)
    if params and params.target and params.target:IsValid() then
        self:SetRangeTarget(params.target)
    end

    local skills = self.key_triggers[key_code]
    if not skills or not self.inst.components.nikki_skill then return false end

    for skill_id, _ in pairs(skills) do
        self.inst.components.nikki_skill:ExecuteTrigger(skill_id, "keys", key_code, params)
    end
    return true
end

return NikkiSkillTrigger
