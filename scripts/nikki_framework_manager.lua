-- scripts/nikki_framework_manager.lua
local log = require("utils/log")
local EffectResolver = require("resolvers/effect_resolver")
local SkillResolver = require("resolvers/skill_resolver")
local StateResolver = require("resolvers/state_resolver")
local ResolverRegistry = require("nikki_resolver_registry")
local ModifierAdapter = require("utils/modifier_adapter")
local ResourceAdapter = require("utils/resource_adapter")

-- ========================================================
-- 组件分层装配工厂
-- ========================================================
local TIER_LEVELS = { effect = 1, skill = 2, player = 3 }

local function ApplyFrameworkToInst(inst, tier_name, default_state, custom_resources)
    local tier_level = TIER_LEVELS[tier_name] or 1

    inst:AddTag("nikki_framework")

    if tier_level >= 3 then
        inst:DoTaskInTime(0, function()
            if not TheNet:IsDedicated() and inst == ThePlayer then
                local indicator = SpawnPrefab("nikki_range_indicator")
                indicator:Attach(inst)
            end
        end)
    end

    if not TheWorld.ismastersim then return end

    -- 层级 1: 纯粹的 Effect (受击/状态接收者)
    -- 此层级不再自动挂载任何自定义资源组件，避免给普通怪物带来不必要的性能开销
    if not inst.components.nikki_effect then
        inst:AddComponent("nikki_effect")
    end

    if tier_level < 2 then return end

    -- 层级 2: Resources, Skill 与 State (施法者/技能拥有者)
    -- 只有达到该层级，才需要消耗/回复资源的组件支持
    if custom_resources then
        for res_id, config_data in pairs(custom_resources) do
            if config_data.component and config_data.component.name then
                local c_name = config_data.component.name
                if not inst.components[c_name] then
                    inst:AddComponent(c_name)
                    log.debug("[Manager] Auto-added custom resource component: '%s' to '%s'", c_name,
                        tostring(inst))
                end
            end
        end
    end

    if not inst.components.nikki_skill then inst:AddComponent("nikki_skill") end
    if not inst.components.nikki_skill_trigger then inst:AddComponent("nikki_skill_trigger") end
    if not inst.components.nikki_state then inst:AddComponent("nikki_state") end

    if inst.components.nikki_state and default_state then
        inst.components.nikki_state:SetState(default_state)
    end

    if tier_level < 3 then return end

    -- 层级 3: SkillWheel (UI / 交互入口)
    if not inst.components.nikki_skillwheel then
        inst:AddComponent("nikki_skillwheel")
    end
end

-- ========================================================
-- Manager 启动入口
-- ========================================================
local NikkiFrameworkManager = {}

function NikkiFrameworkManager.Init(config, mod_env)
    if not config or type(config) ~= "table" then return end

    -- ===============================================
    -- 1. 挂载全局扩展层 (Resources & Modifiers)
    -- 这里仅做全局数据的静态注册，不涉及特定 Prefab 的修改，放最前面无妨
    -- ===============================================
    if config.custom_resources then
        for res_id, config_data in pairs(config.custom_resources) do
            ResourceAdapter.RegisterStrategy(res_id, config_data)
            if config_data.ui and config_data.component and config_data.component.name then
                log.debug("[Manager] Auto-adding replicable component: '%s'", config_data.component.name)
                mod_env.AddReplicableComponent(config_data.component.name)
            end
        end
    end

    if config.custom_modifiers then
        for mod_type, strategy_data in pairs(config.custom_modifiers) do
            ModifierAdapter.RegisterStrategy(mod_type, strategy_data)
        end
    end

    -- ===============================================
    -- 2. 补齐并获取全游唯一的 Resolver 实例
    -- ===============================================
    local def_resolver_class = {
        effect = EffectResolver,
        skill = SkillResolver,
        state = StateResolver
    }
    local def_resolvers = {}
    for key, resolver_class in pairs(def_resolver_class) do
        def_resolvers[key] = ResolverRegistry.Get(key)
        if not def_resolvers[key] then
            def_resolvers[key] = resolver_class()
            ResolverRegistry.Register(key, def_resolvers[key])
        end
    end

    -- ===============================================
    -- 3. 解析配置包 (Defs) -> 汇入全局池
    -- ===============================================
    local defs = config.defs
    local raw_skill_data = nil
    local default_state = "default"

    if defs then
        if type(defs.effect) == "string" then
            local effect_data = require(defs.effect)
            if effect_data then
                def_resolvers.effect:AddDefs(effect_data)
                log.debug("[Manager] Appended effects to global pool from '%s'.", defs.effect)
            end
        end

        if type(defs.skill) == "string" then
            raw_skill_data = require(defs.skill)
            if raw_skill_data then
                def_resolvers.skill:AddDefs(raw_skill_data)
                log.debug("[Manager] Appended skills to global pool from '%s'.", defs.skill)
            end
        end

        if defs.state then
            def_resolvers.state:AddStateConfig(defs.state, raw_skill_data)
            log.debug("[Manager] Appended states to global pool.")

            if type(defs.state) == "table" and defs.state.default then
                default_state = defs.state.default
            end
        end
    end

    -- ===============================================
    -- 4. 装配分发 (Apply To)
    -- ===============================================
    local apply_to = config.apply_to or {}

    for tier_name, tier_cfg in pairs(apply_to) do
        if type(tier_cfg) == "table" then
            -- 按 prefabs 精准注册
            if type(tier_cfg.prefabs) == "table" then
                for _, prefab in ipairs(tier_cfg.prefabs) do
                    mod_env.AddPrefabPostInit(prefab, function(inst)
                        ApplyFrameworkToInst(inst, tier_name, default_state, config.custom_resources)
                        log.debug("[Manager] Prefab PostInit (%s) completed for '%s'", tier_name, prefab)
                    end)
                end
            end

            -- 按单一 tag 泛型注册
            if type(tier_cfg.tag) == "string" then
                local tag_name = tier_cfg.tag
                mod_env.AddPrefabPostInitAny(function(inst)
                    if inst.HasTag and inst:HasTag(tag_name) then
                        ApplyFrameworkToInst(inst, tier_name, default_state, config.custom_resources)
                        log.debug("[Manager] Tag PostInit (%s) completed for tag '%s' on prefab '%s'", tier_name,
                            tag_name, inst.prefab)
                    end
                end)
            end
        end
    end
end

return NikkiFrameworkManager
