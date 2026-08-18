local log = require("utils/log")

local function GetStateResolver()
    if NikkiManager then
        return NikkiManager:GetStateResolver()
    end
    return nil
end

local DEFAULT_STATE = "default"

local NikkiStateReplica = Class(function(self, inst)
    self.inst = inst
    self._state = net_string(inst.GUID, "nikki_state._state", "nikki_statedirty")
    self._state:set(DEFAULT_STATE)

    if not TheWorld.ismastersim then
        inst:ListenForEvent("nikki_statedirty", function()
            inst:PushEvent("nikki_state_dirty", { state = self:GetState() })
        end)
    end
end)

function NikkiStateReplica:SetState(state)
    self._state:set(state or DEFAULT_STATE)
end

function NikkiStateReplica:GetState()
    return self._state:value() or DEFAULT_STATE
end

function NikkiStateReplica:GetBadges()
    local resolver = GetStateResolver()
    if resolver then
        return resolver:GetBadges(self:GetState())
    end
    return nil
end

function NikkiStateReplica:GetSkills()
    local resolver = GetStateResolver()
    if resolver then
        return resolver:GetSkills(self:GetState())
    end
    return {}
end

return NikkiStateReplica
