-- scripts/components/nikki_skill.lua
local NikkiComponentBase = require("components/nikki_component_base")
local log = require("utils/log")

-- ============================================
-- 1. 资源适配器 (纯组件内部工具)
-- ============================================
local ResourceAdapter = {}
function ResourceAdapter.GetComponent(inst, res_name)
    local comp_name = (res_name == "mana") and "nikki_mana" or (res_name == "spark") and "nikki_spark" or res_name
    return inst.components[comp_name]
end

function ResourceAdapter.GetCurrent(comp, res_name)
    if res_name == "health" then return comp.currenthealth or 0 end
    if res_name == "sanity" or res_name == "hunger" then return comp.current or 0 end
    if type(comp.GetCurrent) == "function" then return comp:GetCurrent() end
    return comp.current or 0
end

function ResourceAdapter.DoDelta(comp, amount)
    if type(comp.DoDelta) == "function" then comp:DoDelta(amount) end
end

function ResourceAdapter.AddRegen(inst, comp, res_name, amount, source_id)
    if res_name == "health" then
        comp:AddRegenSource(inst, amount, 1, source_id)
    elseif res_name == "sanity" then
        comp.externalmodifiers:SetModifier(inst, amount, source_id)
    elseif res_name == "hunger" then
        if not inst._nikki_hunger_tasks then inst._nikki_hunger_tasks = {} end
        if inst._nikki_hunger_tasks[source_id] then inst._nikki_hunger_tasks[source_id]:Cancel() end
        inst._nikki_hunger_tasks[source_id] = inst:DoPeriodicTask(1, function() comp:DoDelta(amount, true) end)
    else
        if type(comp.SetRegenMod) == "function" then comp:SetRegenMod(inst, amount, source_id) end
    end
end

function ResourceAdapter.RemoveRegen(inst, comp, res_name, source_id)
    if res_name == "health" then
        comp:RemoveRegenSource(inst, source_id)
    elseif res_name == "sanity" then
        comp.externalmodifiers:RemoveModifier(inst, source_id)
    elseif res_name == "hunger" then
        if inst._nikki_hunger_tasks and inst._nikki_hunger_tasks[source_id] then
            inst._nikki_hunger_tasks[source_id]:Cancel()
            inst._nikki_hunger_tasks[source_id] = nil
        end
    else
        if type(comp.RemoveRegenMod) == "function" then comp:RemoveRegenMod(inst, source_id) end
    end
end

-- ====================================================
-- 组件类定义
-- ====================================================
local function on_max_range(self, max_range)
    if self.inst.replica.nikki_skill then
        self.inst.replica.nikki_skill:SetMaxRange(max_range)
    end
    self.inst:PushEvent("skill_max_range_dirty", { max_range = max_range })
end

local NikkiSkill = Class(NikkiComponentBase, function(self, inst)
        NikkiComponentBase._ctor(self, inst)

        self.max_range = 0

        -- 内部状态，不对外暴露
        self._active_skills = {}
        self._on_hit_skills = {}
        self._on_hurt_skills = {}
        self._toggled_skills = {}

        self.inst:StartUpdatingComponent(self)
    end,
    { max_range = on_max_range })


-- ============================================
-- 公开查询接口 (Getter)
-- ============================================

-- 安全获取当前已装配的所有技能 ID 列表（浅拷贝返回，防止外部串改）
function NikkiSkill:GetActiveSkills()
    local skills = {}
    for i, v in ipairs(self._active_skills) do
        skills[i] = v
    end
    return skills
end

function NikkiSkill:IsAdded(skill_id)
    for _, id in ipairs(self._active_skills) do
        if id == skill_id then return true end
    end
    return false
end

function NikkiSkill:IsActive(skill_id)
    if not self.resolver or not self:IsAdded(skill_id) then return false end
    if self.resolver:IsToggleSkill(skill_id) then return self._toggled_skills[skill_id] == true end
    return true
end

-- ============================================
-- 内部私有方法 (Internal Methods)
-- ============================================

function NikkiSkill:_ApplyBonus(skill_id)
    local def = self.resolver:GetSkillDef(skill_id)
    if not def or not def.bonus then return end
    local inst = self.inst
    for key, val in pairs(def.bonus) do
        if key == "tags" and type(val) == "table" then
            for _, tag in ipairs(val) do inst:AddTag(tag) end
        elseif key == "spd" and inst.components.locomotor then
            inst.components.locomotor:SetExternalSpeedMultiplier(inst, skill_id, val)
        elseif key == "atk" and inst.components.combat and inst.components.combat.externaldamagemultipliers then
            inst.components.combat.externaldamagemultipliers:SetModifier(inst, val, skill_id)
        elseif key == "defense" and inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
            inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, val, skill_id)
        elseif key == "air_spd" and inst.components.jumper then
            inst.components.jumper:SetJumpFloatSpeedMult(val)
        else
            if type(key) == "string" and string.sub(key, -6) == "_regen" then
                local res_name = string.sub(key, 1, -7)
                local comp = ResourceAdapter.GetComponent(inst, res_name)
                if comp then ResourceAdapter.AddRegen(inst, comp, res_name, val, skill_id) end
            end
        end
    end
end

function NikkiSkill:_RemoveBonus(skill_id)
    local def = self.resolver:GetSkillDef(skill_id)
    if not def or not def.bonus then return end
    local inst = self.inst
    for key, val in pairs(def.bonus) do
        if key == "tags" and type(val) == "table" then
            for _, tag in ipairs(val) do inst:RemoveTag(tag) end
        elseif key == "spd" and inst.components.locomotor then
            inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, skill_id)
        elseif key == "atk" and inst.components.combat and inst.components.combat.externaldamagemultipliers then
            inst.components.combat.externaldamagemultipliers:RemoveModifier(inst, skill_id)
        elseif key == "defense" and inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
            inst.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, skill_id)
        elseif key == "air_spd" and inst.components.jumper then
            inst.components.jumper:SetJumpFloatSpeedMult(1)
        else
            if type(key) == "string" and string.sub(key, -6) == "_regen" then
                local res_name = string.sub(key, 1, -7)
                local comp = ResourceAdapter.GetComponent(inst, res_name)
                if comp then ResourceAdapter.RemoveRegen(inst, comp, res_name, skill_id) end
            end
        end
    end
end

function NikkiSkill:_CheckResource(skill_def, expected_when)
    local cost = skill_def.cost
    if not cost then return true end

    local cost_when = cost.when or "cast"
    if expected_when and cost_when ~= expected_when then return true end

    local amount = (cost_when == "drain") and (cost.min_start or cost.rate or 0) or (cost.amount or 0)
    if amount <= 0 then return true end

    local comp = ResourceAdapter.GetComponent(self.inst, cost.resource)
    if not comp then return false, "MISSING_COMPONENT" end

    local current = ResourceAdapter.GetCurrent(comp, cost.resource)
    if current < amount then return false, string.upper(cost.resource) .. "_NOT_ENOUGH" end

    return true, nil, comp, amount, cost.resource
end

function NikkiSkill:_ExecuteTransaction(skill_id, callback, params, cost_when)
    local def = self.resolver:GetSkillDef(skill_id)
    if not def then return false, "NOT_FOUND" end

    -- 1. 验资
    local ok, err, comp, amount, res_name = self:_CheckResource(def, cost_when)
    if not ok then return false, err end

    -- 2. 执行逻辑
    if callback then
        local success, result, failed_reason = pcall(callback, self.inst, params, def)
        if not success then
            log.error("[NikkiSkill] Crash in '%s' (%s): %s", skill_id, cost_when, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            return false, failed_reason or "EXECUTION_REJECTED"
        end
    end

    -- 3. 扣费
    if comp and amount > 0 then
        ResourceAdapter.DoDelta(comp, -amount)
    end

    return true
end

function NikkiSkill:_UpdateRangeRadius()
    if not self.resolver then return end
    local max_range = 0
    for _, skill_id in ipairs(self._active_skills) do
        if self:IsActive(skill_id) then
            local range = self.resolver:GetSkillRange(skill_id)
            if range and type(range) == "number" and range > max_range then
                max_range = range
            end
        end
    end
    if max_range ~= self.max_range then
        self.max_range = max_range
    end
end

-- ====================================================
-- 外部生命周期 API (Public Methods)
-- ====================================================

function NikkiSkill:AddSkill(id)
    if not self.resolver or self:IsAdded(id) then return end
    local def = self.resolver:GetSkillDef(id)
    if not def then return end

    if def.on_add then pcall(def.on_add, self.inst, def) end
    if not self.resolver:IsToggleSkill(id) then self:_ApplyBonus(id) end

    if def.on_hit then self._on_hit_skills[id] = def.on_hit end
    if def.on_hurt then self._on_hurt_skills[id] = def.on_hurt end

    table.insert(self._active_skills, id)

    if self.resolver:IsToggleSkill(id) then
        self:ToggleSkill(id, def.default_active or false)
    end
    self:_UpdateRangeRadius()
end

function NikkiSkill:RemoveSkill(skill_id)
    if not self.resolver or not self:IsAdded(skill_id) then return end

    if self._toggled_skills[skill_id] then self:ToggleSkill(skill_id, false) end

    local def = self.resolver:GetSkillDef(skill_id)
    if not def then return end

    if not self.resolver:IsToggleSkill(skill_id) then self:_RemoveBonus(skill_id) end
    if def.on_remove then pcall(def.on_remove, self.inst, def) end

    self._on_hit_skills[skill_id] = nil
    self._on_hurt_skills[skill_id] = nil

    for i, id in ipairs(self._active_skills) do
        if id == skill_id then
            table.remove(self._active_skills, i)
            break
        end
    end
    self:_UpdateRangeRadius()
end

function NikkiSkill:AddSkills(ids)
    if ids then for _, id in ipairs(ids) do self:AddSkill(id) end end
end

function NikkiSkill:RemoveSkills(ids)
    if ids then for _, id in ipairs(ids) do self:RemoveSkill(id) end end
end

function NikkiSkill:CastSkill(id, params)
    if not self.resolver or not self:IsAdded(id) then return false, "NOT_ADDED" end
    if self.resolver:IsToggleSkill(id) then return self:ToggleSkill(id) end

    local def = self.resolver:GetSkillDef(id)
    return self:_ExecuteTransaction(id, def and def.on_cast, params, "cast")
end

function NikkiSkill:ToggleSkill(skill_id, force_state)
    if not self.resolver or not self:IsAdded(skill_id) then return false, "NOT_ADDED" end

    local current_state = self._toggled_skills[skill_id] or false
    local target_state
    if force_state ~= nil then
        target_state = force_state
    else
        target_state = not current_state
    end
    if force_state == nil and current_state == target_state then return false, "ALREADY_IN_STATE" end

    local def = self.resolver:GetSkillDef(skill_id)
    if not def then return false end

    if target_state == true then
        local ok, err = self:_ExecuteTransaction(skill_id, def.on_active, nil, "drain")
        if not ok then return false, err end

        if def.cost and def.cost.when == "drain" and def.cost.rate then
            local comp = ResourceAdapter.GetComponent(self.inst, def.cost.resource)
            if comp then
                ResourceAdapter.AddRegen(self.inst, comp, def.cost.resource, -def.cost.rate,
                    "drain_" .. skill_id)
            end
        end

        self:_ApplyBonus(skill_id)
        self._toggled_skills[skill_id] = true
        if self.inst.components.talker then self.inst.components.talker:Say(def.name or skill_id) end
    else
        if def.cost and def.cost.when == "drain" then
            local comp = ResourceAdapter.GetComponent(self.inst, def.cost.resource)
            if comp then ResourceAdapter.RemoveRegen(self.inst, comp, def.cost.resource, "drain_" .. skill_id) end
        end
        if def.on_deactive then pcall(def.on_deactive, self.inst, def) end
        self:_RemoveBonus(skill_id)
        self._toggled_skills[skill_id] = nil
    end
    self:_UpdateRangeRadius()
    return true
end

function NikkiSkill:OnHit(params)
    for skill_id, fn in pairs(self._on_hit_skills) do
        if self:IsActive(skill_id) then
            self:_ExecuteTransaction(skill_id, fn, params, "hit")
        end
    end
end

function NikkiSkill:OnHurt(params)
    for skill_id, fn in pairs(self._on_hurt_skills) do
        if self:IsActive(skill_id) then
            self:_ExecuteTransaction(skill_id, fn, params, "hurt")
        end
    end
end

function NikkiSkill:OnUpdate(dt)
    if not self.resolver then return end
    -- 统一的资源耗尽轮询检测 (极低消耗)
    for skill_id, is_on in pairs(self._toggled_skills) do
        if is_on then
            local def = self.resolver:GetSkillDef(skill_id)
            if def and def.cost and def.cost.when == "drain" then
                local res_name = def.cost.resource
                local comp = ResourceAdapter.GetComponent(self.inst, res_name)
                if comp then
                    -- 判断当前资源是否已经见底 (<= 0)
                    local current = ResourceAdapter.GetCurrent(comp, res_name)
                    if current <= 0 then
                        log.debug("[NikkiSkill] Resource '%s' depleted! Auto deactivating '%s'", res_name, skill_id)
                        self:ToggleSkill(skill_id, false)
                    end
                end
            end
        end
    end
    for _, skill_id in ipairs(self._active_skills) do
        if self:IsActive(skill_id) then
            local def = self.resolver:GetSkillDef(skill_id)
            if def and def.on_update then
                local ok, err = pcall(def.on_update, self.inst, dt, def)
                if not ok then log.error("[NikkiSkill] Error in on_update for '%s': %s", skill_id, err) end
            end
        end
    end
end

return NikkiSkill
