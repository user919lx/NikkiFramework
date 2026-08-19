-- scripts/components/nikki_skill_caster.lua
local log = require("utils/log")
local ResourceAdapter = require("utils/resource_adapter")

local function GetSkillManager(self)
    if self == nil or self.inst == nil then
        return nil
    end
    return self.inst.components.nikki_skill or self.inst.replica.nikki_skill
end

-- 无状态Component Server/Client 通用
local NikkiSkillCaster = Class(function(self, inst)
    self.inst = inst
    -- [仅服务端] 生成并绑定虚拟施法器
    -- if TheWorld.ismastersim then
    --     self.spell_caster = SpawnPrefab("nikki_spell_caster")
    --     if self.spell_caster then
    --         self.spell_caster:Attach(inst)
    --         inst.spell_caster = self.spell_caster
    --     end
    -- end
end)

function NikkiSkillCaster:OnRemoveFromEntity()
    -- if TheWorld.ismastersim and self.spell_caster and self.spell_caster:IsValid() then
    --     self.spell_caster:Remove()
    --     self.spell_caster = nil
    -- end
end

-- ============================================================
-- [主客机通用] 动作构造与上下文分析
-- ============================================================
function NikkiSkillCaster:BuildBufferedAction(target, pos, skill_id, is_client)
    local skill_manager = GetSkillManager(self)
    if not skill_manager then return nil end
    local def = skill_manager:GetSkillDef(skill_id)
    if not def or not def.action then return nil end

    local act = BufferedAction(
        self.inst,
        target,
        ACTIONS.NIKKI_SKILL,
        nil,
        pos,
        nil,
        def.range or 0
    )
    act._skill_id = skill_id
    act._skill_state = def.action.state or "doshortaction"
    act._display_name = skill_manager:GetSkillName(skill_id) or skill_id

    -- 客户端需要附加 RPC 预览回调
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

    -- 明确：active_skills 是一组有序的 Array Table (例如: {"skill_a", "skill_b"})
    local active_skills = skill_manager:GetActiveSkills()
    if not active_skills or #active_skills == 0 then return nil end

    local candidates = {}

    -- 用 ipairs 遍历 Array 才是最合理的！
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

    -- 注意：主客机通用组件，通过统一入口获取技能管理器
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

    -- 分支 A：具有 AOE Targeting 属性的技能（需官方瞄准）
    -- TODO: 目前暂不支持官方 AOE 瞄准，后续可考虑通过扩展 PlayerController 来实现
    -- if def.targeting and def.targeting.use_official_aoe then
    --     local pc = self.inst.components.playercontroller
    --     if not pc then return false, "NO_PLAYERCONTROLLER" end

    --     local skill_index = skill_manager.skill_index_map and skill_manager.skill_index_map[skill_id]
    --     if not skill_index then return false, "NOT_IN_SPELLBOOK" end

    --     local caster_inst = self.inst.spell_caster
    --     if caster_inst and caster_inst.components.spellbook then
    --         caster_inst.components.spellbook:SelectSpell(skill_index)
    --         pc:StartAOETargetingUsing(caster_inst)
    --         return true
    --     end
    --     return false
    -- end

    -- 分支 B：非官方 AOE，且无 action（瞬发技能）
    local action_def = def.action
    if not action_def then
        if TheWorld.ismastersim then
            log.debug("[NikkiSkillCaster] Executing instant skill '%s' on server", tostring(skill_id))
            return self:Execute(skill_id, params)
        else
            log.debug("[NikkiSkillCaster] Sending RPC to server to execute instant skill '%s'", tostring(skill_id))
            SendModRPCToServer(GetModRPC("NikkiFramework", "TryExecuteSkill"), skill_id)
            return true
        end
    end
    log.debug("[NikkiSkillCaster] Skill '%s' has action defined, proceeding to build BufferedAction", tostring(skill_id))

    -- 分支 C：需要补全 target/pos，发送 BufferedAction
    local invoke = action_def.invoke or "instant"
    local target = params.target
    local pos = params.pos

    -- 补全参数（fallback）
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

    local act = self:BuildBufferedAction(target, pos, skill_id, not TheWorld.ismastersim)
    if not act then return false, "BUILD_ACTION_FAILED" end

    local pc = self.inst.components.playercontroller
    if pc then
        pc:DoAction(act)
        return true
    end

    return false
end

-- ============================================================
-- [仅服务端] 统一最终结算
-- ============================================================
function NikkiSkillCaster:Execute(skill_id, params)
    if not TheWorld.ismastersim then return false end

    -- 服务端写操作通过统一入口获取（优先 components）
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
