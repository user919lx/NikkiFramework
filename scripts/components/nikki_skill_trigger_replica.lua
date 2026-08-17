local NikkiSkillTrigger = Class(function(self, inst)
    self.inst = inst
end)

function NikkiSkillTrigger:CastKey(key_code)
    if self.inst.components.nikki_skill_trigger then
        self.inst.components.nikki_skill_trigger:CastKey(key_code)
    else
        SendModRPCToServer(GetModRPC("NikkiFramework", "CastKey"), key_code)
    end
end

return NikkiSkillTrigger
