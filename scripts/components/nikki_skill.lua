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
-- 内部执行方法
-- ============================================================

function NikkiSkill:_CheckRequiredTags(skill_id, trigger_type, trigger_key)
    local resolver = GetResolver(self)
    local def = resolver:GetDef(skill_id)
    if not def then return false end

    local ctx = {}
    if trigger_type and trigger_key and def.default_triggers and def.default_triggers[trigger_type] then
        local specific = def.default_triggers[trigger_type][trigger_key]
        if type(specific) == "table" then ctx = specific end
    end

    local is_custom_fn = (ctx.fn ~= nil)
    local req_tags = ctx.required_tags
    if not is_custom_fn and req_tags == nil then
        req_tags = def.required_tags
    end

    if req_tags then
        for _, tag in ipairs(req_tags) do
            if not self.inst:HasTag(tag) then
                return false
            end
        end
    end
    return true
end

function NikkiSkill:CheckRequiredTags(skill_id, trigger_type, trigger_key)
    return self:_CheckRequiredTags(skill_id, trigger_type, trigger_key)
end

function NikkiSkill:NeedsServer(skill_id)
    local resolver = GetResolver(self)
    if not resolver then return false end
    return resolver:NeedsServer(skill_id)
end

function NikkiSkill:GetSkillRange(skill_id)
    local resolver = GetResolver(self)
    if not resolver then return nil end
    return resolver:GetSkillRange(skill_id)
end

function NikkiSkill:GetSkillCooldown(skill_id, trigger_type, trigger_key)
    local resolver = GetResolver(self)
    if not resolver then return 0 end
    return resolver:GetSkillCooldown(skill_id, trigger_type, trigger_key)
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

    if type(def.on_remove) == "function" then
        pcall(def.on_remove, self.inst, def)
    end
end

function NikkiSkill:_Execute(skill_id, trigger_type, trigger_key, params)
    local resolver = GetResolver(self)
    local def = resolver:GetDef(skill_id)
    if not def then return false, "NOT_FOUND" end

    if not self:_CheckRequiredTags(skill_id, trigger_type, trigger_key) then
        return false, "MISSING_TAG"
    end

    local ctx = {}
    if def.default_triggers and def.default_triggers[trigger_type] then
        local specific = def.default_triggers[trigger_type][trigger_key]
        if type(specific) == "table" then ctx = specific end
    end

    local is_custom_fn = (ctx.fn ~= nil)
    local fn = ctx.fn or def.fn

    local cost = ctx.cost
    if not is_custom_fn and cost == nil then
        cost = def.cost
    end

    local amount = (cost and cost.amount and cost.amount > 0) and cost.amount or nil

    if amount then
        local current_val = ResourceAdapter.GetCurrent(self.inst, cost.res)
        if current_val < amount then
            return false, "NOT_ENOUGH_RESOURCE"
        end
    end

    if fn then
        local success, result, err = pcall(fn, self.inst, params, def)
        if not success then
            log.error("[NikkiSkill] Crash in '%s': %s", skill_id, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            return false, err or "EXECUTION_REJECTED"
        end
    end

    if amount and cost and cost.res then
        ResourceAdapter.DoDelta(self.inst, cost.res, -amount)
    end
    return true
end

function NikkiSkill:_ExecuteClient(skill_id, params)
    local resolver = GetResolver(self)
    local def = resolver:GetDef(skill_id)
    if not def then return false, "NOT_FOUND" end

    if type(def.client_fn) == "function" then
        local success, result, err = pcall(def.client_fn, self.inst, params, def)
        if not success then
            local full_stack = debug.traceback(result, 2)
            for line in full_stack:gmatch("[^\n]+") do
                log.error("[NikkiSkill] client_fn crash in '%s': %s", skill_id, line)
            end
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            return false, err or "EXECUTION_REJECTED"
        end
        return true
    end
    return true
end

-- ============================================================
-- 公开 API
-- ============================================================

function NikkiSkill:IsAdded(skill_id)
    for _, id in ipairs(self._active_skills) do
        if id == skill_id then return true end
    end
    return false
end

function NikkiSkill:_UpdateRangeRadius()
    local resolver = GetResolver(self)
    if not resolver then return end

    local max_range = 0
    for _, skill_id in ipairs(self._active_skills) do
        local range = resolver:GetSkillRange(skill_id)
        if range and type(range) == "number" and range > max_range then max_range = range end
    end
    if max_range ~= self.max_range then self.max_range = max_range end
end

function NikkiSkill:AddSkills(ids)
    if not ids then return end

    for _, id in ipairs(ids) do
        if not self:IsAdded(id) then
            self:_OnSkillAdd(id)
            table.insert(self._active_skills, id)
            log.debug("[NikkiSkill] Added skill '%s' to %s.", tostring(id), tostring(self.inst))
        end
    end
    self:_UpdateRangeRadius()
end

function NikkiSkill:RemoveSkills(ids)
    if not ids then return end

    for _, id in ipairs(ids) do
        if self:IsAdded(id) then
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

function NikkiSkill:ExecuteTrigger(skill_id, trigger_type, trigger_key, params)
    if not self:IsAdded(skill_id) then
        return false, "NOT_ADDED"
    end

    if self:IsOnCooldown(skill_id) then
        return false, "ON_COOLDOWN"
    end

    local success, err = self:_Execute(skill_id, trigger_type, trigger_key, params)

    if success then
        local resolver = GetResolver(self)
        local cd = resolver:GetSkillCooldown(skill_id, trigger_type, trigger_key)
        if cd and cd > 0 then
            self:StartCooldown(skill_id, cd)
        end
    end

    return success, err
end

function NikkiSkill:CastSkill(id, params)
    return self:ExecuteTrigger(id, "cast", "default", params)
end

-- ============================================================
-- 客户端执行（供 Replica 调用）
-- ============================================================

function NikkiSkill:ExecuteClientFn(skill_id, params)
    return self:_ExecuteClient(skill_id, params)
end

return NikkiSkill