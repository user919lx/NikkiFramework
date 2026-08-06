-- scripts/resolvers/skill_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")
local ResourceAdapter = require("utils/resource_adapter")

local SkillResolver = Class(BaseResolver, function(self, defs)
    BaseResolver._ctor(self, defs)
end)

function SkillResolver:GetSkillDef(id) return self:GetDef(id) end

function SkillResolver:GetAllSkillIds() return self:GetAllIds() end

function SkillResolver:GetSkillName(skill_id) return self:GetDef(skill_id) and self:GetDef(skill_id).name or skill_id end

function SkillResolver:GetSkillRange(skill_id) return self:GetDef(skill_id) and self:GetDef(skill_id).range or nil end

function SkillResolver:OnSkillAdd(inst, skill_id)
    local def = self:GetDef(skill_id)
    if def and type(def.on_add) == "function" then pcall(def.on_add, inst, def) end
end

function SkillResolver:OnSkillRemove(inst, skill_id)
    local def = self:GetDef(skill_id)
    if def and type(def.on_remove) == "function" then pcall(def.on_remove, inst, def) end
end

function SkillResolver:ExecuteClientFn(inst, skill_id, params)
    local def = self:GetDef(skill_id)
    if not def then return false, "NOT_FOUND" end

    if type(def.client_fn) == "function" then
        local success, result, err = pcall(def.client_fn, inst, params, def)
        if not success then
            log.error("[SkillResolver] client_fn crash in '%s': %s", skill_id, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            return false, err or "EXECUTION_REJECTED"
        end
        return true
    end
    return true
end

function SkillResolver:NeedsServer(skill_id)
    local def = self:GetDef(skill_id)
    if def then
        if def.client_only then return false end
        if type(def.fn) == "function" or def.toggle then return true end
    end
    return false
end

-- ========================================================
-- 公共验证引擎 (双端通用)
-- ========================================================
function SkillResolver:CheckRequiredTags(inst, skill_id, trigger_type, trigger_key)
    local def = self:GetDef(skill_id)
    if not def then return false end

    local ctx = {}
    if trigger_type and trigger_key and def.default_triggers and def.default_triggers[trigger_type] then
        local specific = def.default_triggers[trigger_type][trigger_key]
        if type(specific) == "table" then ctx = specific end
    end

    local req_tags = ctx.required_tags or def.required_tags
    if req_tags then
        for _, tag in ipairs(req_tags) do
            if not inst:HasTag(tag) then
                log.debug("[SkillResolver] CheckRequiredTags failed: '%s' is missing required tag '%s' for skill '%s'",
                    tostring(inst), tag, skill_id)
                return false
            end
        end
    end
    log.debug("[SkillResolver] CheckRequiredTags passed for skill '%s' on '%s'", skill_id, tostring(inst))
    return true
end

-- ========================================================
-- 服务端终极执行引擎
-- ========================================================
function SkillResolver:ExecuteServerTrigger(inst, skill_id, trigger_type, trigger_key, params)
    local def = self:GetDef(skill_id)
    if not def then return false, "NOT_FOUND" end

    if not self:CheckRequiredTags(inst, skill_id, trigger_type, trigger_key) then
        return false, "MISSING_TAG"
    end

    local ctx = {}
    if def.default_triggers and def.default_triggers[trigger_type] then
        local specific = def.default_triggers[trigger_type][trigger_key]
        if type(specific) == "table" then ctx = specific end
    end

    -- ====================================================
    -- 【核心安全屏障】：互斥裁决，fn 拥有绝对优先权
    -- ====================================================
    local fn = ctx.fn or def.fn
    local toggle_data = nil
    if not fn then
        toggle_data = ctx.toggle or def.toggle
    end

    local toggle_list = nil
    if type(toggle_data) == "string" then
        toggle_list = { toggle_data }
    elseif type(toggle_data) == "table" then
        toggle_list = toggle_data
    end

    -- ====================================================
    -- 生命周期智能判定 (支持复数 Effect)
    -- ====================================================
    local is_toggling_off = false
    if toggle_list and inst.components.nikki_effect then
        for _, eff in ipairs(toggle_list) do
            if not inst.components.nikki_effect:IsPermanent(eff) then
                log.error(
                    "[SkillResolver] Configuration error: Toggle skill '%s' is bound to effect '%s' with a duration. Toggle skills can only use permanent effects.",
                    skill_id, eff)
                return false, "INVALID_TOGGLE_EFFECT"
            end
            if inst.components.nikki_effect:HasEffect(eff) then
                is_toggling_off = true
                break
            end
        end
    end

    -- ====================================================
    -- 验资阶段 (纯粹询问 Adapter，不再直接持有 comp)
    -- ====================================================
    local cost = ctx.cost or def.cost
    local amount
    if cost and cost.amount and cost.amount > 0 and not is_toggling_off then
        local current_val = ResourceAdapter.GetCurrent(inst, cost.resource)
        if current_val < cost.amount then
            return false, "NOT_ENOUGH_RESOURCE"
        end
        amount = cost.amount
    end

    -- ====================================================
    -- 互斥执行阶段
    -- ====================================================
    if fn then
        local success, result, err = pcall(fn, inst, params, def)
        if not success then
            log.error("[SkillResolver] Crash in '%s': %s", skill_id, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            return false, err or "EXECUTION_REJECTED"
        end
    elseif toggle_list and inst.components.nikki_effect then
        for _, eff in ipairs(toggle_list) do
            if is_toggling_off then
                inst.components.nikki_effect:Remove(eff, true)
            else
                inst.components.nikki_effect:Apply(eff, inst)
            end
        end
    end

    -- ====================================================
    -- 结算阶段 (瞬间离散扣费，只传 inst, resource_name, delta)
    -- ====================================================
    if amount and cost and cost.resource then
        ResourceAdapter.DoDelta(inst, cost.resource, -amount)
    end

    return true
end

return SkillResolver
