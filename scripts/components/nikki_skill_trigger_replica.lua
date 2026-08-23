local log = require("utils/log")

local NikkiSkillTrigger = Class(function(self, inst)
    self.inst = inst
    self._keys = {}
end)

function NikkiSkillTrigger:AddKey(key_code, skill_id)
    self._keys[key_code] = skill_id
end

function NikkiSkillTrigger:RemoveKey(key_code)
    self._keys[key_code] = nil
end

function NikkiSkillTrigger:GetSkillsForKey(key_code)
    return self._keys[key_code]
end

function NikkiSkillTrigger:CastKey(key)
    if self.inst.components.nikki_skill_trigger then
        return self.inst.components.nikki_skill_trigger:Trigger("keys", key)
    end

    local skill_id = self:GetSkillsForKey(key)
    if not skill_id then return false end

    local caster = self.inst.components.nikki_skill_caster
    if caster then
        return caster:TryExecute(skill_id, {})
    end
    return false
end

return NikkiSkillTrigger
