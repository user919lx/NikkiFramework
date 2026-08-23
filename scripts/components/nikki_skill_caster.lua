local log = require("utils/log")
local ResourceAdapter = require("adapters/resource_adapter")
local NikkiManager = require("nikki_manager")

local DEFAULT_WHEEL_RADIUS = 100
local DEFAULT_WHEEL_FOCUS_RADIUS = DEFAULT_WHEEL_RADIUS + 3

local function GetSkillManager(self)
    if self == nil or self.inst == nil then return nil end
    return self.inst.components.nikki_skill or self.inst.replica.nikki_skill
end

local NikkiSkillCaster = Class(function(self, inst)
    self.inst = inst
    self.is_wheel_open = false
    self._spell_index_map = {}
    self._wheel_items = {}
    self:Init()
end)

function NikkiSkillCaster:Init()
    if TheWorld.ismastersim then
        self.spell_caster = SpawnPrefab("nikki_spell_caster")
        if self.spell_caster then
            self.spell_caster:Attach(self.inst)
            self.inst.spell_caster = self.spell_caster
            self:_RefreshSpell()
            self:_RefreshWheel()
        end
    else
        if self.inst.spell_caster ~= nil then
            self:_RefreshSpell()
            self:_RefreshWheel()
        else
            local callback
            callback = function(inst, caster)
                self.inst:RemoveEventCallback("nikki_spell_caster_ready", callback)
                self:_RefreshSpell()
                self:_RefreshWheel()
            end
            self.inst:ListenForEvent("nikki_spell_caster_ready", callback)
        end
    end
    self.inst:ListenForEvent("nikki_active_skills_dirty", function()
        self:_RefreshSpell()
        self:_RefreshWheel()
    end)
    self.inst:ListenForEvent("nikki_state_dirty", function()
        if self.inst.components.playercontroller ~= nil then
            self.inst.components.playercontroller:CancelAOETargeting()
        end
        self:CloseWheel()
    end)
    self.inst:DoTaskInTime(1, function()
        self:_RefreshSpell()
        self:_RefreshWheel()
    end)
end

function NikkiSkillCaster:GetSpellIndex(skill_id)
    return self._spell_index_map[skill_id]
end

function NikkiSkillCaster:IsWheelOpen()
    local hud = self.inst.HUD
    if hud and hud.controls and hud.controls.spellwheel then
        return hud.controls.spellwheel:IsOpen()
    end
    return self.is_wheel_open
end

function NikkiSkillCaster:CloseWheel()
    self.is_wheel_open = false
    local hud = self.inst.HUD
    if hud and hud.controls and hud.controls.spellwheel and hud.controls.spellwheel:IsOpen() then
        hud.controls.spellwheel:Close()
    end
end

function NikkiSkillCaster:OpenWheel(radius, focus_radius)
    if self.inst.components.playercontroller ~= nil then
        self.inst.components.playercontroller:CancelAOETargeting()
    end

    if self:IsWheelOpen() then return end

    local hud = self.inst.HUD
    if not hud or not hud.controls or not hud.controls.spellwheel then
        log.debug("[NikkiSkillCaster] Cannot open wheel: HUD or spellwheel not found")
        return
    end

    local items = self:GetWheelItems()
    local itemscpy = {}
    for i, v in ipairs(items) do
        local can_show = true
        for _, tag in ipairs(v.required_tags or {}) do
            if not self.inst:HasTag(tag) then
                can_show = false
                break
            end
        end
        if can_show then
            local itemcpy = shallowcopy(v)
            itemcpy.execute = function()
                v.execute(self)
            end
            itemcpy.onfocus = function()
                for j, v2 in ipairs(items) do
                    v2.selected = (i == j) or nil
                end
            end
            table.insert(itemscpy, itemcpy)
        end
    end

    if #itemscpy == 0 then
        log.debug("[NikkiSkillCaster] No wheel items available to display")
        return
    end

    radius = radius or DEFAULT_WHEEL_RADIUS
    focus_radius = focus_radius or DEFAULT_WHEEL_FOCUS_RADIUS
    self.is_wheel_open = true

    hud.controls.spellwheel:SetScale(TheFrontEnd:GetProportionalHUDScale())
    hud.controls.spellwheel:SetItems(itemscpy, radius, focus_radius)
    hud.controls.spellwheel:Open()
end

function NikkiSkillCaster:GetWheelItems()
    return self._wheel_items
end

function NikkiSkillCaster:_RefreshSpell()
    local skill_manager = GetSkillManager(self)
    if not skill_manager then return end
    local resolver = NikkiManager.GetInstance():GetResolver("skill")
    if not resolver or not resolver.BuildSpellItemsByIds then return end
    local active_skills = skill_manager:GetActiveSkills()
    local spell_items, index_map = resolver:BuildSpellItemsByIds(active_skills)
    self._spell_index_map = index_map
    local caster_inst = self.spell_caster or self.inst.spell_caster
    if caster_inst and caster_inst.components.spellbook then
        caster_inst.components.spellbook:SetItems(spell_items)
    end
    log.debug("[NikkiSkillCaster _RefreshSpell] Spell items updated: %d", #spell_items)
end

function NikkiSkillCaster:_RefreshWheel()
    local skill_manager = GetSkillManager(self)
    if not skill_manager then return end
    local resolver = NikkiManager.GetInstance():GetResolver("skill")
    if not resolver then return end
    local active_skills = skill_manager:GetActiveSkills()
    if resolver.BuildWheelItemsByIds then
        self._wheel_items = resolver:BuildWheelItemsByIds(active_skills)
    else
        self._wheel_items = {}
    end
    log.debug("[NikkiSkillCaster _RefreshWheel] Wheel items updated: %d", #self._wheel_items)
end

function NikkiSkillCaster:BuildBufferedAction(target, pos, skill_id, is_client)
    local skill_manager = GetSkillManager(self)
    if not skill_manager then return nil end
    local action_def = skill_manager:GetSkillActionDef(skill_id) or {}
    local range = skill_manager:GetSkillRange(skill_id)
    local act = BufferedAction(
        self.inst,
        target,
        ACTIONS.NIKKI_SKILL,
        nil,
        pos,
        nil,
        range or 0
    )
    act._skill_id = skill_id
    act._skill_state = action_def.state or "doshortaction"
    act._display_name = skill_manager:GetSkillName(skill_id) or skill_id

    if is_client then
        pos = pos or {}
        local x, z = pos.x, pos.z
        local callback = function()
            SendModRPCToServer(GetModRPC("NikkiFramework", "TryExecuteSkill"), skill_id, target, x, z)
        end
        if self.inst.components.locomotor ~= nil then
            act.preview_cb = callback
        else
            act.non_preview_cb = callback
        end
    end
    return act
end

function NikkiSkillCaster:GetAvailableSkillAction(target, pos, right)
    if not self.inst or not self.inst:IsValid() then return nil end
    local skill_manager = GetSkillManager(self)
    if not skill_manager then return nil end

    local active_skills = skill_manager:GetActiveSkills()
    if not active_skills or #active_skills == 0 then return nil end

    local candidates = {}
    for _, skill_id in ipairs(active_skills) do
        local action_def = skill_manager:GetSkillActionDef(skill_id)
        if action_def and action_def.invoke ~= "instant" and action_def.testfn then
            local ok = false
            if action_def.invoke == "target" then
                ok = action_def.testfn(self.inst, target, right)
            elseif action_def.invoke == "pos" then
                ok = action_def.testfn(self.inst, pos, right)
            end
            if ok == true then
                table.insert(candidates, { skill_id = skill_id, priority = action_def.priority or 0 })
            end
        end
    end

    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b) return a.priority > b.priority end)
    return self:BuildBufferedAction(target, pos, candidates[1].skill_id, not TheWorld.ismastersim)
end

function NikkiSkillCaster:TryExecute(skill_id, params)
    log.debug("[NikkiSkillCaster] TryExecute called for skill '%s' with params: %s", tostring(skill_id), tostring(params))
    local skill_manager = GetSkillManager(self)
    local pc = self.inst.components.playercontroller
    if not skill_manager then
        log.error("[NikkiSkillCaster] No skill manager found")
        return false, "NO_MANAGER"
    end

    local def = skill_manager:GetSkillDef(skill_id)
    if not def then
        log.error("[NikkiSkillCaster] Skill definition not found for skill '%s'", tostring(skill_id))
        return false, "SKILL_DEF_NOT_FOUND"
    end
    if def.client_only and not TheWorld.ismastersim then
        return self:Execute(skill_id, params)
    end

    local is_rpc = params and params.is_rpc
    local is_client = not TheWorld.ismastersim

    if def.is_aoe and not is_rpc then
        local spell_caster = self.spell_caster or self.inst.spell_caster
        local spell_index = self:GetSpellIndex(skill_id)
        if spell_index and spell_caster and spell_caster.components.spellbook then
            if spell_caster.components.spellbook:SelectSpell(spell_index) then
                pc:StartAOETargetingUsing(spell_caster)
                return true
            end
        end
    end

    local action_def = def.action
    if not action_def then
        if TheWorld.ismastersim then
            return self:Execute(skill_id, params)
        else
            SendModRPCToServer(GetModRPC("NikkiFramework", "TryExecuteSkill"), skill_id)
            return true
        end
    end

    local invoke = action_def.invoke or "instant"
    local target = params and params.target
    local pos = params and params.pos

    if invoke == "target" then
        if not target and action_def.fallback and action_def.fallback.target then
            target = action_def.fallback.target(self.inst, params, def)
        end
        if not target or not target:IsValid() then
            log.debug("[NikkiSkillCaster] Missing or invalid target for skill '%s' that requires a target",
                tostring(skill_id))
            return false, "MISSING_OR_INVALID_TARGET"
        end
    elseif invoke == "pos" then
        if not pos and action_def.fallback and action_def.fallback.pos then
            pos = action_def.fallback.pos(self.inst, params, def)
        end
        if not pos then
            log.debug("[NikkiSkillCaster] Missing position for skill '%s' that requires a position", tostring(skill_id))
            return false, "MISSING_POS"
        end
    end

    local act = self:BuildBufferedAction(target, pos, skill_id, is_client)
    if not act then
        log.debug("[NikkiSkillCaster] Failed to build action for skill '%s'", tostring(skill_id))
        return false, "BUILD_ACTION_FAILED"
    end

    if pc then
        pc:DoAction(act)
        return true
    end
    log.debug("[NikkiSkillCaster] No playercontroller found to perform action for skill '%s'", tostring(skill_id))
    return false
end

function NikkiSkillCaster:Execute(skill_id, params)
    local skill_manager = GetSkillManager(self)
    if not skill_manager then return false, "NO_MANAGER" end

    if not skill_manager:IsAdded(skill_id) then return false, "NOT_ADDED" end
    if skill_manager:IsOnCooldown(skill_id) then return false, "ON_COOLDOWN" end

    local def = skill_manager:GetSkillDef(skill_id)
    if not def then return false, "SKILL_NOT_FOUND" end

    if def.required_tags then
        for _, tag in ipairs(def.required_tags) do
            if not self.inst:HasTag(tag) then return false, "MISSING_TAG: " .. tag end
        end
    end

    if def.cost and def.cost.res and def.cost.amount and def.cost.amount > 0 then
        local current = ResourceAdapter.GetCurrent(self.inst, def.cost.res)
        if current < def.cost.amount then return false, "NOT_ENOUGH_RESOURCE" end
    end

    if def.fn then
        local success, result, err = pcall(def.fn, self.inst, params, def)
        if not success or result == false then
            log.debug("[NikkiSkillCaster] Skill '%s' execution failed: %s", tostring(skill_id), tostring(err))
            return false, err or "EXECUTION_REJECTED"
        end
    end

    if def.cost and def.cost.res and def.cost.amount and def.cost.amount > 0 then
        ResourceAdapter.DoDelta(self.inst, def.cost.res, -def.cost.amount)
    end

    if def.cd and def.cd > 0 then
        skill_manager:StartCooldown(skill_id, def.cd)
    end

    return true
end

return NikkiSkillCaster
