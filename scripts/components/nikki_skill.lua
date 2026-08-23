local log = require("utils/log")
local NikkiManager = require("nikki_manager")

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
        self._cooldowns = {}
    end,
    nil,
    { max_range = on_max_range })

function NikkiSkill:_GetResolver()
    return NikkiManager.GetInstance():GetResolver("skill")
end

function NikkiSkill:_GetTriggerResolver()
    return NikkiManager.GetInstance():GetResolver("trigger")
end

function NikkiSkill:_OnSkillAdd(skill_id)
    local resolver = self:_GetResolver()
    local def = resolver and resolver:GetDef(skill_id)
    if not def then return end

    if def.tags then
        for _, tag in ipairs(def.tags) do self.inst:AddTag(tag) end
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
    local resolver = self:_GetResolver()
    local def = resolver and resolver:GetDef(skill_id)
    if not def then return end

    if def.tags then
        for _, tag in ipairs(def.tags) do self.inst:RemoveTag(tag) end
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
    local active_skills = self:GetActiveSkills()
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

function NikkiSkill:_UpdateSkillStatus()
    self:_UpdateRangeRadius()
    self:_SyncActiveSkillsToReplica()
    self.inst:PushEvent("nikki_active_skills_dirty")
end

function NikkiSkill:_AddSkillsInternal(ids)
    if not ids then return end
    local resolver = self:_GetResolver()
    local trigger_resolver = self:_GetTriggerResolver()
    for _, id in ipairs(ids) do
        if not self:IsAdded(id) then
            -- 1. 标记状态
            self._active_skills[id] = true
            -- 2. 装配主技能逻辑（Tag、Effect、on_add）
            self:_OnSkillAdd(id)
            -- 3. 装配触发器
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
            -- 4. 递归装配子技能
            local def = resolver and resolver:GetDef(id)
            if def and def._sub_skills then
                self:_AddSkillsInternal(def._sub_skills)
            end
            -- 5. 一切安好，打上成功日志
            log.debug("[NikkiSkill] Added skill '%s' to %s.", tostring(id), tostring(self.inst))
        end
    end
end

function NikkiSkill:_RemoveSkillsInternal(ids)
    if not ids then return end
    for _, id in ipairs(ids) do
        if self:IsAdded(id) then
            local resolver = self:_GetResolver()
            local def = resolver and resolver:GetDef(id)
            -- 1. 【核心修正：后进先出】先递归卸载子技能，保证子技能卸载时依然能享受父技能的环境
            if def and def._sub_skills then
                self:_RemoveSkillsInternal(def._sub_skills)
            end
            -- 2. 卸载触发器
            local trigger_resolver = self:_GetTriggerResolver()
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
            -- 3. 卸载主技能逻辑（Tag、Effect、on_remove）
            self:_OnSkillRemove(id)
            -- 4. 清理状态与冷却
            self._active_skills[id] = nil
            self._cooldowns[id] = nil
            if self.inst.components.spellbookcooldowns then
                self.inst.components.spellbookcooldowns:StopSpellCooldown(id)
            end
            -- 5. 安全着陆，打上卸载成功日志
            log.debug("[NikkiSkill] Removed skill '%s' from %s.", tostring(id), tostring(self.inst))
        end
    end
end

function NikkiSkill:AddSkills(ids)
    self:_AddSkillsInternal(ids)
    self:_UpdateSkillStatus()
end

function NikkiSkill:RemoveSkills(ids)
    self:_RemoveSkillsInternal(ids)
    self:_UpdateSkillStatus()
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

function NikkiSkill:GetCooldownPercent(skill_id)
    local resolver = self:_GetResolver()
    if not resolver then return 0 end
    local total_cooldown = resolver:GetCooldown(skill_id)
    if not total_cooldown or total_cooldown <= 0 then
        return 0
    end
    local remain = self:GetCooldown(skill_id)
    return remain / total_cooldown
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
    local resolver = self:_GetResolver()
    return resolver and resolver:GetDef(id)
end

function NikkiSkill:IsAdded(skill_id)
    return self._active_skills[skill_id] == true
end

function NikkiSkill:GetActiveSkills()
    local list = {}
    for skill_id, _ in pairs(self._active_skills) do
        table.insert(list, skill_id)
    end
    return list
end

function NikkiSkill:GetSkillActionDef(id)
    local resolver = self:_GetResolver()
    return resolver and resolver:GetActionDef(id)
end

function NikkiSkill:GetSkillTargetingDef(id)
    local resolver = self:_GetResolver()
    return resolver and resolver:GetTargetingDef(id)
end

function NikkiSkill:GetSkillRange(id)
    local resolver = self:_GetResolver()
    return resolver and resolver:GetRange(id)
end

function NikkiSkill:GetSkillName(id)
    local resolver = self:_GetResolver()
    return resolver and resolver:GetDisplayName(id)
end

function NikkiSkill:Clear()
    local ids_to_remove = self:GetActiveSkills()
    if #ids_to_remove > 0 then
        self:RemoveSkills(ids_to_remove)
    end
    self._cooldowns = {}
end

return NikkiSkill
