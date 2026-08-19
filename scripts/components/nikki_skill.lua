-- scripts/components/nikki_skill.lua
local log = require("utils/log")

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
        self.skill_index_map = {}
        self._resolver = nil
        self._trigger_resolver = nil
        self._cooldowns = {}
    end,
    nil,
    {
        max_range = on_max_range
    })
-- ============================================================
-- 生命周期管理
-- ============================================================
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

function NikkiSkill:_UpdateRangeRadius()
    local max_range = 0
    local active_skills = self:GetActiveSkills() -- 获取当前所有激活技能的列表
    for _, skill_id in ipairs(active_skills) do
        local range = self:GetSkillRange(skill_id)
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

function NikkiSkill:_UpdateSpellbookItems()
    -- TODO: 实现更新逻辑
end

function NikkiSkill:_UpdateSkillStatus()
    self:_UpdateRangeRadius()
    self:_SyncActiveSkillsToReplica()
    self:_UpdateSpellbookItems()
end

function NikkiSkill:_AddSkillsInternal(ids)
    if not ids then return end
    local resolver = self._resolver
    local trigger_resolver = self._trigger_resolver
    for _, id in ipairs(ids) do
        -- 字典查重，O(1) 复杂度，绝不重复
        if not self:IsAdded(id) then
            self:_OnSkillAdd(id)
            self._active_skills[id] = true -- 写入字典
            log.debug("[NikkiSkill] Added skill '%s' to %s.", tostring(id), tostring(self.inst))
            if trigger_resolver then
                local triggers = trigger_resolver:GetTriggers(id)
                if triggers and next(triggers) then
                    local trigger_comp = self.inst.components.nikki_skill_trigger
                    if trigger_comp then
                        for trigger_type, trigger_keys in pairs(triggers) do
                            for _, trigger_key in ipairs(trigger_keys) do
                                trigger_comp:Add(trigger_type, trigger_key, id)
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
                            end
                        end
                    end
                end
            end
            self:_OnSkillRemove(id)
            self._active_skills[id] = nil -- O(1) 复杂度直接删除
            self._cooldowns[id] = nil
        end
    end
end

function NikkiSkill:AddSkills(ids)
    self:_AddSkillsInternal(ids)
    self:_UpdateSkillStatus()
end

function NikkiSkill:RemoveSkills(ids, update_status)
    self:_RemoveSkillsInternal(ids)
    if update_status then
        self:_UpdateSkillStatus()
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

function NikkiSkill:GetSkillDef(id)
    if self._resolver then
        return self._resolver:GetDef(id)
    end
end

-- ============================================================
-- 动态查询接口
-- ============================================================
function NikkiSkill:IsAdded(skill_id)
    return self._active_skills[skill_id] == true -- O(1) 查询
end

function NikkiSkill:GetActiveSkills()
    -- 将底层的字典动态打包成 Array 返回，满足 ipairs 遍历
    local list = {}
    for skill_id, _ in pairs(self._active_skills) do
        table.insert(list, skill_id)
    end
    return list
end
-- ============================================================
-- 静态查询接口 (转发SkillResolver)
-- ============================================================
function NikkiSkill:GetSkillActionDef(id)
    if self._resolver then
        return self._resolver:GetActionDef(id)
    end
end

function NikkiSkill:GetSkillRange(id)
    if self._resolver then
        return self._resolver:GetRange(id)
    end
end

function NikkiSkill:GetSkillName(id)
    if self._resolver then
        return self._resolver:GetDisplayName(id)
    end
end

return NikkiSkill
