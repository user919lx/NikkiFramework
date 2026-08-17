-- scripts/components/nikki_skill.lua
local log = require("utils/log")
local ResourceAdapter = require("utils/resource_adapter")

-- ============================================================
-- 通过全局 Manager 获取 Resolver
-- ============================================================
local function GetResolver(self)
    if not self._resolver and GLOBAL.NikkiManager then
        self._resolver = GLOBAL.NikkiManager:GetSkillResolver()
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
    -- 1. 检查技能是否已添加
    if not self:IsAdded(skill_id) then
        return false, "NOT_ADDED"
    end

    -- 2. 检查冷却
    if self:IsOnCooldown(skill_id) then
        return false, "ON_COOLDOWN"
    end

    -- 3. 获取技能定义
    local resolver = GetResolver(self)
    if not resolver then
        return false, "RESOLVER_NOT_FOUND"
    end

    local def = resolver:GetDef(skill_id)
    if not def then
        return false, "SKILL_NOT_FOUND"
    end

    -- 4. 检查前置标签
    if def.required_tags then
        for _, tag in ipairs(def.required_tags) do
            if not self.inst:HasTag(tag) then
                return false, "MISSING_TAG: " .. tag
            end
        end
    end

    -- 5. 检查资源消耗
    if def.cost and def.cost.res and def.cost.amount and def.cost.amount > 0 then
        local current = ResourceAdapter.GetCurrent(self.inst, def.cost.res)
        if current < def.cost.amount then
            return false, "NOT_ENOUGH_RESOURCE"
        end
    end

    -- 6. 执行技能函数
    if def.fn then
        local success, result, err = pcall(def.fn, self.inst, params, def)
        if not success then
            log.error("[NikkiSkill] Crash in '%s': %s", skill_id, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            return false, err or "EXECUTION_REJECTED"
        end
    end

    -- 7. 扣除资源（在 fn 执行之后）
    if def.cost and def.cost.res and def.cost.amount and def.cost.amount > 0 then
        ResourceAdapter.DoDelta(self.inst, def.cost.res, -def.cost.amount)
    end

    -- 8. 启动冷却
    if def.cd and def.cd > 0 then
        self:StartCooldown(skill_id, def.cd)
    end

    return true
end

return NikkiSkill
