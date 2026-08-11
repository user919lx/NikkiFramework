-- scripts/resolvers/skill_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")
local ResourceAdapter = require("utils/resource_adapter")

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
    self.compiled_wheels = {}
    self.child_skill_ids = {}
    BaseResolver._ctor(self, defs)
end)

-- 预编译
function SkillResolver:OnDefAdded(skill_id, def)
    -- 语法糖处理
    if def.default_triggers then
        for t_type, t_dict in pairs(def.default_triggers) do
            for k, v in pairs(t_dict) do
                if type(v) == "function" then
                    t_dict[k] = { fn = v }
                end
            end
        end
    end
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

function SkillResolver:IsWheelSkill(skill_id)
    return self.compiled_wheels ~= nil and self.compiled_wheels[skill_id] ~= nil
end

function SkillResolver:BuildWheelItem(skill_id, user, order)
    local compiled = self.compiled_wheels and self.compiled_wheels[skill_id]
    if not compiled then return nil end

    local is_aoe = (compiled.aoe ~= nil and next(compiled.aoe) ~= nil)
    local is_instant = compiled.instant

    local item = {
        label = compiled.name,
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

function SkillResolver:GetSkillDef(id) return self:GetDef(id) end

function SkillResolver:GetAllSkillIds() return self:GetAllIds() end

function SkillResolver:GetSkillName(skill_id) return self:GetDef(skill_id) and self:GetDef(skill_id).name or skill_id end

function SkillResolver:GetSkillRange(skill_id) return self:GetDef(skill_id) and self:GetDef(skill_id).range or nil end

function SkillResolver:GetSkillCooldown(skill_id, trigger_type, trigger_key)
    local def = self:GetDef(skill_id)
    if not def then return 0 end
    local ctx = {}
    if trigger_type and trigger_key and def.default_triggers and def.default_triggers[trigger_type] then
        local specific = def.default_triggers[trigger_type][trigger_key]
        if type(specific) == "table" then ctx = specific end
    end
    -- 如果有独立的子 fn，则不继承父级冷却
    local is_custom_fn = (ctx.fn ~= nil)
    if is_custom_fn then
        return ctx.cd or 0
    end
    return ctx.cd or def.cd or 0
end

function SkillResolver:NeedsServer(skill_id)
    local def = self:GetDef(skill_id)
    if def then
        if def.client_only then return false end
        if type(def.fn) == "function" then return true end
    end
    return false
end

function SkillResolver:CheckRequiredTags(inst, skill_id, trigger_type, trigger_key)
    local def = self:GetDef(skill_id)
    if not def then return false end

    local ctx = {}
    if trigger_type and trigger_key and def.default_triggers and def.default_triggers[trigger_type] then
        local specific = def.default_triggers[trigger_type][trigger_key]
        if type(specific) == "table" then ctx = specific end
    end

    -- 如果有独立的子 fn，则不继承父级的通行证标签
    local is_custom_fn = (ctx.fn ~= nil)
    local req_tags = ctx.required_tags
    if not is_custom_fn and req_tags == nil then
        req_tags = def.required_tags
    end

    if req_tags then
        for _, tag in ipairs(req_tags) do
            if not inst:HasTag(tag) then
                return false
            end
        end
    end
    return true
end

function SkillResolver:OnSkillAdd(inst, skill_id)
    local def = self:GetDef(skill_id)
    if not def then return end

    -- 自动赋予技能声明的能力通行证 Tag
    if def.tags then
        for _, tag in ipairs(def.tags) do
            inst:AddTag(tag)
        end
    end

    if type(def.on_add) == "function" then
        pcall(def.on_add, inst, def)
    end
end

function SkillResolver:OnSkillRemove(inst, skill_id)
    local def = self:GetDef(skill_id)
    if not def then return end

    -- 自动剥夺技能声明的能力通行证 Tag
    if def.tags then
        for _, tag in ipairs(def.tags) do
            inst:RemoveTag(tag)
        end
    end

    if type(def.on_remove) == "function" then
        pcall(def.on_remove, inst, def)
    end
end

function SkillResolver:ExecuteClientFn(inst, skill_id, params)
    local def = self:GetDef(skill_id)
    if not def then return false, "NOT_FOUND" end
    if type(def.client_fn) == "function" then
        local success, result, err = pcall(def.client_fn, inst, params, def)
        if not success then
            local full_stack = debug.traceback(result, 2)
            for line in full_stack:gmatch("[^\n]+") do
                log.error("[SkillResolver] client_fn crash in '%s': %s", skill_id, line)
            end
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            return false, err or "EXECUTION_REJECTED"
        end
        return true
    end
    return true
end

function SkillResolver:ExecuteServerTrigger(inst, skill_id, trigger_type, trigger_key, params)
    local def = self:GetDef(skill_id)
    if not def then return false, "NOT_FOUND" end

    if not self:CheckRequiredTags(inst, skill_id, trigger_type, trigger_key) then
        return false, "MISSING_TAG"
    end

    local ctx = {}
    if def.default_triggers and def.default_triggers[trigger_type] then
        local specific = def.default_triggers[trigger_type][trigger_key]
        if type(specific) == "table" then ctx = specific end
    end

    -- 判定是否为独立的子功能
    local is_custom_fn = (ctx.fn ~= nil)
    local fn = ctx.fn or def.fn

    -- 如果有自定义的 fn，就只认它自己的 cost（没写就是无消耗）；否则才去继承父级的 cost
    local cost = ctx.cost
    if not is_custom_fn and cost == nil then
        cost = def.cost
    end

    local amount = (cost and cost.amount and cost.amount > 0) and cost.amount or nil

    if amount then
        local current_val = ResourceAdapter.GetCurrent(inst, cost.res)
        if current_val < amount then
            return false, "NOT_ENOUGH_RESOURCE"
        end
    end

    if fn then
        local success, result, err = pcall(fn, inst, params, def)
        if not success then
            log.error("[SkillResolver] Crash in '%s': %s", skill_id, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            return false, err or "EXECUTION_REJECTED"
        end
    end

    if amount and cost and cost.res then
        ResourceAdapter.DoDelta(inst, cost.res, -amount)
    end
    return true
end

return SkillResolver
