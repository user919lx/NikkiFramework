local log = require("utils/log")
log.set_level("debug")

local NikkiSkillWheelReplica = Class(function(self, inst)
    self.inst = inst
end)

-- 客户端调用：打开轮盘 UI
function NikkiSkillWheelReplica:OpenWheel()
    local caster = self.inst.spell_caster
    if caster and caster.components.spellbook then
        caster.components.spellbook:OpenSpellBook(self.inst)
        log.debug("[NikkiSkillWheelReplica] OpenWheel called for %s", tostring(self.inst))
    end
    return false
end

return NikkiSkillWheelReplica