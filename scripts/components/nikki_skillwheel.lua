local log = require("utils/log")

local NikkiSkillWheel = Class(function(self, inst)
    self.inst = inst
    -- 核心职责：生成并绑定虚拟施法器
    self.spell_caster = SpawnPrefab("nikki_spell_caster")
    if self.spell_caster then
        self.spell_caster:Attach(inst)
        inst.spell_caster = self.spell_caster
    end
end)

function NikkiSkillWheel:OnRemoveFromEntity()
    if self.spell_caster and self.spell_caster:IsValid() then
        self.spell_caster:Remove()
    end
    self.inst.spell_caster = nil
end

function NikkiSkillWheel:OpenWheel()
    if self.spell_caster and self.spell_caster.components.spellbook then
        self.spell_caster.components.spellbook:OpenSpellBook(self.inst)
        log.debug("[NikkiSkillWheel] OpenWheel called for %s", tostring(self.inst))
    end
end

return NikkiSkillWheel
