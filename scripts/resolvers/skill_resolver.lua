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

    -- 如果定义了客机预测函数，则执行并严格捕获其返回值与错误信息
    if type(def.client_fn) == "function" then
        local success, result, err = pcall(def.client_fn, inst, params, def)
        if not success then
            log.error("[SkillResolver] client_fn crash in '%s': %s", skill_id, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            -- 允许开发者在 client_fn 中 return false, "TOO_FAR" 等自定义拒因
            return false, err or "EXECUTION_REJECTED"
        end
        return true
    end
    -- 如果没有定义 client_fn，视为客机无异议，绝对放行
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
            -- DST 引擎中，客机也能通过 HasTag 读取同步过的网络标签
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

    local ctx = {}
    if def.default_triggers and def.default_triggers[trigger_type] then
        local specific = def.default_triggers[trigger_type][trigger_key]
        if type(specific) == "table" then ctx = specific end
    end

    local req_tags = ctx.required_tags or def.required_tags
    if req_tags then
        for _, tag in ipairs(req_tags) do
            if not inst:HasTag(tag) then return false, "MISSING_TAG" end
        end
    end

    -- ====================================================
    -- 【核心安全屏障】：互斥裁决，fn 拥有绝对优先权
    -- ====================================================
    local fn = ctx.fn or def.fn
    local toggle_data = nil
    if not fn then
        toggle_data = ctx.toggle or def.toggle
    end

    -- 向下兼容：将单字符串统一转化为数组结构
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
            -- 【新增安全屏障】：强制校验 Toggle 绑定的 Effect 必须没有 duration
            if not inst.components.nikki_effect:IsPermanent(eff) then
                log.error(
                    "[SkillResolver] Configuration error: Toggle skill '%s' is bound to effect '%s' with a duration. Toggle skills can only use permanent effects.",
                    skill_id, eff)
                return false, "INVALID_TOGGLE_EFFECT"
            end
            -- 原有的开启状态判定逻辑
            if inst.components.nikki_effect:HasEffect(eff) then
                is_toggling_off = true
                break
            end
        end
    end

    -- ====================================================
    -- 验资阶段 (关闭 Toggle 免费，其余严格扣费)
    -- ====================================================
    local cost = ctx.cost or def.cost
    local comp, amount
    if cost and cost.amount and cost.amount > 0 and not is_toggling_off then
        comp = ResourceAdapter.GetComponent(inst, cost.resource)
        if not comp or ResourceAdapter.GetCurrent(comp, cost.resource) < cost.amount then
            return false, "NOT_ENOUGH_RESOURCE"
        end
        amount = cost.amount
    end

    -- ====================================================
    -- 互斥执行阶段
    -- ====================================================
    if fn then
        -- A. 执行开发者自定义的绝对逻辑
        local success, result, err = pcall(fn, inst, params, def)
        if not success then
            log.error("[SkillResolver] Crash in '%s': %s", skill_id, tostring(result))
            return false, "EXECUTION_CRASHED"
        elseif result == false then
            return false, err or "EXECUTION_REJECTED"
        end
    elseif toggle_list and inst.components.nikki_effect then
        -- B. 执行复数 Effect 的智能 Toggle
        for _, eff in ipairs(toggle_list) do
            if is_toggling_off then
                inst.components.nikki_effect:Remove(eff, true)
            else
                inst.components.nikki_effect:Apply(eff, inst)
            end
        end
    end

    -- ====================================================
    -- 结算阶段 (瞬间离散扣费)
    -- ====================================================
    if comp and amount then
        ResourceAdapter.DoDelta(comp, -amount)
    end

    return true
end

return SkillResolver
