-- scripts/components/nikki_skill_trigger_replica.lua
local log = require("utils/log")

local function GetRangeIndicator (inst)
    if inst.range_indicator then
        return inst.range_indicator
    end
    local indicator = SpawnPrefab("nikki_range_indicator")
    indicator:SetOwner(inst)
    inst.range_indicator = indicator
    return indicator
end

local NikkiSkillTrigger = Class(function(self, inst)
    self.inst = inst

    self._keys = {}
    self._aiming = false
    self._aiming_skill = nil
    self._aiming_params = nil

    self.inst:ListenForEvent("nikki_state_dirty", function(inst, data)
        local state = data and data.state
        local old_state = data and data.old_state
        self:_RefreshKeys(state, old_state)
        self:ExitAiming()
    end)
end)

function NikkiSkillTrigger:Init(resolver)
    if not resolver then
        log.warn("[NikkiSkillTrigger Replica] No resolver provided during Init.")
        return
    end
    self._resolver = resolver
    self:_RefreshKeys(self._resolver:GetBasicState(), nil)
    self:_RefreshKeys()
    self:ExitAiming()
end

function NikkiSkillTrigger:AddKey(key_code, skill_id)
    self._keys[key_code] = skill_id
end

function NikkiSkillTrigger:RemoveKey(key_code)
    self._keys[key_code] = nil
end

function NikkiSkillTrigger:_RefreshKeys(current_state, old_state)
    log.debug("[NikkiSkillTrigger Replica] Refreshing keys for state '%s' (old_state=%s)", current_state,
        tostring(old_state))
    local resolver = self._resolver
    if not resolver then
        log.debug("[NikkiSkillTrigger Replica] No resolver available to refresh keys.")
        return
    end

    if not current_state then
        local state_comp = self.inst.replica.nikki_state
        if state_comp then
            current_state = state_comp:GetState()
        end
        if not current_state then
            log.debug("[NikkiSkillTrigger Replica] No state available to refresh keys.")
            return
        end
    end

    if old_state then
        local old_def = resolver:GetStateDef(old_state)
        if old_def and old_def.keys then
            for key_code, _ in pairs(old_def.keys) do
                self:RemoveKey(key_code)
            end
            log.debug("[NikkiSkillTrigger Replica] Removed keys for old state '%s'", old_state)
        end
    end

    local state_def = resolver:GetStateDef(current_state)
    if not state_def then
        log.debug("[NikkiSkillTrigger Replica] State definition not found for '%s'", current_state)
        return
    end
    if state_def.keys and next(state_def.keys) then
        for key_code, skill_id in pairs(state_def.keys) do
            self:AddKey(key_code, skill_id)
        end
    end

    log.debug("[NikkiSkillTrigger Replica] Refreshed keys for state '%s' (old_state=%s)", current_state,
        tostring(old_state))
end

function NikkiSkillTrigger:GetSkillsForKey(key_code)
    return self._keys[key_code]
end


-- ============================================================
-- 瞄准状态管理（客户端）
-- ============================================================
function NikkiSkillTrigger:EnterAiming(skill_id)
    self._aiming = true
    self._aiming_skill = skill_id
    log.debug("[NikkiSkillTrigger Replica] Enter aiming for skill: %s", skill_id)

    local indicator = GetRangeIndicator(self.inst)
    if indicator then
        local range = self.inst.replica.nikki_skill and self.inst.replica.nikki_skill:GetSkillRange(skill_id)
        if range and range > 0 then
            indicator:EnterOverride(range)
        else
            log.debug("[NikkiSkillTrigger Replica] Skill '%s' has no range, not overriding indicator", skill_id)
        end
    else
        log.debug("[NikkiSkillTrigger Replica] No range indicator found on owner")
    end
end

function NikkiSkillTrigger:ExitAiming()
    self._aiming = false
    self._aiming_skill = nil
    log.debug("[NikkiSkillTrigger Replica] Exit aiming")
    local indicator = GetRangeIndicator(self.inst)
    if indicator then
        indicator:ExitOverride()
    end
end

function NikkiSkillTrigger:IsAiming()
    return self._aiming
end

function NikkiSkillTrigger:GetAimingSkill()
    return self._aiming_skill
end

-- ============================================================
-- 按键触发（客户端处理）
-- ============================================================
function NikkiSkillTrigger:CastKey(key)
    local skill_id = self:GetSkillsForKey(key)
    if not skill_id then
        log.warn("[NikkiSkillTrigger Replica] No skill bound to key '%s'", key)
        return false
    end

    local def = self.inst.replica.nikki_skill and self.inst.replica.nikki_skill:GetSkillDef(skill_id)
    if not def then
        log.debug("[NikkiSkillTrigger Replica] Skill definition not found for skill_id '%s'", skill_id)
        return false
    end

    if def.targeting then
        if def.targeting.mode == "target" then
            if self:IsAiming() then
                self:ExitAiming()
                log.debug("[NikkiSkillTrigger Replica] Skill '%s' exits aiming mode.", skill_id)
            else
                self:EnterAiming(skill_id)
                log.debug("[NikkiSkillTrigger Replica] Skill '%s' enters aiming mode.", skill_id)
            end
            return true
        end
    end

    log.debug("[NikkiSkillTrigger Replica] Casting skill '%s' for key '%s'", skill_id, key)
    SendModRPCToServer(GetModRPC("NikkiFramework", "CastKey"), key)
    return true
end

-- ============================================================
-- 取消瞄准
-- ============================================================
function NikkiSkillTrigger:CancelAiming()
    if not self._aiming then
        return
    end
    self:ExitAiming()
    self.inst:PushEvent("nikki_aiming_cancel")
end

return NikkiSkillTrigger
