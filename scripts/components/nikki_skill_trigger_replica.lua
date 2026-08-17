local NikkiSkillTrigger = Class(function(self, inst)
    self.inst = inst
end)

function NikkiSkillTrigger:CastKey(key)
    if self.inst.components.nikki_skill_trigger then
        self.inst.components.nikki_skill_trigger:Trigger("keys", key)
    else
        SendModRPCToServer(GetModRPC("NikkiFramework", "CastKey"), key)
    end
end

return NikkiSkillTrigger
