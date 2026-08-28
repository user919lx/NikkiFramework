local log = require("utils/log")

local NikkiSkillTrigger = Class(function(self, inst)
    self.inst = inst
    self.triggers = {
        keys = {},
        actions = {},
        events = {},
    }
end)

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

function NikkiSkillTrigger:Clear()
    self.triggers = { keys = {}, actions = {}, events = {} }
end

function NikkiSkillTrigger:Trigger(trigger_type, trigger_key, params)
    if type(trigger_type) ~= "string" then
        log.warn("[NikkiSkillTrigger] Trigger: trigger_type must be string, got %s", tostring(trigger_type))
        return false
    end

    params = params or {}
    local skill_comp = self.inst.components.nikki_skill_caster
    if not skill_comp then
        return false
    end

    -- 主动按键/快捷施法
    local skill_id = nil
    if trigger_type == "cast" then
        skill_id = trigger_key
    elseif trigger_type == "keys" then
        skill_id = self.triggers.keys[trigger_key]
    end
    if skill_id then
        return skill_comp:TryExecute(skill_id, params)
    end

    -- 被动触发
    local skill_set = self.triggers[trigger_type] and self.triggers[trigger_type][trigger_key]
    if not skill_set or next(skill_set) == nil then
        return false
    end

    local any_success = false
    local last_error = nil

    for sid, _ in pairs(skill_set) do
        local success, err = skill_comp:Execute(sid, params)
        if success then
            any_success = true
        else
            last_error = err or "EXECUTION_FAILED"
        end
    end
    return any_success, last_error
end

return NikkiSkillTrigger
