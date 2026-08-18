-- scripts/components/nikki_skill_trigger_replica.lua
local log = require("utils/log")

local function GetStateResolver()
    if NikkiManager then
        return NikkiManager:GetStateResolver()
    end
    return nil
end

local NikkiSkillTrigger = Class(function(self, inst)
    self.inst = inst

    -- 按键映射缓存（客户端）
    self._keys = {}

    -- 瞄准状态（客户端）
    self._aiming = false
    self._aiming_skill = nil
    self._aiming_params = nil

    self.inst:ListenForEvent("nikki_state_dirty", function(inst, data)
        local state = data and data.state
        local old_state = data and data.old_state
        self:_RefreshKeys(state, old_state)
    end)

    -- 延迟执行初始刷新，传入 basic 状态
    self.inst:DoTaskInTime(0, function()
        local resolver = GetStateResolver()
        if resolver then
            local basic_state = resolver:GetBasicState()
            self:_RefreshKeys(basic_state, nil)
        end
    end)
end)

function NikkiSkillTrigger:AddKey(key_code, skill_id)
    self._keys[key_code] = skill_id
end

function NikkiSkillTrigger:RemoveKey(key_code)
    self._keys[key_code] = nil
end

function NikkiSkillTrigger:_RefreshKeys(current_state, old_state)
    local resolver = GetStateResolver()
    if not resolver then
        return
    end

    if not current_state then
        local state_comp = self.inst.components.nikki_state
        if state_comp then
            current_state = state_comp:GetState()
        end
    end
    if not current_state then
        log.debug("[NikkiSkillTrigger Replica] No state available to refresh keys.")
        return
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

    log.debug("[NikkiSkillTrigger Replica] Refreshed keys for state '%s' (old_state=%s)", current_state, tostring(old_state))
end

-- ============================================================
-- 客户端：根据按键获取技能 ID
-- ============================================================
function NikkiSkillTrigger:GetSkillsForKey(key_code)
    return self._keys[key_code]
end

-- ============================================================
-- 瞄准状态管理（客户端）
-- ============================================================
function NikkiSkillTrigger:EnterAiming(skill_id)
    self._aiming = true
    self._aiming_skill = skill_id
    self.inst:AddTag("aiming_point")
    log.debug("[NikkiSkillTrigger Replica] Enter aiming for skill: %s", skill_id)
end

function NikkiSkillTrigger:ExitAiming()
    self._aiming = false
    self._aiming_skill = nil
    self.inst:RemoveTag("aiming_point")
    log.debug("[NikkiSkillTrigger Replica] Exit aiming")
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
        return false
    end

    local resolver = NikkiManager:GetSkillResolver()
    if not resolver then
        return false
    end

    local def = resolver:GetDef(skill_id)
    if not def then
        return false
    end

    -- 检查是否需要瞄准
    if def.targeting and def.targeting.mode == "point" then
        self:EnterAiming(skill_id)
        self.inst:PushEvent("nikki_aiming_start", { skill_id = skill_id })
        return true
    end

    -- 瞬发：发送 RPC 到服务端
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