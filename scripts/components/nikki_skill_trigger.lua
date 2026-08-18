-- scripts/components/nikki_skill_trigger.lua
local log = require("utils/log")

local function GetStateResolver()
    if NikkiManager then
        return NikkiManager:GetStateResolver()
    end
    return nil
end

local NikkiSkillTrigger = Class(function(self, inst)
    self.inst = inst

    self.triggers = {
        keys = {},
        actions = {},
        events = {},
    }

    -- 监听状态变化，刷新 keys
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

-- ============================================================
-- 添加触发器绑定
-- ============================================================
function NikkiSkillTrigger:Add(trigger_type, trigger_key, skill_id)
    if type(trigger_type) ~= "string" then
        log.warn("[NikkiSkillTrigger] Add: trigger_type must be string, got %s", tostring(trigger_type))
        return false
    end

    if not self.triggers[trigger_type] then
        log.warn("[NikkiSkillTrigger] Add: unknown trigger_type '%s'", trigger_type)
        return false
    end

    if skill_id == nil or type(skill_id) ~= "string" or skill_id == "" then
        log.warn("[NikkiSkillTrigger] Add: skill_id must be non-empty string, got %s", tostring(skill_id))
        return false
    end

    if trigger_type == "keys" then
        self.triggers.keys[trigger_key] = skill_id
        log.debug("[NikkiSkillTrigger] Added key trigger: key_code=%s, skill_id=%s", tostring(trigger_key),
            tostring(skill_id))
    else
        if not self.triggers[trigger_type][trigger_key] then
            self.triggers[trigger_type][trigger_key] = {}
        end
        self.triggers[trigger_type][trigger_key][skill_id] = true
    end

    return true
end

-- ============================================================
-- 移除触发器绑定
-- ============================================================
function NikkiSkillTrigger:Remove(trigger_type, trigger_key, skill_id)
    if type(trigger_type) ~= "string" then
        log.warn("[NikkiSkillTrigger] Remove: trigger_type must be string, got %s", tostring(trigger_type))
        return false
    end

    if not self.triggers[trigger_type] then
        log.warn("[NikkiSkillTrigger] Remove: unknown trigger_type '%s'", trigger_type)
        return false
    end

    if trigger_type == "keys" then
        self.triggers.keys[trigger_key] = nil
        log.debug("[NikkiSkillTrigger] Removed key trigger: key_code=%s", tostring(trigger_key))
        return true
    end

    local skill_set = self.triggers[trigger_type][trigger_key]
    if not skill_set then
        return false
    end

    if skill_id then
        if type(skill_id) ~= "string" then
            log.warn("[NikkiSkillTrigger] Remove: skill_id must be string, got %s", tostring(skill_id))
            return false
        end
        skill_set[skill_id] = nil
        if next(skill_set) == nil then
            self.triggers[trigger_type][trigger_key] = nil
        end
    else
        self.triggers[trigger_type][trigger_key] = nil
    end

    return true
end

-- ============================================================
-- 清空所有触发器
-- ============================================================
function NikkiSkillTrigger:Clear()
    self.triggers = { keys = {}, actions = {}, events = {} }
end

-- ============================================================
-- 刷新 keys 绑定（支持 state 覆盖，但内部有 fallback）
-- ============================================================
function NikkiSkillTrigger:_RefreshKeys(current_state, old_state)
    local resolver = GetStateResolver()
    if not resolver then
        return
    end

    -- 若未传入当前状态，则从组件获取
    if not current_state then
        local state_comp = self.inst.components.nikki_state
        if state_comp then
            current_state = state_comp:GetState()
        end
    end
    if not current_state then
        log.debug("[NikkiSkillTrigger] No state available to refresh keys.")
        return
    end

    -- 处理旧状态：移除旧状态的按键绑定
    if old_state then
        local old_def = resolver:GetStateDef(old_state)
        if old_def and old_def.keys then
            for key_code, skill_id in pairs(old_def.keys) do
                self:Remove("keys", key_code, skill_id)
            end
            log.debug("[NikkiSkillTrigger] Removed keys for old state '%s'", old_state)
        end
    end

    -- 处理新状态：添加新状态的按键绑定
    local state_def = resolver:GetStateDef(current_state)
    if not state_def then
        log.debug("[NikkiSkillTrigger] State definition not found for '%s'", current_state)
        return
    end

    if state_def.keys then
        for key_code, skill_id in pairs(state_def.keys) do
            self:Add("keys", key_code, skill_id)
        end
    end

    log.debug("[NikkiSkillTrigger] Refreshed keys for state '%s' (old_state=%s)", current_state, tostring(old_state))
end

-- ============================================================
-- 统一触发接口
-- ============================================================
function NikkiSkillTrigger:Trigger(trigger_type, trigger_key, params)
    if type(trigger_type) ~= "string" then
        log.warn("[NikkiSkillTrigger] Trigger: trigger_type must be string, got %s", tostring(trigger_type))
        return false
    end

    params = params or {}
    local skill_comp = self.inst.components.nikki_skill
    if not skill_comp then
        return false
    end

    if trigger_type == "cast" then
        if not trigger_key or type(trigger_key) ~= "string" then
            log.warn("[NikkiSkillTrigger] Trigger(cast): skill_id must be non-empty string, got %s",
                tostring(trigger_key))
            return false
        end
        return skill_comp:Execute(trigger_key, params)
    end

    if trigger_type == "keys" then
        local skill_id = self.triggers.keys[trigger_key]
        if not skill_id then
            log.debug("[NikkiSkillTrigger] Trigger(keys): No skill bound to key '%s'", tostring(trigger_key))
            return false
        end
        log.debug("[NikkiSkillTrigger] Trigger(keys): Executing skill '%s' for key '%s'", skill_id, tostring(trigger_key))
        return skill_comp:Execute(skill_id, params)
    end

    local skill_set = self.triggers[trigger_type] and self.triggers[trigger_type][trigger_key]
    if not skill_set or next(skill_set) == nil then
        return false
    end

    local any_success = false
    local last_error = nil

    for skill_id, _ in pairs(skill_set) do
        local success, err = skill_comp:Execute(skill_id, params)
        if success then
            any_success = true
        else
            last_error = err or "EXECUTION_FAILED"
        end
    end

    return any_success, last_error
end

return NikkiSkillTrigger
