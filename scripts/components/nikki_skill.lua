-- scripts/components/nikki_skill.lua
local log = require("utils/log")
local ResourceAdapter = require("utils/resource_adapter")

-- ============================================================
-- 通过全局 Manager 获取 Resolver
-- ============================================================
local function GetResolver(self)
    if not self._resolver and NikkiManager then
        self._resolver = NikkiManager:GetSkillResolver()
    end
    return self._resolver
end

local function GetTriggerResolver()
    if NikkiManager then
        return NikkiManager:GetTriggerResolver()
    end
    return nil
end

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
        self._resolver = nil
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
    for _, id in ipairs(self._active_skills) do
        if id == skill_id then return true end
    end
    return false
end

function NikkiSkill:_OnSkillAdd(skill_id)
    local resolver = GetResolver(self)
    local def = resolver:GetDef(skill_id)
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
    local resolver = GetResolver(self)
    local def = resolver:GetDef(skill_id)
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
-- 添加技能（含 trigger 绑定和子技能递归）
-- ============================================================
function NikkiSkill:AddSkills(ids)
    if not ids then return end

    for _, id in ipairs(ids) do
        if not self:IsAdded(id) then
            self:_OnSkillAdd(id)
            table.insert(self._active_skills, id)
            log.debug("[NikkiSkill] Added skill '%s' to %s.", tostring(id), tostring(self.inst))

            local trigger_resolver = GetTriggerResolver()
            if trigger_resolver then
                local triggers = trigger_resolver:GetTriggers(id)
                if triggers and next(triggers) then
                    local trigger_comp = self.inst.components.nikki_skill_trigger
                    if trigger_comp then
                        for trigger_type, trigger_keys in pairs(triggers) do
                            for _, trigger_key in ipairs(trigger_keys) do
                                trigger_comp:Add(trigger_type, trigger_key, id)
                                log.debug("[NikkiSkill] Added trigger binding: %s[%s] -> %s", trigger_type, trigger_key,
                                    id)
                            end
                        end
                    end
                end
            end

            local resolver = GetResolver(self)
            local def = resolver and resolver:GetDef(id)
            if def and def._sub_skills then
                self:AddSkills(def._sub_skills)
            end
        end
    end
    self:_UpdateRangeRadius()
end

-- ============================================================
-- 移除技能（含 trigger 绑定移除和子技能递归）
-- ============================================================
function NikkiSkill:RemoveSkills(ids)
    if not ids then return end

    for _, id in ipairs(ids) do
        if self:IsAdded(id) then
            local resolver = GetResolver(self)
            local def = resolver and resolver:GetDef(id)
            if def and def._sub_skills then
                self:RemoveSkills(def._sub_skills)
            end

            local trigger_resolver = GetTriggerResolver()
            if trigger_resolver then
                local triggers = trigger_resolver:GetTriggers(id)
                if triggers and next(triggers) then
                    local trigger_comp = self.inst.components.nikki_skill_trigger
                    if trigger_comp then
                        for trigger_type, trigger_keys in pairs(triggers) do
                            for _, trigger_key in ipairs(trigger_keys) do
                                trigger_comp:Remove(trigger_type, trigger_key, id)
                                log.debug("[NikkiSkill] Removed trigger binding: %s[%s] -> %s", trigger_type, trigger_key,
                                    id)
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
    self:_UpdateRangeRadius()
end

function NikkiSkill:_UpdateRangeRadius()
    local resolver = GetResolver(self)
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
-- 核心执行入口
-- ============================================================

function NikkiSkill:Execute(skill_id, params)
    if not self:IsAdded(skill_id) then
        return false, "NOT_ADDED"
    end

    if self:IsOnCooldown(skill_id) then
        return false, "ON_COOLDOWN"
    end

    local resolver = GetResolver(self)
    if not resolver then
        return false, "RESOLVER_NOT_FOUND"
    end

    local def = resolver:GetDef(skill_id)
    if not def then
        return false, "SKILL_NOT_FOUND"
    end

    if def.required_tags then
        for _, tag in ipairs(def.required_tags) do
            if not self.inst:HasTag(tag) then
                return false, "MISSING_TAG: " .. tag
            end
        end
    end

    if def.cost and def.cost.res and def.cost.amount and def.cost.amount > 0 then
        local current = ResourceAdapter.GetCurrent(self.inst, def.cost.res)
        if current < def.cost.amount then
            return false, "NOT_ENOUGH_RESOURCE"
        end
    end

    if def.fn then
        local success, result, err = pcall(def.fn, self.inst, params, def)
        if not success then
            log.error("[NikkiSkill] Crash in '%s': %s", skill_id, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
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
