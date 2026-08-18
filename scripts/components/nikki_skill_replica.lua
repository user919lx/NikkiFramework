local NikkiSkill = Class(function(self, inst)
    self.inst = inst
    self._max_range = net_float(inst.GUID, "skill._max_range", "skill_maxrangedirty")
    self._max_range:set(0)
    self._resolver = nil
    if not TheWorld.ismastersim then
        inst:ListenForEvent("skill_maxrangedirty", function()
            inst:PushEvent("skill_max_range_dirty", { max_range = self:GetMaxRange() })
        end)
    end
end)

function NikkiSkill:SetMaxRange(range)
    self._max_range:set(range or 0)
end

function NikkiSkill:GetMaxRange()
    if self.inst.components.nikki_skill ~= nil then
        return self.inst.components.nikki_skill.max_range
    else
        return self._max_range:value()
    end
end

function NikkiSkill:GetSkillDef(id)
    if self._resolver then
        return self._resolver:GetDef(id)
    end
end
function NikkiSkill:GetSkillRange(id)
    if self._resolver then
        return self._resolver:GetSkillRange(id)
    end
end
function NikkiSkill:GetSkillName(id)
    if self._resolver then
        return self._resolver:GetDisplayName(id)
    end
end

return NikkiSkill
