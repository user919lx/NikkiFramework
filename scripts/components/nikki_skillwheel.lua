local NikkiSkillWheel = Class(function(self, inst)
    self.inst = inst
    -- 核心职责：生成并绑定虚拟施法器
    self.spell_caster = SpawnPrefab("nikki_spell_caster")
    if self.spell_caster then
        self.spell_caster:Attach(inst)
        -- 依然暴露在 inst.spell_caster，保证你原先按键调用不会报错
        inst.spell_caster = self.spell_caster
    end
end)

-- 当组件或玩家实体被移除时，安全销毁虚拟物品，防止内存泄漏
function NikkiSkillWheel:OnRemoveFromEntity()
    if self.spell_caster and self.spell_caster:IsValid() then
        self.spell_caster:Remove()
    end
    self.inst.spell_caster = nil
end

-- 可选：给外部提供一个干净的开轮盘接口
function NikkiSkillWheel:OpenWheel()
    if self.spell_caster and self.spell_caster.components.spellbook then
        self.spell_caster.components.spellbook:OpenSpellBook(self.inst)
    end
end

return NikkiSkillWheel