-- scripts/resolvers/state_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")

-- ========================================================
-- 私有辅助：合并与覆盖逻辑
-- ========================================================
local function MergeArrays(base, overlay)
    local res, seen = {}, {}
    for _, v in ipairs(base or {}) do
        if not seen[v] then
            table.insert(res, v); seen[v] = true
        end
    end
    for _, v in ipairs(overlay or {}) do
        if not seen[v] then
            table.insert(res, v); seen[v] = true
        end
    end
    return res
end

local function ApplyTriggerOverrides(target, source)
    if not source then return end
    for t_type, t_dict in pairs(source) do
        target[t_type] = target[t_type] or {}
        for k, v in pairs(t_dict) do
            if v == false then
                target[t_type][k] = nil
            elseif type(v) == "string" then
                target[t_type][k] = { [v] = true }
            elseif type(v) == "table" then
                target[t_type][k] = target[t_type][k] or {}
                for sub_k, sub_v in pairs(v) do
                    if sub_v == false then
                        target[t_type][k][sub_k] = nil
                    else
                        target[t_type][k][sub_k] = true
                    end
                end
            end
        end
    end
end

-- ========================================================
-- 注意：HookActionForSkill 已迁移到 nikki_framework_manager.lua
-- ========================================================

local StateResolver = Class(BaseResolver, function(self, defs)
    self._resolver_type = "state"
    BaseResolver._ctor(self, defs)
end)

-- ========================================================
-- 编译接口（初始化时调用，不是运行时查询）
-- ========================================================
function StateResolver:AddStateConfig(state_cfg, raw_skill_data, hook_action_fn)
    if not state_cfg then return end

    local state_file = type(state_cfg) == "table" and state_cfg.file or
        (type(state_cfg) == "string" and state_cfg or nil)
    local basic_state = type(state_cfg) == "table" and state_cfg.basic or "basic"
    if not state_file then return end

    local raw_state_data = require(state_file)
    if not raw_state_data then return end

    local basic = raw_state_data[basic_state] or {}
    for state_name, state_def in pairs(raw_state_data) do
        if state_name ~= basic_state then
            state_def.skills = MergeArrays(basic.skills, state_def.skills)
            state_def.effects = MergeArrays(basic.effects, state_def.effects)
            state_def.tags = MergeArrays(basic.tags, state_def.tags)

            local compiled_triggers = { keys = {}, actions = {}, events = {} }

            if raw_skill_data then
                for _, skill_id in ipairs(state_def.skills or {}) do
                    local s_def = raw_skill_data[skill_id]
                    if s_def and s_def.default_triggers then
                        for t_type, t_dict in pairs(s_def.default_triggers) do
                            compiled_triggers[t_type] = compiled_triggers[t_type] or {}
                            for k, v in pairs(t_dict) do
                                if v then
                                    compiled_triggers[t_type][k] = compiled_triggers[t_type][k] or {}
                                    compiled_triggers[t_type][k][skill_id] = true
                                end
                            end
                        end
                    end
                end
            end

            ApplyTriggerOverrides(compiled_triggers, basic.triggers)
            ApplyTriggerOverrides(compiled_triggers, state_def.triggers)
            state_def.compiled_triggers = compiled_triggers

            -- 如果有 actions 且传入了 hook 函数，执行劫持
            if compiled_triggers.actions and hook_action_fn then
                for action_id, _ in pairs(compiled_triggers.actions) do
                    hook_action_fn(action_id)
                end
            end
        end
    end

    self:AddDefs(raw_state_data)
end

-- ============================================================
-- 纯查询接口
-- ============================================================

function StateResolver:OnDefAdded(state_name, def)
    if def.compiled_triggers and def.compiled_triggers.keys then
        local numeric_keys = {}
        for k, v in pairs(def.compiled_triggers.keys) do
            if type(k) == "string" and rawget(_G, k) ~= nil then
                numeric_keys[rawget(_G, k)] = v
            else
                numeric_keys[k] = v
            end
        end
        def.compiled_triggers.keys = numeric_keys
    end
end

function StateResolver:GetStateDef(state_name)
    return self:GetDef(state_name) or {}
end

function StateResolver:GetAllStates()
    return self:GetAllDefs()
end

function StateResolver:GetBadges(state)
    local def = self:GetStateDef(state)
    return def and def.badges or nil
end

function StateResolver:GetSkills(state_name)
    local def = self:GetStateDef(state_name)
    return def and def.skills or {}
end

function StateResolver:GetSkillsForKey(state_name, key_code)
    local def = self:GetStateDef(state_name)
    if def and def.compiled_triggers and def.compiled_triggers.keys then
        return def.compiled_triggers.keys[key_code]
    end
    return nil
end

return StateResolver
