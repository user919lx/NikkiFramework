-- scripts/components/nikki_skill_caster.lua
local log = require("utils/log")
local ResourceAdapter = require("utils/resource_adapter")

local function GetSkillManager(self)
    if self == nil or self.inst == nil then
        return nil
    end
    return self.inst.components.nikki_skill or self.inst.replica.nikki_skill
end

local function GetRangeIndicator(inst)
    if inst.range_indicator then
        return inst.range_indicator
    end
    local indicator = SpawnPrefab("nikki_range_indicator")
    indicator:SetOwner(inst)
    inst.range_indicator = indicator
    return indicator
end

-- 无状态Component Server/Client 通用
local NikkiSkillCaster = Class(function(self, inst)
    self.inst = inst
    self._aiming_skill = nil
    self._is_aiming = false

    self:Init()
end)

function NikkiSkillCaster:Init()
    self:ExitAiming()
    if TheWorld.ismastersim then
        self.spell_caster = SpawnPrefab("nikki_spell_caster")
        if self.spell_caster then
            self.spell_caster:Attach(self.inst)
            self.inst.spell_caster = self.spell_caster
        end
    end
    self.inst:ListenForEvent("nikki_spell_items_dirty", function()
        self:_RefreshSpell()
    end)
end


function NikkiSkillCaster:OnRemoveFromEntity()
    self:ExitAiming()
end

function NikkiSkillCaster:_RefreshSpell()
    local caster_inst = self.spell_caster or self.inst.spell_caster
    if not caster_inst or not caster_inst.components.spellbook then
        log.error("[NikkiSkillCaster _RefreshSpell] No spellbook component found on caster")
        return
    end
    local skill_manager = GetSkillManager(self)
    if not skill_manager then
        log.error("[NikkiSkillCaster _RefreshSpell] No skill manager found for caster")
        return
    end
    local items = skill_manager:GetSpellItems()
    caster_inst.components.spellbook:SetItems(items)
    log.debug("[NikkiSkillCaster _RefreshSpell] Spellbook items updated. Total: %d", #items)
end
-- ============================================================
-- 瞄准状态管理 (Targeting)
-- ============================================================
function NikkiSkillCaster:EnterAiming(skill_id)
    self._aiming_skill = skill_id
    self._is_aiming = true
    log.debug("[NikkiSkillCaster] Enter aiming for skill: %s", tostring(skill_id))

    local skill_manager = GetSkillManager(self)
    if skill_manager then
        local range = skill_manager:GetSkillRange(skill_id)
        local indicator = GetRangeIndicator(self.inst)
        if indicator and range and range > 0 then
            indicator:EnterOverride(range)
        end
    end
end

function NikkiSkillCaster:ExitAiming()
    self._aiming_skill = nil
    self._is_aiming = false
    log.debug("[NikkiSkillCaster] Exit aiming")

    local indicator = GetRangeIndicator(self.inst)
    if indicator then
        indicator:ExitOverride()
    end
end

function NikkiSkillCaster:ToggleAiming(skill_id)
    if self:IsAiming() and self._aiming_skill == skill_id then
        self:ExitAiming()
        return false
    else
        self:EnterAiming(skill_id)
        return true
    end
end

function NikkiSkillCaster:IsAiming()
    return self._is_aiming and self._aiming_skill ~= nil
end

function NikkiSkillCaster:GetAimingSkill()
    return self._aiming_skill
end

-- ============================================================
-- [主客机通用] 动作构造与上下文分析
-- ============================================================
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

-- 专门用于构建 Target 瞄准动作的入口 (所有校验与获取收归内部)
function NikkiSkillCaster:BuildTargetAimAction(target)
    if not target or not target:IsValid() then
        return nil
    end

    local skill_id = self:GetAimingSkill()
    if not skill_id then
        return nil
    end

    local skill_manager = GetSkillManager(self)
    if not skill_manager then
        return nil
    end

    -- 强制校验：必须具备 targeting 定义且必须提供 testfn 校验函数
    local targeting_def = skill_manager.GetSkillTargetingDef and skill_manager:GetSkillTargetingDef(skill_id)
    if not targeting_def or type(targeting_def.testfn) ~= "function" then
        return nil
    end

    -- 执行目标过滤判定
    if targeting_def.testfn(self.inst, target) ~= true then
        return nil
    end

    return self:BuildBufferedAction(target, nil, skill_id, not TheWorld.ismastersim)
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

-- ============================================================
-- [主客机通用] 主动执行路由
-- ============================================================
function NikkiSkillCaster:TryExecute(skill_id, params)
    log.debug("[NikkiSkillCaster] TryExecute called for skill '%s' with params: %s", tostring(skill_id), tostring(params))

    local skill_manager = GetSkillManager(self)
    if not skill_manager then
        log.debug("[NikkiSkillCaster] No skill manager found")
        return false, "NO_MANAGER"
    end

    local def = skill_manager:GetSkillDef(skill_id)
    if not def then
        log.debug("[NikkiSkillCaster] Skill definition not found for skill '%s'", tostring(skill_id))
        return false, "SKILL_DEF_NOT_FOUND"
    end
    local is_rpc = params and params.is_rpc
    local is_client = not TheWorld.ismastersim
    -- 只有非 RPC 发起（即玩家本地交互）且具备 targeting 定义时，才触发瞄准切换
    local targeting_def = skill_manager:GetSkillTargetingDef(skill_id)
    if targeting_def and not is_rpc then
        local mode = targeting_def.mode
        if mode == "target" then
            log.debug("[NikkiSkillCaster] Toggled aiming for skill '%s'", tostring(skill_id))
            self:ToggleAiming(skill_id)
            return true
        elseif mode == "pos" then
            local spell_caster = self.spell_caster or self.inst.spell_caster
            if not spell_caster or not spell_caster.components.aoetargeting then
                log.error("[NikkiSkillCaster] No AOE targeting component found for skill '%s'", tostring(skill_id))
                return false, "NO_AOE_TARGETING"
            end
            -- 装配

            -- 进入AOE瞄准
            spell_caster.components.aoetargeting:StartTargeting()
        end
    end

    -- 瞬发技能逻辑
    local action_def = def.action
    if not action_def then
        if TheWorld.ismastersim then
            log.debug("[NikkiSkillCaster] Executing instant skill '%s' directly on server", tostring(skill_id))
            return self:Execute(skill_id, params)
        else
            log.debug("[NikkiSkillCaster] Sending TryExecuteSkill RPC for skill '%s' to server", tostring(skill_id))
            SendModRPCToServer(GetModRPC("NikkiFramework", "TryExecuteSkill"), skill_id)
            return true
        end
    end

    -- 参数补全 (fallback)
    local invoke = action_def.invoke or "instant"
    local target = params and params.target
    local pos = params and params.pos

    if invoke == "target" then
        if not target and action_def.fallback and action_def.fallback.target then
            target = action_def.fallback.target(self.inst, params, def)
        end
        if not target or not target:IsValid() then return false, "MISSING_OR_INVALID_TARGET" end
    elseif invoke == "pos" then
        if not pos and action_def.fallback and action_def.fallback.pos then
            pos = action_def.fallback.pos(self.inst, params, def)
        end
        if not pos then return false, "MISSING_POS" end
    end

    local act = self:BuildBufferedAction(target, pos, skill_id, is_client)
    log.debug("[NikkiSkillCaster] Built buffered action for skill '%s': %s, is_client=%s", tostring(skill_id),
        tostring(act), tostring(is_client))
    if not act then
        log.debug("[NikkiSkillCaster] Failed to build buffered action for skill '%s'", tostring(skill_id))
        return false, "BUILD_ACTION_FAILED"
    end

    local pc = self.inst.components.playercontroller
    if pc then
        pc:DoAction(act)
        log.debug("[NikkiSkillCaster] Action for skill '%s' dispatched to player controller", tostring(skill_id))
        return true
    end
    log.debug("[NikkiSkillCaster] No player controller found to dispatch action for skill '%s'", tostring(skill_id))
    return false
end

-- ============================================================
-- [仅服务端] 统一最终结算
-- ============================================================
function NikkiSkillCaster:Execute(skill_id, params)
    if not TheWorld.ismastersim then return false end

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
