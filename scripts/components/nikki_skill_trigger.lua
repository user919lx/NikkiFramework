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
        self.range_target = nil

        -- 三大触发源映射表（对称结构）
        self.key_triggers = {}
        self.action_triggers = {}
        self.event_triggers = {}

        -- 存动态注册的事件监听器句柄，方便 Clear 时清理
        self._active_event_listeners = {}
    end,
    nil,
    {
        range_target = on_range_target
    })

-- ==========================================================
-- 配置触发器（由 State 或外部调用）
-- ==========================================================
function NikkiSkillTrigger:SetTriggers(compiled_triggers)
    self:Clear()
    if not compiled_triggers then return end

    -- 存储映射表
    self.key_triggers = compiled_triggers.keys or {}
    self.action_triggers = compiled_triggers.actions or {}
    self.event_triggers = compiled_triggers.events or {}

    -- 注册事件监听器（现在只负责“监听”，不负责“执行”）
    if compiled_triggers.events then
        for event_name, skills_dict in pairs(compiled_triggers.events) do
            if next(skills_dict) then
                local handler = function(inst, data)
                    -- 核心改动：不再内联 ExecuteTrigger，而是走统一的 CastEvent 入口
                    self:CastEvent(event_name, data)
                end
                self.inst:ListenForEvent(event_name, handler)
                table.insert(self._active_event_listeners, {
                    event = event_name,
                    fn = handler
                })
            end
        end
    end
end

-- ==========================================================
-- 清理所有触发器与监听器
-- ==========================================================
function NikkiSkillTrigger:Clear()
    self.key_triggers = {}
    self.action_triggers = {}
    self.event_triggers = {}

    for _, listener in ipairs(self._active_event_listeners) do
        self.inst:RemoveEventCallback(listener.event, listener.fn)
    end
    self._active_event_listeners = {}
end

-- ==========================================================
-- 数据读写接口（目标缓存）
-- ==========================================================
function NikkiSkillTrigger:SetRangeTarget(target)
    self.range_target = target
end

function NikkiSkillTrigger:GetRangeTarget()
    return self.range_target
end

-- ==========================================================
-- 三大统一执行网关（对称设计）
-- ==========================================================

-- 1. 直接技能调用（如 RPC、UI 点击、脚本调用）
function NikkiSkillTrigger:CastSkill(skill_id, params)
    if params and params.target and params.target:IsValid() then
        self:SetRangeTarget(params.target)
    end

    if self.inst.components.nikki_skill then
        return self.inst.components.nikki_skill:ExecuteTrigger(skill_id, "cast", "default", params)
    end
    return false
end

-- 2. 原生 Action 行为触发（如砍树、攻击、钓鱼）
--    注意：此处采用“短路”逻辑，一旦某个技能失败立即返回，
--    因为 Action 需要告知游戏引擎原动作是否被成功接管。
function NikkiSkillTrigger:CastAction(action_id, params)
    if params and params.target and params.target:IsValid() then
        self:SetRangeTarget(params.target)
    end

    local skills = self.action_triggers[action_id]
    if not skills or not self.inst.components.nikki_skill then
        return false
    end

    for skill_id, _ in pairs(skills) do
        local res, reason = self.inst.components.nikki_skill:ExecuteTrigger(skill_id, "actions", action_id, params)
        if res == false then
            return false, reason
        end
    end
    return true
end

-- 3. 按键触发（键盘、手柄）
--    注意：按键通常是“同时触发”多个技能（如切状态+放技能），
--    因此不采用短路逻辑，遍历执行所有绑定的技能。
function NikkiSkillTrigger:CastKey(key_code, params)
    if params and params.target and params.target:IsValid() then
        self:SetRangeTarget(params.target)
    end

    local skills = self.key_triggers[key_code]
    if not skills or not self.inst.components.nikki_skill then
        return false
    end

    for skill_id, _ in pairs(skills) do
        self.inst.components.nikki_skill:ExecuteTrigger(skill_id, "keys", key_code, params)
    end
    return true
end

-- 4. 事件触发（如“血量过低”、“进入战斗”）
--    注意：事件是“广播”语义，一个技能失败不应阻断其他技能，
--    因此遍历执行所有绑定的技能，不短路。
function NikkiSkillTrigger:CastEvent(event_name, data)
    local skills = self.event_triggers[event_name]
    if not skills or not self.inst.components.nikki_skill then
        return false
    end

    for skill_id, _ in pairs(skills) do
        self.inst.components.nikki_skill:ExecuteTrigger(skill_id, "events", event_name, data)
    end
    return true
end

return NikkiSkillTrigger
