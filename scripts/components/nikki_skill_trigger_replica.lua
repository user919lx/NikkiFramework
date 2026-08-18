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
        self:_RefreshKeys(data and data.state)
    end)

    -- 延迟执行初始刷新，传入 basic 状态
    self.inst:DoTaskInTime(0, function()
        local resolver = GetStateResolver()
        if resolver then
            local basic_state = resolver:GetBasicState()
            self:_RefreshKeys(basic_state)
        end
    end)
end)

-- ============================================================
-- 刷新 keys 绑定（支持 state 覆盖，但内部有 fallback）
-- ============================================================
function NikkiSkillTrigger:_RefreshKeys(state_override)
    local resolver = GetStateResolver()
    if not resolver then
        return
    end

    local state_name = state_override

    -- 若未传入，则从组件获取当前状态
    if not state_name then
        local state_comp = self.inst.components.nikki_state
        if state_comp then
            state_name = state_comp:GetState()
        end
    end

    if not state_name then
        log.debug("[NikkiSkillTrigger Replica] No state available to refresh keys.")
        return
    end

    local state_def = resolver:GetStateDef(state_name)
    if not state_def then
        log.debug("[NikkiSkillTrigger Replica] State definition not found for '%s'", state_name)
        return
    end

    if state_def.keys and next(state_def.keys) then
        for key_code, skill_id in pairs(state_def.keys) do
            self._keys[key_code] = skill_id
        end
    end

    log.debug("[NikkiSkillTrigger Replica] Refreshed keys for state '%s' (override=%s)", state_name, tostring(state_override))
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