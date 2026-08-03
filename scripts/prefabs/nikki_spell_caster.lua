local ResolverRegistry = require("nikki_resolver_registry")
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

local function Attach(inst, owner)
    if not owner then return end
    inst.entity:SetParent(owner.entity)
    if inst.components.inventoryitem then
        inst.components.inventoryitem.GetGrandOwner = function(self) return owner end
    end
end

local function OnEntityReplicated(inst)
    inst:DoTaskInTime(1, function()
        local parent = inst.entity:GetParent()
        if parent ~= nil then
            parent.spell_caster = inst
            if inst.replica.inventoryitem then
                inst.replica.inventoryitem.IsGrandOwner = function(self, guy) return guy == parent end
            end
        end
    end)
end

-- ==========================================================
-- 核心动态生成方法：从注册表中读取当前形态的 wheel 技能，并组装 UI
-- ==========================================================
local function BuildDynamicWheelItems(inst, user)
    if not user then return {} end

    local resolvers = ResolverRegistry.Get(user.prefab)
    if not resolvers or not resolvers.state or not resolvers.skill then return {} end

    -- 获取当前状态
    local current_state = "default"
    if user.replica.nikki_state then
        current_state = user.replica.nikki_state:GetState() or "default"
    end

    -- 获取当前状态该显示的技能列表
    local wheel_skill_ids = resolvers.state:GetWheelSkills(current_state)
    local items = {}
    local order = 1

    for _, skill_id in ipairs(wheel_skill_ids) do
        local skill_def = resolvers.skill:GetSkillDef(skill_id)

        if not skill_def or not skill_def.ui then
            log.warn("[Nikki Spell Caster] 技能 '%s' 缺少 ui 配置表，无法加入轮盘！", tostring(skill_id))
        else
            local ui_def = skill_def.ui
            local is_aoe = (ui_def.reticule ~= nil)
            local is_no_anim = (ui_def.no_anim == true)

            -- 1. 组装基础渲染参数
            local item = {
                label = skill_def.name or skill_id,
                id = skill_id,
                atlas = ui_def.atlas,
                normal = ui_def.normal,
                bank = ui_def.bank,
                build = ui_def.build,
                anims = ui_def.anims,
                checkenabled = ui_def.checkenabled,
                checkcooldown = ui_def.checkcooldown,
                cooldowncolor = ui_def.cooldowncolor or (ui_def.checkcooldown and { 0.65, 0.65, 0.65, 0.75 } or nil),
                widget_scale = ui_def.widget_scale or 0.6,
                hit_radius = (ui_def.anims == nil) and (ui_def.hit_radius or 50) or nil,
                order = order,
            }
            order = order + 1

            -- 2. 组装客户端动作路由 (打开指示器 or 直接释放)
            item.execute = function(spell_inst)
                local doer = GetCasterOwner(spell_inst)
                if not doer then return end

                if is_aoe then
                    if doer.components.playercontroller then
                        return doer.components.playercontroller:StartAOETargetingUsing(spell_inst)
                    end
                elseif is_no_anim then
                    if doer.replica.nikki_skill_trigger then
                        return doer.replica.nikki_skill_trigger:CastSkill(skill_id)
                    end
                else
                    if doer.replica.inventory then
                        return doer.replica.inventory:CastSpellBookFromInv(spell_inst)
                    end
                end
            end

            -- 3. 组装服务端装配路由 (指示器参数与回调映射)
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

                        if ui_def.reticule then
                            for k, v in pairs(ui_def.reticule) do
                                reticule[k] = v
                            end
                        end
                    end
                    spell_inst.components.aoetargeting:SetShouldRepeatCastFn(ui_def.should_repeat_cast_fn)
                end

                -- 服务端映射到底层的 CastSkill
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
                    elseif not is_no_anim then
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
    return items
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddNetwork()

    inst:AddTag("CLASSIFIED")
    inst:AddTag("NOCLICK")
    inst:AddTag("book")

    inst:AddComponent("aoetargeting")
    inst.components.aoetargeting:SetAllowWater(false)

    inst:AddComponent("spellbook")
    inst.components.spellbook:SetRadius(100)
    inst.components.spellbook:SetFocusRadius(102)

    local _OpenSpellBook = inst.components.spellbook.OpenSpellBook
    inst.components.spellbook.OpenSpellBook = function(self, user)
        local valid_items = BuildDynamicWheelItems(inst, user)
        if #valid_items == 0 then
            log.warn("[Nikki Spell Caster] '%s' 当前形态没有可用的轮盘技能。", tostring(user))
            return false
        end
        self:SetItems(valid_items)
        return _OpenSpellBook(self, user)
    end

    local _SelectSpell = inst.components.spellbook.SelectSpell
    inst.components.spellbook.SelectSpell = function(self, index)
        local owner = GetCasterOwner(self.inst)
        if owner then
            local valid_items = BuildDynamicWheelItems(inst, owner)
            self:SetItems(valid_items)
        end
        return _SelectSpell(self, index)
    end

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        inst.OnEntityReplicated = OnEntityReplicated
        return inst
    end

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.canbepickedup = false
    inst:AddComponent("aoespell")
    inst.Attach = Attach

    return inst
end

return Prefab("nikki_spell_caster", fn)
