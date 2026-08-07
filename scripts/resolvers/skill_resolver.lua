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

-- ========================================================
-- 纯粹的只读查询接口，不修改任何状态
-- ========================================================

-- 查询技能轮数据
function SkillResolver:GetSkillWheel(skill_id)
    local def = self:GetDef(skill_id)
    if not def or type(def.wheel) ~= "table" or not def.wheel.ui then
        return nil
    end

    -- 封装并只返回 Prefab/UI 关心的轮盘内部结构，隐藏 cost、fn 等核心逻辑
    return {
        id = skill_id,
        name = def.name or skill_id,
        instant = def.wheel.instant == true, -- 顶层瞬发标志
        ui = def.wheel.ui,
        reticule = def.wheel.reticule,
    }
end

function SkillResolver:GetSkillCooldown(skill_id, trigger_type, trigger_key)
    local def = self:GetDef(skill_id)
    if not def then return 0 end

    local ctx = {}
    if trigger_type and trigger_key and def.default_triggers and def.default_triggers[trigger_type] then
        local specific = def.default_triggers[trigger_type][trigger_key]
        if type(specific) == "table" then ctx = specific end
    end

    return ctx.cd or def.cd or 0
end

function SkillResolver:OnSkillAdd(inst, skill_id)
    local def = self:GetDef(skill_id)
    if def and type(def.on_add) == "function" then pcall(def.on_add, inst, def) end
end

function SkillResolver:OnSkillRemove(inst, skill_id)
    local def = self:GetDef(skill_id)
    if def and type(def.on_remove) == "function" then pcall(def.on_remove, inst, def) end
end

function SkillResolver:NeedsServer(skill_id)
    local def = self:GetDef(skill_id)
    if def then
        if def.client_only then return false end
        if type(def.fn) == "function" then return true end
    end
    return false
end

-- ========================================================
-- 公共验证引擎 (双端通用)
-- ========================================================


function SkillResolver:ExecuteClientFn(inst, skill_id, params)
    local def = self:GetDef(skill_id)
    if not def then return false, "NOT_FOUND" end

    -- 这里的拦截也必须交还给客户端负责调用的入口 (不再引入 Component)
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
-- 服务端终极执行引擎 (彻底剔除 Component 调用)
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

    local fn = ctx.fn or def.fn

    -- 验资阶段 (技能施放瞬间的离散消耗)
    local cost = ctx.cost or def.cost
    local amount = (cost and cost.amount and cost.amount > 0) and cost.amount or nil
    if amount then
        local current_val = ResourceAdapter.GetCurrent(inst, cost.res)
        if current_val < amount then
            return false, "NOT_ENOUGH_RESOURCE"
        end
    end

    -- 执行阶段
    if fn then
        local success, result, err = pcall(fn, inst, params, def)
        if not success then
            log.error("[SkillResolver] Crash in '%s': %s", skill_id, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            return false, err or "EXECUTION_REJECTED"
        end
    end

    -- 结算扣费
    if amount and cost and cost.res then
        ResourceAdapter.DoDelta(inst, cost.res, -amount)
    end

    return true
end

return SkillResolver
