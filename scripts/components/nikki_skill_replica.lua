-- scripts/components/nikki_skill_replica.lua
local log = require("utils/log")
local NikkiSkill = Class(function(self, inst)
    self.inst = inst

    self._max_range = net_float(inst.GUID, "skill._max_range", "skill_maxrangedirty")
    self._max_range:set(0)

    self._active_skills_str = net_string(inst.GUID, "skill._active_skills_str", "skill_activeskillsdirty")
    self._active_skills_cache = {}
    self._skill_index_map = {}

    self._resolver = inst._replica_skill_resolver
    inst._replica_skill_resolver = nil

    if not TheWorld.ismastersim then
        inst:ListenForEvent("skill_maxrangedirty", function()
            inst:PushEvent("skill_max_range_dirty", { max_range = self:GetMaxRange() })
        end)

        inst:ListenForEvent("skill_activeskillsdirty", function()
            local str = self._active_skills_str:value()
            self._active_skills_cache = {}
            for id in string.gmatch(str or "", "[^,]+") do
                self._active_skills_cache[id] = true
            end
            self:_UpdateSpellbookItems()
            log.debug("[NikkiSkill Replica] Updated active skills cache: %s", str)
        end)
    end
end)


-- ============================================================
-- 数据同步 (Client)
-- ============================================================
function NikkiSkill:_UpdateSpellbookItems()
    local resolver = self._resolver
    if not resolver then
        log.debug("[NikkiSkill Replica] No resolver set, cannot update spell items")
        return
    end
    local active_skills = self:GetActiveSkills()
    local spell_ids = resolver:FilterSpellIds(active_skills)
    self._skill_index_map = {}
    for index, skill_id in ipairs(spell_ids) do
        self._skill_index_map[skill_id] = index
    end
    self.inst:PushEvent("nikki_spell_items_dirty")
end

-- ============================================================
-- 数据同步 (Server)
-- ============================================================

function NikkiSkill:SetMaxRange(range)
    self._max_range:set(range or 0)
end

function NikkiSkill:SyncActiveSkills()
    local comp = self.inst.components.nikki_skill
    if not comp then return end
    -- 把服务端的字典 keys 拼成字符串同步到客户端
    local keys = {}
    for k, _ in pairs(comp._active_skills) do
        table.insert(keys, k)
    end
    local str = table.concat(keys, ",")
    self._active_skills_str:set(str)
    log.debug("[NikkiSkill Replica] Synced active skills: %s", str)
end

-- ============================================================
-- 动态查询接口
-- ============================================================
function NikkiSkill:IsAdded(skill_id)
    return self._active_skills_cache[skill_id] == true
end

function NikkiSkill:GetActiveSkills()
    local list = {}
    for skill_id, _ in pairs(self._active_skills_cache) do
        table.insert(list, skill_id)
    end
    return list
end

function NikkiSkill:GetMaxRange()
    if self.inst.components.nikki_skill ~= nil then
        return self.inst.components.nikki_skill.max_range
    else
        return self._max_range:value()
    end
end

function NikkiSkill:GetSkillSpellIndex(skill_id)
    return self._skill_index_map and self._skill_index_map[skill_id]
end

function NikkiSkill:GetSpellItems()
    local resolver = self._resolver
    if not resolver then return {} end
    local active_skills = self:GetActiveSkills()
    local spell_ids = resolver:FilterSpellIds(active_skills)
    return resolver:BuildSpellItemsByIds(spell_ids)
end
-- ============================================================
-- 静态查询接口 (转发SkillResolver)
-- ============================================================
function NikkiSkill:GetSkillDef(id)
    if self._resolver then
        return self._resolver:GetDef(id)
    end
end

function NikkiSkill:GetSkillActionDef(id)
    if self._resolver then
        return self._resolver:GetActionDef(id)
    end
end

function NikkiSkill:GetSkillTargetingDef(id)
    if self._resolver then
        return self._resolver:GetTargetingDef(id)
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
