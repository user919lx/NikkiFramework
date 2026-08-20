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
-- 1. 编译生命周期钩子
-- ============================================================
-- 预编译添加信息
function SkillResolver:OnDefAdded(skill_id, def)
    def.priority = def.priority or 0
    local has_wheel = def.wheel ~= nil
    local targeting_def = def.targeting
    local is_pos_targeting = targeting_def and targeting_def.mode == "pos"
    local is_spell_item = has_wheel or is_pos_targeting
    def.is_spell_item = is_spell_item

    -- Wheel 编译
    -- if type(def.wheel) == "table" and type(def.wheel.ui) == "table" then
    --     local w_def = def.wheel
    --     local ui = w_def.ui
    --     local aoe = w_def.aoe or {}

    --     local anim_cfg = ui.anim or (ui.bank and ui)
    --     local image_cfg = ui.image or (ui.atlas and ui)
    --     local is_anim = anim_cfg ~= nil and (anim_cfg.bank or anim_cfg.build or anim_cfg.anims)

    --     local checkcooldown_fn = nil
    --     local checkenabled_fn = nil

    --     if is_anim then
    --         checkcooldown_fn = function(owner)
    --             if owner and owner.components.spellbookcooldowns then
    --                 return owner.components.spellbookcooldowns:GetSpellCooldownPercent(skill_id)
    --             end
    --             return nil
    --         end
    --         checkenabled_fn = ui.checkenabled
    --     else
    --         local user_checkenabled = ui.checkenabled
    --         checkenabled_fn = function(owner)
    --             if owner and owner.components.spellbookcooldowns and owner.components.spellbookcooldowns:IsInCooldown(skill_id) then
    --                 return false
    --             end
    --             if user_checkenabled then
    --                 return user_checkenabled(owner)
    --             end
    --             return true
    --         end
    --     end

    --     self.compiled_wheels[skill_id] = {
    --         id = skill_id,
    --         name = def.name or skill_id,
    --         instant = w_def.instant == true,
    --         is_anim = is_anim,
    --         anim_cfg = is_anim and anim_cfg or nil,
    --         image_cfg = (not is_anim) and image_cfg or nil,
    --         checkcooldown = checkcooldown_fn,
    --         checkenabled = checkenabled_fn,
    --         widget_scale = ui.widget_scale or 0.6,
    --         hit_radius = ui.hit_radius or (not is_anim and 50 or nil),
    --         clicksound = ui.clicksound,
    --         spacer = ui.spacer,
    --         nestedwheel = ui.nestedwheel,
    --         helptext = ui.helptext,
    --         aoe = aoe,
    --         state = aoe.state,
    --         allow_water = aoe.allow_water,
    --         deploy_radius = aoe.deploy_radius,
    --         target_fx = aoe.target_fx,
    --         should_repeat_cast_fn = aoe.should_repeat_cast_fn,
    --         reticule = aoe.reticule,
    --     }
    -- end
end

-- ============================================================
-- 属性查询
-- ============================================================
function SkillResolver:GetPriority(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.priority or 0
end

--- 获取射程范围
function SkillResolver:GetRange(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.range or nil
end

--- 获取基础冷却时间
function SkillResolver:GetCooldown(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.cd or 0
end

--- 获取动作定义
function SkillResolver:GetActionDef(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.action or nil
end

--- 获取瞄准配置定义
function SkillResolver:GetTargetingDef(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.targeting or nil
end

-- ============================================================
-- 3. 施法装配和查询
-- ============================================================

--- 查询指定技能是否已编译轮盘配置
function SkillResolver:IsSpellItem(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.is_spell_item == true or false
end

--- 根据活跃技能列表过滤并提取可展示在轮盘/施法书中的技能 ID 列表
---@param skill_ids string[] 当前活跃技能 ID 数组
---@return string[] 适用于轮盘展示的技能 ID 列表
function SkillResolver:FilterSpellIds(skill_ids)
    if not skill_ids or #skill_ids == 0 then
        return {}
    end
    local valid_items = {}
    for _, skill_id in ipairs(skill_ids) do
        if self:IsSpellItem(skill_id) then
            table.insert(valid_items, skill_id)
        end
    end
    table.sort(valid_items, function(a, b)
        return self:GetPriority(a) > self:GetPriority(b)
    end)
    return valid_items
end

--- 构建供 Spell 使用的数据条目
--- @param skill_id string 技能 ID
--- @param user EntityScript 施法者实体
--- @return table item 供 spellbook组件 使用的条目
function SkillResolver:_BuildSpellItem(skill_id, order)
    local item = {
        skill_id = skill_id,
        order = order,
    }
    local def = self:GetDef(skill_id)
    if def then
        local name = self:GetDisplayName(skill_id)
        item.ui = {
            label = name,
        }
        local targeting_def = def.targeting
        local is_aoe_targeting = targeting_def and targeting_def.mode == "pos"
        item.onselect = function(spell_caster)
            if spell_caster.components.spellbook then
                spell_caster.components.spellbook:SetSpellName(name)
            end
            if is_aoe_targeting then
                local should_repeat_cast_fn = nil
                if targeting_def.should_repeat_cast_fn then
                    should_repeat_cast_fn = function(caster, doer)
                        return targeting_def.should_repeat_cast_fn(doer)
                    end
                end
                spell_caster.components.aoetargeting:SetAllowWater(targeting_def.allow_water or false)
                spell_caster.components.aoetargeting:SetDeployRadius(targeting_def.deploy_radius)
                spell_caster.components.aoetargeting:SetShouldRepeatCastFn(should_repeat_cast_fn)
                local native_reticule = spell_caster.components.aoetargeting.reticule
                if native_reticule then
                    -- 设置默认值
                    native_reticule.reticuleprefab = "reticuleaoe"
                    native_reticule.pingprefab = "reticuleaoeping"
                    native_reticule.targetfn = nil
                    native_reticule.mousetargetfn = nil
                    native_reticule.updatepositionfn = nil
                    native_reticule.validcolour = { 1, .75, 0, 1 }
                    native_reticule.invalidcolour = { .5, 0, 0, 1 }
                    native_reticule.ease = true
                    native_reticule.mouseenabled = true
                    native_reticule.twinstickmode = 1
                    native_reticule.twinstickrange = 8
                    native_reticule.twinstickrange = 8

                    if targeting_def.reticule then
                        for k, v in pairs(targeting_def.reticule) do
                            native_reticule[k] = v
                        end
                    end
                end
                if TheWorld.ismastersim then
                    log.debug("[SkillResolver] Setting up AOE targeting for skill '%s' with targeting definition: %s", tostring(skill_id), tostring(targeting_def))
                    spell_caster.components.aoetargeting:SetTargetFX(targeting_def.target_fx)
                    spell_caster.components.spellbook:SetSpellFn(nil)
                    spell_caster.components.aoespell:SetSpellFn(function(inst, doer, pt)
                        log.debug("[SkillResolver] Executing skill '%s' at position %s", tostring(skill_id), tostring(pt))
                        local caster_comp = doer.components.nikki_skill_caster
                        if caster_comp then
                            log.debug("[SkillResolver] Found caster component for doer '%s', executing skill.", tostring(doer))
                            return caster_comp:Execute(skill_id, { pos = pt })
                        end
                        log.debug("[SkillResolver] No caster component found for doer '%s', cannot execute skill.", tostring(doer))
                        return false, "NO_CASTER_COMP"
                    end)
                end
            end
        end
    end

    return item
end

--- 批量构建供 spellbook组件 使用的 Items 数组（保持原数组顺序）
---@param skill_ids string[] 有序技能 ID 列表
---@param user EntityScript 施法者实体
---@return table[] items  用于spellbook组件 SetItems的数组
function SkillResolver:BuildSpellItemsByIds(skill_ids)
    if not skill_ids or #skill_ids == 0 then
        return {}
    end
    local items = {}
    for order, skill_id in ipairs(skill_ids) do
        local item = self:_BuildSpellItem(skill_id, order)
        if item then
            table.insert(items, item)
        end
    end
    table.sort(items, function(a, b)
        return (a.order or 0) < (b.order or 0)
    end)
    return items
end

return SkillResolver
