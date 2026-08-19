-- scripts/components/nikki_skill.lua
local log = require("utils/log")
local ResourceAdapter = require("utils/resource_adapter")

local function on_max_range(self, max_range)
    if self.inst.replica.nikki_skill then
        self.inst.replica.nikki_skill:SetMaxRange(max_range)
    end
    self.inst:PushEvent("skill_max_range_dirty", { max_range = max_range })
end

local NikkiSkill = Class(function(self, inst)
        self.inst = inst
        self.max_range = 0
        self._active_skills = {}
        self._resolver = nil         -- 由 Manager 注入
        self._trigger_resolver = nil -- 由 Manager 注入
        self._cooldowns = {}
    end,
    nil,
    {
        max_range = on_max_range
    })

-- ============================================================
-- 生命周期管理
-- ============================================================

function NikkiSkill:IsAdded(skill_id)
    return table.contains(self._active_skills, skill_id)
end

function NikkiSkill:_OnSkillAdd(skill_id)
    local resolver = self._resolver
    local def = resolver and resolver:GetDef(skill_id)
    if not def then return end

    if def.tags then
        for _, tag in ipairs(def.tags) do
            self.inst:AddTag(tag)
        end
    end

    if def.effects then
        for _, effect_id in ipairs(def.effects) do
            if self.inst.components.nikki_effect then
                self.inst.components.nikki_effect:Apply(effect_id, self.inst)
            end
        end
    end

    if type(def.on_add) == "function" then
        pcall(def.on_add, self.inst, def)
    end
end

function NikkiSkill:_OnSkillRemove(skill_id)
    local resolver = self._resolver
    local def = resolver and resolver:GetDef(skill_id)
    if not def then return end

    if def.tags then
        for _, tag in ipairs(def.tags) do
            self.inst:RemoveTag(tag)
        end
    end

    if def.effects then
        for _, effect_id in ipairs(def.effects) do
            if self.inst.components.nikki_effect then
                self.inst.components.nikki_effect:Remove(effect_id, true)
            end
        end
    end

    if type(def.on_remove) == "function" then
        pcall(def.on_remove, self.inst, def)
    end
end

-- ============================================================
-- 技能 添加/移除
-- ============================================================
function NikkiSkill:_UpdateRangeRadius()
    local resolver = self._resolver
    if not resolver then return end

    local max_range = 0
    for _, skill_id in ipairs(self._active_skills) do
        local range = resolver:GetSkillRange(skill_id)
        if range and type(range) == "number" and range > max_range then
            max_range = range
        end
    end
    if max_range ~= self.max_range then
        self.max_range = max_range
    end
end
function NikkiSkill:_SyncActiveSkillsToReplica()
    if self.inst.replica.nikki_skill then
        self.inst.replica.nikki_skill:SyncActiveSkills()
    end
end
function NikkiSkill:_AddSkillsInternal(ids)
    if not ids then return end
    local resolver = self._resolver
    local trigger_resolver = self._trigger_resolver
    for _, id in ipairs(ids) do
        if not self:IsAdded(id) then
            self:_OnSkillAdd(id)
            table.insert(self._active_skills, id)
            log.debug("[NikkiSkill] Added skill '%s' to %s.", tostring(id), tostring(self.inst))
            if trigger_resolver then
                local triggers = trigger_resolver:GetTriggers(id)
                if triggers and next(triggers) then
                    local trigger_comp = self.inst.components.nikki_skill_trigger
                    if trigger_comp then
                        for trigger_type, trigger_keys in pairs(triggers) do
                            for _, trigger_key in ipairs(trigger_keys) do
                                trigger_comp:Add(trigger_type, trigger_key, id)
                                log.debug("[NikkiSkill] Added trigger binding: %s[%s] -> %s", trigger_type, trigger_key, id)
                            end
                        end
                    end
                end
            end
            local def = resolver and resolver:GetDef(id)
            if def and def._sub_skills then
                self:_AddSkillsInternal(def._sub_skills)
            end
        end
    end
end
function NikkiSkill:_RemoveSkillsInternal(ids)
    if not ids then return end

    for _, id in ipairs(ids) do
        if self:IsAdded(id) then
            local resolver = self._resolver
            local def = resolver and resolver:GetDef(id)

            if def and def._sub_skills then
                self:_RemoveSkillsInternal(def._sub_skills)
            end

            local trigger_resolver = self._trigger_resolver
            if trigger_resolver then
                local triggers = trigger_resolver:GetTriggers(id)
                if triggers and next(triggers) then
                    local trigger_comp = self.inst.components.nikki_skill_trigger
                    if trigger_comp then
                        for trigger_type, trigger_keys in pairs(triggers) do
                            for _, trigger_key in ipairs(trigger_keys) do
                                trigger_comp:Remove(trigger_type, trigger_key, id)
                                log.debug("[NikkiSkill] Removed trigger binding: %s[%s] -> %s", trigger_type, trigger_key, id)
                            end
                        end
                    end
                end
            end

            self:_OnSkillRemove(id)

            for i, existing_id in ipairs(self._active_skills) do
                if existing_id == id then
                    table.remove(self._active_skills, i)
                    log.debug("[NikkiSkill] Removed skill '%s' from %s.", tostring(id), tostring(self.inst))
                    break
                end
            end

            self._cooldowns[id] = nil
        end
    end
end
function NikkiSkill:AddSkills(ids)
    self:_AddSkillsInternal(ids)
    self:_UpdateRangeRadius()
    self:_SyncActiveSkillsToReplica()
end

function NikkiSkill:RemoveSkills(ids)
    self:_RemoveSkillsInternal(ids)
    self:_UpdateRangeRadius()
    self:_SyncActiveSkillsToReplica()
end

-- ============================================================
-- 冷却管理
-- ============================================================

function NikkiSkill:GetCooldown(skill_id)
    local expire_time = self._cooldowns[skill_id]
    if not expire_time then return 0 end

    local remain = expire_time - GetTime()
    if remain <= 0 then
        self._cooldowns[skill_id] = nil
        return 0
    end
    return remain
end

function NikkiSkill:IsOnCooldown(skill_id)
    return self:GetCooldown(skill_id) > 0
end

function NikkiSkill:StartCooldown(skill_id, cd_time)
    if cd_time and cd_time > 0 then
        self._cooldowns[skill_id] = GetTime() + cd_time

        if self.inst.components.spellbookcooldowns then
            self.inst.components.spellbookcooldowns:RestartSpellCooldown(skill_id, cd_time)
        end
    end
end

-- ============================================================
-- 执行入口
-- ============================================================

-- 主动执行 （封装BufferAction）
function NikkiSkill:TryExecute(skill_id, params)
    log.debug("[NikkiSkill] TryExecute called for skill '%s' with params: %s", tostring(skill_id), tostring(params))
    local resolver = self._resolver
    if not resolver then
        log.debug("[NikkiSkill] No resolver found for skill '%s' when trying to execute for %s.", tostring(skill_id), tostring(self.inst))
        return false, "RESOLVER_NOT_FOUND"
    end
    local def = resolver:GetDef(skill_id)
    if not def then
        log.debug("[NikkiSkill] Skill definition not found for skill_id '%s' when trying to execute for %s.", tostring(skill_id), tostring(self.inst))
        return false, "SKILL_DEF_NOT_FOUND"
    end
    -- 无 action 块 → 直接执行（走 Execute）
    local action_def = def.action
    if not action_def then
        return self:Execute(skill_id, params)
    end
    -- 有 action 块 → 走 BufferedAction 封装
    local invoke = action_def.invoke or "instant"
    local target = params.target
    local pos = params.pos

    -- 4. 根据 invoke 补全参数（fallback）
    if invoke == "target" then
        if not target and action_def.fallback and action_def.fallback.target then
            target = action_def.fallback.target(self.inst, params, def)
        end
        if not target or not target:IsValid() then
            log.debug("[NikkiSkill] Missing or invalid target for skill '%s'.", tostring(skill_id))
            return false, "MISSING_OR_INVALID_TARGET"
        end
    elseif invoke == "pos" then
        if not pos and action_def.fallback and action_def.fallback.pos then
            pos = action_def.fallback.pos(self.inst, params, def)
        end
        if not pos then
            log.debug("[NikkiSkill] Missing position for skill '%s'.", tostring(skill_id))
            return false, "MISSING_POS"
        end
    end
    log.debug("[NikkiSkill] Preparing to execute skill '%s' with invoke='%s', target=%s, pos=%s", tostring(skill_id), tostring(invoke), tostring(target), tostring(pos))
    -- invoke == "instant" 不需要补全任何参数

    -- 5. 构造 BufferedAction
    local act = BufferedAction(
        self.inst,           -- doer
        target,              -- target（invoke="target" 时有值）
        ACTIONS.NIKKI_SKILL, -- action（需提前注册）
        nil,                 -- invobject
        pos,                 -- pos（invoke="pos" 时有值）
        nil,                 -- recipe
        def.range or 0       -- distance（用 def.range 控制）
    )

    -- 挂载元数据（供 ACTIONS.NIKKI_SKILL.fn 回调）
    act._skill_id = skill_id
    act._skill_state = action_def.state or "doshortaction"
    act._display_name = resolver:GetDisplayName(skill_id)

    -- 6. 推送到 locomotor
    local pc = self.inst.components.playercontroller
    if not pc then
        log.debug("[NikkiSkill] No player controller found for %s when trying to execute skill '%s'.", tostring(self.inst), tostring(skill_id))
        return false, "NO_PLAYERCONTROLLER"
    end
    pc:DoAction(act)
    return true
end

-- 统一执行入口（直接执行）
function NikkiSkill:Execute(skill_id, params)
    if not self:IsAdded(skill_id) then
        log.warn("[NikkiSkill] Attempted to execute skill '%s' which is not added to %s.", tostring(skill_id), tostring(self.inst))
        return false, "NOT_ADDED"
    end

    if self:IsOnCooldown(skill_id) then
        log.debug("[NikkiSkill] Attempted to execute skill '%s' which is on cooldown for %s.", tostring(skill_id), tostring(self.inst))
        return false, "ON_COOLDOWN"
    end

    local def = self._resolver and self._resolver:GetDef(skill_id)
    if not def then
        log.debug("[NikkiSkill] Skill definition not found for skill_id '%s' when executing for %s.", tostring(skill_id), tostring(self.inst))
        return false, "SKILL_NOT_FOUND"
    end

    if def.required_tags then
        for _, tag in ipairs(def.required_tags) do
            if not self.inst:HasTag(tag) then
                log.debug("[NikkiSkill] Missing required tag '%s' for skill '%s' on %s.", tostring(tag), tostring(skill_id), tostring(self.inst))
                return false, "MISSING_TAG: " .. tag
            end
        end
    end

    if def.cost and def.cost.res and def.cost.amount and def.cost.amount > 0 then
        local current = ResourceAdapter.GetCurrent(self.inst, def.cost.res)
        if current < def.cost.amount then
            log.debug("[NikkiSkill] Not enough resource '%s' for skill '%s' on %s. Required: %d, Current: %d", tostring(def.cost.res), tostring(skill_id), tostring(self.inst), def.cost.amount, current)
            return false, "NOT_ENOUGH_RESOURCE"
        end
    end

    if def.fn then
        local success, result, err = pcall(def.fn, self.inst, params, def)
        if not success then
            log.error("[NikkiSkill] Crash in '%s': %s", skill_id, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            log.debug("[NikkiSkill] Execution of skill '%s' rejected for %s. Reason: %s", tostring(skill_id), tostring(self.inst), tostring(err))
            return false, err or "EXECUTION_REJECTED"
        end
    end

    if def.cost and def.cost.res and def.cost.amount and def.cost.amount > 0 then
        ResourceAdapter.DoDelta(self.inst, def.cost.res, -def.cost.amount)
    end

    if def.cd and def.cd > 0 then
        self:StartCooldown(skill_id, def.cd)
    end

    return true
end

return NikkiSkill
