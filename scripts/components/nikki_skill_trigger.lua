-- scripts/components/nikki_skill_trigger.lua
local NikkiComponentBase = require("components/nikki_component_base")
local log = require("utils/log")
local NikkiSkillTrigger = Class(NikkiComponentBase, function(self, inst)
    NikkiComponentBase._ctor(self, inst)
    self.key_triggers = {}
    self.action_triggers = {}
    self._active_event_listeners = {}
end)

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

function NikkiSkillTrigger:CastKey(key_code, params)
    local skills = self.key_triggers[key_code]
    if not skills or not self.inst.components.nikki_skill then return false end
    for skill_id, _ in pairs(skills) do
        self.inst.components.nikki_skill:ExecuteTrigger(skill_id, "keys", key_code, params)
    end
    return true
end

function NikkiSkillTrigger:CastAction(action_id, params)
    local skills = self.action_triggers[action_id]
    if not skills or not self.inst.components.nikki_skill then return false end
    for skill_id, _ in pairs(skills) do
        self.inst.components.nikki_skill:ExecuteTrigger(skill_id, "actions", action_id, params)
    end
    return true
end

return NikkiSkillTrigger
