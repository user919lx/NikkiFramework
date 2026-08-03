-- scripts/nikki_framework_manager.lua
local log = require("utils/log")

local SkillResolver = require("resolvers/skill_resolver")
local StateResolver = require("resolvers/state_resolver")
local ResolverRegistry = require("nikki_resolver_registry")

local function HookActionForSkill(action_id)
    local action = ACTIONS[action_id]
    if not action or action._nikki_hooked then return end

    local old_fn = action.fn
    action.fn = function(act)
        local orig_res = old_fn and old_fn(act) or nil
        if act.doer and act.doer.components.nikki_skill_trigger then
            local params = {
                target = act.target,
                doer = act.doer,
                pos = act:GetActionPoint(),
                invobject = act.invobject,
                orig_result = orig_res,
            }
            local skill_res = act.doer.components.nikki_skill_trigger:CastAction(act.action.id, params)
            if old_fn == nil then return skill_res end
        end
        return orig_res
    end
    action._nikki_hooked = true
end

-- 【新增】：智能混入全局默认触发器
local function MergeDefaultTriggers(state_data, default_triggers)
    if not default_triggers or type(default_triggers) ~= "table" then return end
    for _, state_def in pairs(state_data) do
        state_def.triggers = state_def.triggers or {}
        for category, items in pairs(default_triggers) do
            state_def.triggers[category] = state_def.triggers[category] or {}
            if type(items) == "table" then
                -- 处理数组 (如 wheel)
                if items[1] ~= nil then
                    for _, v in ipairs(items) do
                        table.insert(state_def.triggers[category], v)
                    end
                    -- 处理字典 (如 keys, actions, events)
                else
                    for k, v in pairs(items) do
                        -- 仅当该形态没有覆盖该键位时，才填入默认值
                        if state_def.triggers[category][k] == nil then
                            state_def.triggers[category][k] = v
                        end
                    end
                end
            end
        end
    end
end

local NikkiFrameworkManager = {}

function NikkiFrameworkManager.Init(config, mod_env)
    if not config or type(config) ~= "table" then return end

    for profile_name, profile_data in pairs(config) do
        local profile_resolvers = {}

        if profile_data.skill then
            local skill_data = require(profile_data.skill)
            if type(skill_data) == "table" and next(skill_data) then
                profile_resolvers.skill = SkillResolver(skill_data)
            end
        end

        if profile_data.state then
            local state_data = require(profile_data.state)
            if type(state_data) == "table" and next(state_data) then
                -- 【优化】：在生成 Resolver 之前，先混入 config 的默认 triggers
                if profile_data.default and profile_data.default.triggers then
                    MergeDefaultTriggers(state_data, profile_data.default.triggers)
                end

                profile_resolvers.state = StateResolver(state_data)

                for _, state_def in pairs(state_data) do
                    if state_def.triggers and state_def.triggers.actions then
                        for action_id, _ in pairs(state_def.triggers.actions) do
                            HookActionForSkill(action_id)
                        end
                    end
                end
            end
        end

        if profile_data.prefabs and type(profile_data.prefabs) == "table" then
            for _, prefab_name in ipairs(profile_data.prefabs) do
                ResolverRegistry.Register(prefab_name, profile_resolvers)

                mod_env.AddPrefabPostInit(prefab_name, function(inst)
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
                        "nikki_skillwheel",
                        "nikki_state"
                    }
                    for _, comp_name in ipairs(core_components) do
                        if not inst.components[comp_name] then
                            inst:AddComponent(comp_name)
                        end
                    end

                    if profile_resolvers.skill then
                        inst.components.nikki_skill:SetResolver(profile_resolvers.skill)
                    end

                    if profile_resolvers.state then
                        local default_state = profile_data.default and profile_data.default.state or "default"
                        inst.components.nikki_state:Init(profile_resolvers.state, default_state)
                    end

                    if profile_data.default and profile_data.default.skills then
                        inst.components.nikki_skill:AddSkills(profile_data.default.skills)
                    end
                end)
            end
        end
    end
end

return NikkiFrameworkManager
