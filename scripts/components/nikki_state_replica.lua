local log = require("utils/log")
local NikkiManager = require("nikki_manager")

local DEFAULT_STATE = "default"

local NikkiStateReplica = Class(function(self, inst)
    self.inst = inst
    self._state = net_string(inst.GUID, "nikki_state._state", "nikki_statedirty")
    self._old_state = net_string(inst.GUID, "nikki_state._old_state")
    self._state:set(DEFAULT_STATE)
    self._old_state:set(DEFAULT_STATE)

    if not TheWorld.ismastersim then
        inst:ListenForEvent("nikki_statedirty", function()
            local current_state = self:GetState()
            local old_state = self._old_state:value()

            self:_RefreshTriggerKeys(current_state, old_state)

            inst:PushEvent("nikki_state_dirty", {
                state = current_state,
                old_state = old_state
            })
        end)
    end
end)

function NikkiStateReplica:SetState(state, old_state)
    self._state:set(state or DEFAULT_STATE)
    self._old_state:set(old_state or DEFAULT_STATE)
end

function NikkiStateReplica:GetState()
    return self._state:value() or DEFAULT_STATE
end

function NikkiStateReplica:_RefreshTriggerKeys(current_state, old_state)
    local trigger_replica = self.inst.replica.nikki_skill_trigger
    if not trigger_replica then return end

    local resolver = NikkiManager.GetInstance():GetResolver("state")

    if old_state then
        local old_def = resolver and resolver:GetDef(old_state)
        if old_def and old_def.keys then
            for key_code, _ in pairs(old_def.keys) do
                trigger_replica:RemoveKey(key_code)
            end
        end
    end

    if current_state then
        local state_def = resolver and resolver:GetDef(current_state)
        if state_def and state_def.keys then
            for key_code, skill_id in pairs(state_def.keys) do
                trigger_replica:AddKey(key_code, skill_id)
            end
        end
    end
end

function NikkiStateReplica:GetBadges()
    local resolver = NikkiManager.GetInstance():GetResolver("state")
    local def = resolver and resolver:GetDef(self:GetState())
    return def and def.badges or nil
end

function NikkiStateReplica:GetSkills()
    local resolver = NikkiManager.GetInstance():GetResolver("state")
    local def = resolver and resolver:GetDef(self:GetState())
    return def and def.skills or {}
end

return NikkiStateReplica
