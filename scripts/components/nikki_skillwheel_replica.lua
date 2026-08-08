-- scripts/components/nikki_skillwheel_replica.lua
local ResolverRegistry = require("nikki_resolver_registry")
local ResourceAdapter = require("utils/resource_adapter")
local log = require("utils/log")

local ANIM_TAGS = {
    "book", "willow_ember", "remotecontrol", "abigail_flower",
    "slingshot", "aoeweapon_lunge", "aoeweapon_leap",
    "superjump", "parryweapon", "blowdart", "throw_line"
}

local function GetCasterOwner(inst)
    local parent = inst.entity:GetParent()
    if parent and parent:IsValid() then return parent end
    if inst.components.inventoryitem and inst.components.inventoryitem:GetGrandOwner() then
        return inst.components.inventoryitem:GetGrandOwner()
    end
    return not TheWorld.ismastersim and ThePlayer or nil
end

local NikkiSkillWheel = Class(function(self, inst)
    self.inst = inst
end)

function NikkiSkillWheel:GetWheelItems()
    local user = self.inst
    local resolvers = ResolverRegistry.Get(user.prefab)
    if not resolvers or not resolvers.skill then return {} end

    local items = {}
    local order = 1

    local target_skill_ids = {}
    if user.replica and user.replica.nikki_state then
        target_skill_ids = user.replica.nikki_state:GetSkills()
    end

    for _, skill_id in ipairs(target_skill_ids) do
        local wheel_data = resolvers.skill:GetSkillWheel(skill_id)
        if wheel_data then
            local can_show = resolvers.skill:CheckRequiredTags(user, skill_id, nil, nil)
            if can_show then
                local ui_def = wheel_data.ui
                local reticule_def = wheel_data.reticule

                local is_aoe = (reticule_def ~= nil)
                local is_instant = (wheel_data.instant == true)

                -- ===================================================
                -- 自动装配：自动对接官方 CD 查表
                -- ===================================================
                local checkcooldown_fn = ui_def.checkcooldown or function(owner)
                    -- 使用官方组件进行 CD UI 百分比读取 (Client Safe)
                    if owner and owner.components.spellbookcooldowns then
                        return owner.components.spellbookcooldowns:GetSpellCooldownPercent(skill_id)
                    end
                    return nil
                end

                local item = {
                    label = wheel_data.name,
                    id = wheel_data.id,
                    atlas = ui_def.atlas,
                    normal = ui_def.normal,
                    bank = ui_def.bank,
                    build = ui_def.build,
                    anims = ui_def.anims,

                    checkcooldown = checkcooldown_fn,
                    checkenabled = ui_def.checkenabled,
                    cooldowncolor = ui_def.cooldowncolor or { 0.65, 0.65, 0.65, 0.75 },

                    widget_scale = ui_def.widget_scale or 0.6,
                    hit_radius = (ui_def.anims == nil) and (ui_def.hit_radius or 50) or nil,
                    order = order,
                }
                order = order + 1

                item.execute = function(spell_inst)
                    local doer = GetCasterOwner(spell_inst)
                    if not doer then return end

                    if is_aoe then
                        if doer.components.playercontroller then
                            return doer.components.playercontroller:StartAOETargetingUsing(spell_inst)
                        end
                    elseif is_instant then
                        if doer.replica.nikki_skill_trigger then
                            return doer.replica.nikki_skill_trigger:CastSkill(skill_id)
                        end
                    else
                        if doer.replica.inventory then
                            return doer.replica.inventory:CastSpellBookFromInv(spell_inst)
                        end
                    end
                end

                item.onselect = function(spell_inst)
                    for _, tag in ipairs(ANIM_TAGS) do
                        spell_inst:RemoveTag(tag)
                    end
                    if ui_def.anim_tag then
                        spell_inst:AddTag(ui_def.anim_tag)
                    end

                    if spell_inst.components.spellbook then
                        spell_inst.components.spellbook:SetSpellName(item.label)
                        spell_inst.components.spellbook:SetSpellAction(ui_def.spell_action or nil)
                    end

                    if is_aoe and spell_inst.components.aoetargeting then
                        spell_inst.components.aoetargeting:SetAllowWater(ui_def.allow_water or false)
                        spell_inst.components.aoetargeting:SetDeployRadius(ui_def.deploy_radius or 0)

                        local reticule = spell_inst.components.aoetargeting.reticule
                        if reticule then
                            reticule.targetfn = nil
                            reticule.mousetargetfn = nil
                            reticule.updatepositionfn = nil
                            reticule.validcolour = { 1, .75, 0, 1 }
                            reticule.invalidcolour = { .5, 0, 0, 1 }
                            reticule.ease = true
                            reticule.mouseenabled = true
                            reticule.twinstickmode = 1
                            reticule.twinstickrange = 8

                            if reticule_def then
                                for k, v in pairs(reticule_def) do
                                    reticule[k] = v
                                end
                            end
                        end
                        spell_inst.components.aoetargeting:SetShouldRepeatCastFn(ui_def.should_repeat_cast_fn)
                    end

                    if TheWorld.ismastersim then
                        if is_aoe then
                            spell_inst.components.aoetargeting:SetTargetFX(ui_def.target_fx or nil)
                            spell_inst.components.spellbook:SetSpellFn(nil)
                            spell_inst.components.aoespell:SetSpellFn(function(caster_inst, doer, pos)
                                local params = { pos = pos }
                                if doer.components.nikki_skill then
                                    return doer.components.nikki_skill:CastSkill(skill_id, params)
                                end
                            end)
                        elseif not is_instant then
                            spell_inst.components.aoespell:SetSpellFn(nil)
                            spell_inst.components.spellbook:SetSpellFn(function(caster_inst, doer)
                                if doer.components.nikki_skill then
                                    return doer.components.nikki_skill:CastSkill(skill_id)
                                end
                            end)
                        end
                    end
                end

                table.insert(items, item)
            end
        end
    end
    return items
end

function NikkiSkillWheel:OpenWheel()
    local inst = self.inst
    if inst.components.nikki_skillwheel then
        inst.components.nikki_skillwheel:OpenWheel()
    else
        local caster = inst.spell_caster
        if caster and caster.components.spellbook then
            caster.components.spellbook:OpenSpellBook(inst)
        end
    end
    return false
end

return NikkiSkillWheel
