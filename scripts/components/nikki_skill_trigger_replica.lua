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
    if self.inst.components.nikki_skill_trigger then
        self.inst.components.nikki_skill_trigger:CastKey(key_code)
    else
        SendModRPCToServer(GetModRPC("NikkiFramework", "CastKey"), key_code)
    end
end


return NikkiSkillTrigger
