-- scripts/resolvers/skill_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")
local ResourceAdapter = require("utils/resource_adapter")

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

local SkillResolver = Class(BaseResolver, function(self, defs)
    BaseResolver._ctor(self, defs)
    self:_PrecompileWheelDefs(defs or {})
end)

-- ========================================================
-- 预编译：启动时完成 ui.anim / ui.image 解析与闭包固化
-- ========================================================
function SkillResolver:_PrecompileWheelDefs(defs)
    self.compiled_wheels = {}

    for skill_id, def in pairs(defs) do
        if type(def.wheel) == "table" and type(def.wheel.ui) == "table" then
            local w_def = def.wheel
            local ui = w_def.ui

            -- 1. 结构判定：支持分支结构 ui.anim / ui.image，同时向下兼容旧平铺写法
            local anim_cfg = ui.anim or (ui.bank and ui)
            local image_cfg = ui.image or (ui.atlas and ui)

            local is_anim = anim_cfg ~= nil and (anim_cfg.bank or anim_cfg.build or anim_cfg.anims)

            -- 2. 闭包固化：根据类型固化 checkcooldown 与 checkenabled
            local checkcooldown_fn = nil
            local checkenabled_fn = ui.checkenabled

            if is_anim then
                -- Anim 模式：对接到官方组件读取转圈 CD 百分比
                checkcooldown_fn = function(owner)
                    if owner and owner.components.spellbookcooldowns then
                        return owner.components.spellbookcooldowns:GetSpellCooldownPercent(skill_id)
                    end
                    return nil
                end
            else
                -- Image 模式：没有转圈动画，将 CD 状态转化为 checkenabled = false (触发 ImageButton 原生变灰滤镜)
                local user_checkenabled = ui.checkenabled
                checkenabled_fn = function(owner)
                    -- 第一关：检查是否在 CD 中，在 CD 直接变灰禁用
                    if owner and owner.components.spellbookcooldowns and owner.components.spellbookcooldowns:IsInCooldown(skill_id) then
                        return false
                    end
                    -- 第二关：执行开发者自定义的可用性检查
                    if user_checkenabled then
                        return user_checkenabled(owner)
                    end
                    return true
                end
            end

            -- 3. 缓化存入预编译字典
            self.compiled_wheels[skill_id] = {
                id = skill_id,
                name = def.name or skill_id,
                instant = w_def.instant == true,
                is_anim = is_anim,
                anim_cfg = is_anim and anim_cfg or nil,
                image_cfg = (not is_anim) and image_cfg or nil,
                reticule = w_def.reticule,
                checkcooldown = checkcooldown_fn,
                checkenabled = checkenabled_fn,
                widget_scale = ui.widget_scale or 0.6,
                hit_radius = ui.hit_radius or (not is_anim and 50 or nil),
                anim_tag = ui.anim_tag,
                spell_action = ui.spell_action,
                allow_water = ui.allow_water,
                deploy_radius = ui.deploy_radius,
                should_repeat_cast_fn = ui.should_repeat_cast_fn,
                target_fx = ui.target_fx,
            }
        end
    end
end

-- 判断某个技能是否配置了轮盘参数
function SkillResolver:IsWheelSkill(skill_id)
    return self.compiled_wheels ~= nil and self.compiled_wheels[skill_id] ~= nil
end
-- ========================================================
-- 工厂接口：传入上下文参数，生产组装好的 Item 对象
-- ========================================================
function SkillResolver:BuildWheelItem(skill_id, user, order)
    local compiled = self.compiled_wheels and self.compiled_wheels[skill_id]
    if not compiled then return nil end

    local is_aoe = (compiled.reticule ~= nil)
    local is_instant = compiled.instant

    -- 基础结构构建
    local item = {
        label = compiled.name,
        id = skill_id,
        checkenabled = compiled.checkenabled,
        checkcooldown = compiled.checkcooldown,
        widget_scale = compiled.widget_scale,
        hit_radius = compiled.hit_radius,
        order = order or 1,
    }

    -- 材质分支注入 (Anim 优先)
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

    -- 动态路由闭包绑装
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
        if compiled.anim_tag then
            spell_inst:AddTag(compiled.anim_tag)
        end

        if spell_inst.components.spellbook then
            spell_inst.components.spellbook:SetSpellName(item.label)
            spell_inst.components.spellbook:SetSpellAction(compiled.spell_action or nil)
        end

        if is_aoe and spell_inst.components.aoetargeting then
            spell_inst.components.aoetargeting:SetAllowWater(compiled.allow_water or false)
            spell_inst.components.aoetargeting:SetDeployRadius(compiled.deploy_radius or 0)

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

                if compiled.reticule then
                    for k, v in pairs(compiled.reticule) do
                        reticule[k] = v
                    end
                end
            end
            spell_inst.components.aoetargeting:SetShouldRepeatCastFn(compiled.should_repeat_cast_fn)
        end

        if TheWorld.ismastersim then
            if is_aoe then
                spell_inst.components.aoetargeting:SetTargetFX(compiled.target_fx or nil)
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

    return item
end

-- ========================================================
-- 基础查询与执行 API
-- ========================================================
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

    local req_tags = ctx.required_tags or def.required_tags
    if req_tags then
        for _, tag in ipairs(req_tags) do
            if not inst:HasTag(tag) then
                log.debug("[SkillResolver] CheckRequiredTags failed: '%s' is missing required tag '%s' for skill '%s'",
                    tostring(inst), tag, skill_id)
                return false
            end
        end
    end
    log.debug("[SkillResolver] CheckRequiredTags passed for skill '%s' on '%s'", skill_id, tostring(inst))
    return true
end

function SkillResolver:OnSkillAdd(inst, skill_id)
    local def = self:GetDef(skill_id)
    if def and type(def.on_add) == "function" then pcall(def.on_add, inst, def) end
end

function SkillResolver:OnSkillRemove(inst, skill_id)
    local def = self:GetDef(skill_id)
    if def and type(def.on_remove) == "function" then pcall(def.on_remove, inst, def) end
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

    local fn = ctx.fn or def.fn

    -- 验资阶段 (技能施放瞬间的离散消耗)
    local cost = ctx.cost or def.cost
    local amount = (cost and cost.amount and cost.amount > 0) and cost.amount or nil
    if amount then
        local current_val = ResourceAdapter.GetCurrent(inst, cost.res)
        if current_val < amount then
            return false, "NOT_ENOUGH_RESOURCE"
        end
    end

    -- 执行阶段
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