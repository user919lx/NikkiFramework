-- scripts/components/nikki_skill_trigger_replica.lua
local log = require("utils/log")

local NikkiSkillTrigger = Class(function(self, inst)
    self.inst = inst
    -- 在 Replica 注册网络变量，两端都能直接访问
    self._range_target = net_entity(inst.GUID, "nikki_skill_trigger._range_target")
end)

function NikkiSkillTrigger:SetRangeTarget(target)
    self._range_target:set(target ~= nil and target:IsValid() and target or nil)
end

function NikkiSkillTrigger:GetRangeTarget()
    return self._range_target:value()
end

function NikkiSkillTrigger:CastKey(key_code)
    if not self.inst.replica.nikki_state then return false end
    local skills = self.inst.replica.nikki_state:GetSkillsForKey(key_code)
    if not skills then return false end

    -- 【核心注入】：自动提取记忆目标，封装进 params 往下传
    local params = { key = key_code }
    local mem_target = self:GetRangeTarget()
    if mem_target and mem_target:IsValid() then
        params.target = mem_target
        log.debug("[NikkiSkillTrigger Replica] Injected memorized target: %s", tostring(mem_target))
    end

    if self.inst.replica.nikki_skill then
        self.inst.replica.nikki_skill:CastKey(key_code, skills, params)
    end
    return true
end

function NikkiSkillTrigger:CastSkill(id, params)
    params = params or {}
    -- 如果玩家没有显式指定目标，则尝试填充记忆目标
    if not params.target then
        local mem_target = self:GetRangeTarget()
        if mem_target and mem_target:IsValid() then
            params.target = mem_target
        end
    end
    if self.inst.replica.nikki_skill then
        self.inst.replica.nikki_skill:CastSkill(id, params)
    end
end

return NikkiSkillTrigger
