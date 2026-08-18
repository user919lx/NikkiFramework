-- scripts/resolvers/skill_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")

local SG_STATE_MAP = {
    ["book"] = { "book" },
    ["castspellmind"] = { "willow_ember" },
    ["remotecast_pre"] = { "remotecontrol" },
    ["commune_with_abigail"] = { "abigail_flower" },
    ["slingshot_special"] = { "slingshot" },
    ["combat_lunge_start"] = { "aoeweapon_lunge" },
    ["combat_leap_start"] = { "aoeweapon_leap" },
    ["combat_superjump_start"] = { "aoeweapon_leap", "superjump" },
    ["parry_pre"] = { "parryweapon" },
    ["blowdart_special"] = { "blowdart" },
    ["throw_line"] = { "throw_line" },
    ["castspell"] = {},
}

local function GetCasterOwner(inst)
    local parent = inst.entity:GetParent()
    if parent and parent:IsValid() then return parent end
    if inst.components.inventoryitem and inst.components.inventoryitem:GetGrandOwner() then
        return inst.components.inventoryitem:GetGrandOwner()
    end
    return not TheWorld.ismastersim and ThePlayer or nil
end

local SkillResolver = Class(BaseResolver, function(self, defs)
    self._resolver_type = "skill"
    self.compiled_wheels = {}
    BaseResolver._ctor(self, defs)
end)

-- ============================================================
-- 技能定义添加钩子（编译时）
-- 注意：default_triggers 和 toggle 已在 manager 层预处理并删除
--       这里只处理 wheel 编译
-- ============================================================
function SkillResolver:OnDefAdded(skill_id, def)
    -- Wheel 编译
    if type(def.wheel) == "table" and type(def.wheel.ui) == "table" then
        local w_def = def.wheel
        local ui = w_def.ui
        local aoe = w_def.aoe or {}

        local anim_cfg = ui.anim or (ui.bank and ui)
        local image_cfg = ui.image or (ui.atlas and ui)
        local is_anim = anim_cfg ~= nil and (anim_cfg.bank or anim_cfg.build or anim_cfg.anims)

        local checkcooldown_fn = nil
        local checkenabled_fn = nil

        if is_anim then
            checkcooldown_fn = function(owner)
                if owner and owner.components.spellbookcooldowns then
                    return owner.components.spellbookcooldowns:GetSpellCooldownPercent(skill_id)
                end
                return nil
            end
            checkenabled_fn = ui.checkenabled
        else
            local user_checkenabled = ui.checkenabled
            checkenabled_fn = function(owner)
                if owner and owner.components.spellbookcooldowns and owner.components.spellbookcooldowns:IsInCooldown(skill_id) then
                    return false
                end
                if user_checkenabled then
                    return user_checkenabled(owner)
                end
                return true
            end
        end

        self.compiled_wheels[skill_id] = {
            id = skill_id,
            name = def.name or skill_id,
            instant = w_def.instant == true,
            is_anim = is_anim,
            anim_cfg = is_anim and anim_cfg or nil,
            image_cfg = (not is_anim) and image_cfg or nil,
            checkcooldown = checkcooldown_fn,
            checkenabled = checkenabled_fn,
            widget_scale = ui.widget_scale or 0.6,
            hit_radius = ui.hit_radius or (not is_anim and 50 or nil),
            clicksound = ui.clicksound,
            spacer = ui.spacer,
            nestedwheel = ui.nestedwheel,
            helptext = ui.helptext,
            aoe = aoe,
            state = aoe.state,
            allow_water = aoe.allow_water,
            deploy_radius = aoe.deploy_radius,
            target_fx = aoe.target_fx,
            should_repeat_cast_fn = aoe.should_repeat_cast_fn,
            reticule = aoe.reticule,
        }
    end
end

-- ============================================================
-- 纯查询接口
-- ============================================================

function SkillResolver:IsWheelSkill(skill_id)
    return self.compiled_wheels ~= nil and self.compiled_wheels[skill_id] ~= nil
end

function SkillResolver:BuildWheelItem(skill_id, user, order)
    local compiled = self.compiled_wheels and self.compiled_wheels[skill_id]
    if not compiled then return nil end

    local is_aoe = (compiled.aoe ~= nil and next(compiled.aoe) ~= nil)
    local is_instant = compiled.instant

    local item = {
        label = self:GetDisplayName(skill_id),
        id = skill_id,
        checkenabled = compiled.checkenabled,
        checkcooldown = compiled.checkcooldown,
        widget_scale = compiled.widget_scale,
        hit_radius = compiled.hit_radius,
        clicksound = compiled.clicksound,
        spacer = compiled.spacer,
        nestedwheel = compiled.nestedwheel,
        helptext = compiled.helptext,
        order = order or 1,
    }

    if compiled.is_anim then
        local a = compiled.anim_cfg
        item.bank = a.bank
        item.build = a.build
        item.anims = a.anims
        item.cooldowncolor = a.cooldowncolor or { 0.65, 0.65, 0.65, 0.75 }
    else
        local img = compiled.image_cfg
        item.atlas = img.atlas
        item.normal = img.normal
        item.focus = img.focus
        item.disabled = img.disabled
        item.down = img.down
        item.selected = img.selected
    end

    item.execute = function(spell_caster)
        local doer = GetCasterOwner(spell_caster)
        if not doer then return end

        if is_aoe then
            if doer.components.playercontroller then
                return doer.components.playercontroller:StartAOETargetingUsing(spell_caster)
            end
        elseif is_instant then
            if doer.replica.nikki_skill_trigger then
                return doer.replica.nikki_skill_trigger:CastSkill(skill_id)
            end
        else
            if doer.replica.inventory then
                return doer.replica.inventory:CastSpellBookFromInv(spell_caster)
            end
        end
    end

    item.onselect = function(spell_caster)
        if spell_caster.components.spellbook then
            spell_caster.components.spellbook:SetSpellName(item.label)
        end

        if is_aoe then
            for _, tags in pairs(SG_STATE_MAP) do
                for _, tag in ipairs(tags) do
                    spell_caster:RemoveTag(tag)
                end
            end
            if compiled.state and SG_STATE_MAP[compiled.state] then
                for _, tag in ipairs(SG_STATE_MAP[compiled.state]) do
                    spell_caster:AddTag(tag)
                end
            end

            if spell_caster.components.aoetargeting then
                spell_caster.components.aoetargeting:SetAllowWater(compiled.allow_water or false)
                spell_caster.components.aoetargeting:SetDeployRadius(compiled.deploy_radius or 0)

                local native_reticule = spell_caster.components.aoetargeting.reticule
                if native_reticule then
                    native_reticule.targetfn = nil
                    native_reticule.mousetargetfn = nil
                    native_reticule.updatepositionfn = nil
                    native_reticule.validcolour = { 1, .75, 0, 1 }
                    native_reticule.invalidcolour = { .5, 0, 0, 1 }
                    native_reticule.ease = true
                    native_reticule.mouseenabled = true
                    native_reticule.twinstickmode = 1
                    native_reticule.twinstickrange = 8

                    if compiled.reticule then
                        for k, v in pairs(compiled.reticule) do
                            native_reticule[k] = v
                        end
                    end
                end
                spell_caster.components.aoetargeting:SetShouldRepeatCastFn(compiled.should_repeat_cast_fn)
            end
        end

        if TheWorld.ismastersim then
            if is_aoe then
                spell_caster.components.aoetargeting:SetTargetFX(compiled.target_fx or nil)
                spell_caster.components.spellbook:SetSpellFn(nil)
                spell_caster.components.aoespell:SetSpellFn(function(caster_inst, doer, pos)
                    local params = { pos = pos }
                    if doer.components.nikki_skill then
                        return doer.components.nikki_skill:CastSkill(skill_id, params)
                    end
                end)
            elseif not is_instant then
                spell_caster.components.aoespell:SetSpellFn(nil)
                spell_caster.components.spellbook:SetSpellFn(function(caster_inst, doer)
                    if doer.components.nikki_skill then
                        return doer.components.nikki_skill:CastSkill(skill_id)
                    end
                end)
            end
        end
    end
    return item
end

function SkillResolver:GetSkillRange(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.range or nil
end

function SkillResolver:GetSkillCooldown(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.cd or 0
end

function SkillResolver:NeedsServer(skill_id)
    local def = self:GetDef(skill_id)
    if def then
        if def.client_only then return false end
        if type(def.fn) == "function" then return true end
    end
    return false
end

return SkillResolver