-- scripts/nikki_framework_manager.lua
local log = require("utils/log")
local EffectResolver = require("resolvers/effect_resolver")
local SkillResolver = require("resolvers/skill_resolver")
local StateResolver = require("resolvers/state_resolver")
local ResolverRegistry = require("nikki_resolver_registry")
local ModifierAdapter = require("utils/modifier_adapter")
local ResourceAdapter = require("utils/resource_adapter")

-- ========================================================
-- 调试打印工具
-- ========================================================
local function FormatTableToString(tab, indent, seen, out)
    indent = indent or 0
    seen = seen or {}
    out = out or {}

    if type(tab) ~= "table" then
        table.insert(out, string.rep(" ", indent) .. tostring(tab))
        return out
    end
    if seen[tab] then
        table.insert(out, string.rep(" ", indent) .. "<循环引用>")
        return out
    end
    seen[tab] = true

    local indent_str = string.rep("  ", indent)
    local array_part = {}
    local max_index = 0
    for i = 1, #tab do
        if tab[i] ~= nil then
            table.insert(array_part, { index = i, value = tab[i] })
            max_index = i
        end
    end

    local other_part = {}
    for k, v in pairs(tab) do
        if type(k) ~= "number" or k > max_index or k < 1 or math.floor(k) ~= k then
            table.insert(other_part, { key = k, value = v })
        end
    end

    table.sort(other_part, function(a, b)
        local type_a, type_b = type(a.key), type(b.key)
        if type_a ~= type_b then return type_a < type_b end
        return tostring(a.key) < tostring(b.key)
    end)

    table.insert(out, indent_str .. "{")
    for _, item in ipairs(array_part) do
        local value = item.value
        if type(value) == "table" then
            table.insert(out, indent_str .. "  [" .. item.index .. "] =")
            FormatTableToString(value, indent + 2, seen, out)
        else
            local value_str = type(value) == "string" and "\"" .. value .. "\"" or tostring(value)
            table.insert(out, indent_str .. "  [" .. item.index .. "] = " .. value_str)
        end
    end

    for _, item in ipairs(other_part) do
        local key_str = (type(item.key) == "string" and string.match(item.key, "^[%a_][%a%d_]*$")) and item.key or
            "[" .. tostring(item.key) .. "]"
        local value = item.value
        if type(value) == "table" then
            table.insert(out, indent_str .. "  " .. key_str .. " =")
            FormatTableToString(value, indent + 2, seen, out)
        else
            local value_str = type(value) == "string" and "\"" .. value .. "\"" or tostring(value)
            table.insert(out, indent_str .. "  " .. key_str .. " = " .. value_str)
        end
    end
    table.insert(out, indent_str .. "}")
    seen[tab] = nil

    return out
end

local function DumpTableToLog(tab)
    local lines = FormatTableToString(tab, 2, {}, {})
    return table.concat(lines, "\n")
end

-- ========================================================
-- 核心编译逻辑
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
                    if sub_v == false then target[t_type][k][sub_k] = nil else target[t_type][k][sub_k] = true end
                end
            end
        end
    end
end

local function PrecompileStates(state_data, skill_data, basic_state_name)
    local basic = state_data[basic_state_name] or {}

    for state_name, state_def in pairs(state_data) do
        if state_name ~= basic_state_name then
            state_def.skills = MergeArrays(basic.skills, state_def.skills)
            state_def.effects = MergeArrays(basic.effects, state_def.effects)
            state_def.tags = MergeArrays(basic.tags, state_def.tags)

            local compiled_triggers = { keys = {}, actions = {}, events = {} }

            if skill_data then
                for _, skill_id in ipairs(state_def.skills) do
                    local s_def = skill_data[skill_id]
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

            local dump_str = DumpTableToLog(compiled_triggers)
            log.debug("\n==================================================\n" ..
                "[NikkiFramework] Compiled state: '" .. tostring(state_name) .. "'\n" ..
                "Compiled Triggers Data:\n" .. dump_str ..
                "\n==================================================")
        end
    end
end

local function HookActionForSkill(action_id)
    local action = ACTIONS[action_id]
    if not action or action._nikki_hooked then return end
    local old_fn = action.fn
    action.fn = function(act)
        local origin_result = old_fn and old_fn(act) or nil
        if act.doer and act.doer.components.nikki_skill_trigger then
            local params = {
                act = act,
                target = act.target,
                pos = type(act.GetActionPoint) == "function" and act:GetActionPoint() or nil,
                doer = act.doer,
                invobject = act.invobject,
                origin_result = origin_result
            }
            local skill_res = act.doer.components.nikki_skill_trigger:CastAction(act.action.id, params)
            if old_fn == nil then return skill_res end
        end
        return origin_result
    end
    action._nikki_hooked = true
end

local NikkiFrameworkManager = {}

function NikkiFrameworkManager.Init(config, mod_env)
    if not config or type(config) ~= "table" then return end

    for profile_name, profile_data in pairs(config) do
        local profile_resolvers = {}
        local raw_skill_data, raw_state_data = nil, nil

        -- 解析合并后的 state 配置结构
        local state_cfg = profile_data.state
        local state_file = type(state_cfg) == "table" and state_cfg.file or
        (type(state_cfg) == "string" and state_cfg or nil)
        local basic_state = type(state_cfg) == "table" and state_cfg.basic or profile_data.basic_state or "basic"
        local default_state = type(state_cfg) == "table" and state_cfg.default or profile_data.default_state or "default"

        if profile_data.effect then
            local effect_data = require(profile_data.effect)
            if effect_data then
                profile_resolvers.effect = EffectResolver(effect_data)
                log.debug("[NikkiFramework] EffectResolver initialized for profile '%s' with %d effects", profile_name,
                    table.count(effect_data))
            end
        end
        if profile_data.skill then
            raw_skill_data = require(profile_data.skill)
            if raw_skill_data then
                profile_resolvers.skill = SkillResolver(raw_skill_data)
                log.debug("[NikkiFramework] SkillResolver initialized for profile '%s' with %d skills", profile_name,
                    table.count(raw_skill_data))
            end
        end
        if state_file then
            raw_state_data = require(state_file)
            if raw_state_data then
                PrecompileStates(raw_state_data, raw_skill_data, basic_state)
                profile_resolvers.state = StateResolver(raw_state_data)
                for state_name, state_def in pairs(raw_state_data) do
                    if state_name ~= basic_state and state_def.compiled_triggers and state_def.compiled_triggers.actions then
                        for action_id, _ in pairs(state_def.compiled_triggers.actions) do HookActionForSkill(action_id) end
                    end
                end
                log.debug("[NikkiFramework] StateResolver initialized for profile '%s' with default state '%s'",
                    profile_name, default_state)
            end
        end

        if profile_data.custom_resources then
            for res_id, config_data in pairs(profile_data.custom_resources) do
                ResourceAdapter.RegisterStrategy(res_id, config_data)
                if config_data.ui and config_data.component and config_data.component.name then
                    log.debug("[NikkiFramework] Auto-adding replicable component: '%s' for resource '%s'",
                        config_data.component.name, res_id)
                    mod_env.AddReplicableComponent(config_data.component.name)
                end
            end
        end

        if profile_data.custom_modifiers then
            for mod_type, strategy_data in pairs(profile_data.custom_modifiers) do
                ModifierAdapter.RegisterStrategy(mod_type, strategy_data)
            end
        end

        if profile_data.prefabs and type(profile_data.prefabs) == "table" then
            for _, prefab_name in ipairs(profile_data.prefabs) do
                ResolverRegistry.Register(prefab_name, profile_resolvers)

                mod_env.AddPrefabPostInit(prefab_name, function(inst)
                    inst:AddTag("nikki_framework")
                    inst:DoTaskInTime(0, function()
                        if not TheNet:IsDedicated() and inst == ThePlayer then
                            local indicator = SpawnPrefab("nikki_range_indicator")
                            indicator:Attach(inst)
                        end
                    end)

                    if not TheWorld.ismastersim then return end

                    local core_components = {
                        "nikki_skill",
                        "nikki_skill_trigger",
                        "nikki_state",
                        "nikki_effect",
                        "nikki_skillwheel",
                    }
                    for _, comp_name in ipairs(core_components) do
                        if not inst.components[comp_name] then inst:AddComponent(comp_name) end
                    end

                    if profile_data.custom_resources then
                        for res_id, config_data in pairs(profile_data.custom_resources) do
                            if config_data.component and config_data.component.name then
                                local c_name = config_data.component.name
                                if not inst.components[c_name] then
                                    inst:AddComponent(c_name)
                                    log.debug(
                                        "[NikkiFramework] Auto-added missing custom resource component: '%s' to '%s'",
                                        c_name,
                                        tostring(inst))
                                end
                            end
                        end
                    end

                    -- 移除所有的 SetResolver，State 在 0 帧后直接赋予初始形态
                    if inst.components.nikki_state then
                        inst.components.nikki_state:SetState(default_state)
                    end

                    log.debug("[NikkiFramework] PostInit completed for prefab '%s' with profile '%s'", prefab_name,
                        profile_name)
                end)
            end
        end
    end
end

return NikkiFrameworkManager
