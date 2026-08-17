-- scripts/nikki_manager.lua
local log = require("utils/log")
local EffectResolver = require("resolvers/effect_resolver")
local SkillResolver = require("resolvers/skill_resolver")
local StateResolver = require("resolvers/state_resolver")
local ModifierAdapter = require("utils/modifier_adapter")
local ResourceAdapter = require("utils/resource_adapter")
local json = require("json")

-- ============================================================
-- 统一管理器（全局单例）
-- ============================================================
local NikkiManager = Class(function(self)
    -- 全局 Resolver 实例
    self.effect_resolver = nil
    self.skill_resolver = nil
    self.state_resolver = nil

    -- 客户端设置（取代 NikkiClientSettings）
    self._settings_file = "nikki_framework_settings"
    self._settings = {
        show_range = true,
    }
    self._settings_loaded = false

    -- 状态
    self._is_initialized = false
    self._hook_installed = false
end)

-- ============================================================
-- 初始化框架（由 modmain 调用）
-- ============================================================
function NikkiManager:Init(env)
    if self._is_initialized then
        log.warn("[NikkiManager] Already initialized. Skipping.")
        return
    end

    self:_CreateResolvers()
    self:_LoadSettings()
    self:_InstallTriggerHooks(env)

    self._is_initialized = true
    log.info("[NikkiManager] Framework initialized.")
end

-- ============================================================
-- 注册 Mod 配置（每个依赖 Mod 调用一次）
-- ============================================================
function NikkiManager:RegisterMod(config, mod_env)
    if not self._is_initialized then
        log.error("[NikkiManager] RegisterMod: Framework not initialized.")
        return
    end
    if not config or type(config) ~= "table" then
        log.error("[NikkiManager] RegisterMod: config is required.")
        return
    end
    if not mod_env then
        log.error("[NikkiManager] RegisterMod: mod_env is required.")
        return
    end

    self:_RegisterExtensions(config, mod_env)
    self:_LoadDefs(config)

    -- 提取该 Mod 的默认状态
    local default_state = "default"
    if config.defs and config.defs.state and type(config.defs.state) == "table" and config.defs.state.default then
        default_state = config.defs.state.default
    end

    self:_ApplyTo(config, mod_env, default_state)

    log.info("[NikkiManager] Mod registered.")
end

-- ============================================================
-- 私有方法
-- ============================================================
function NikkiManager:_CreateResolvers()
    self.effect_resolver = EffectResolver()
    self.skill_resolver = SkillResolver()
    self.state_resolver = StateResolver()
end

-- ============================================================
-- 为 nikki_skill_trigger 安装劫持，使其能自动拦截 Action 和 Event
-- ============================================================
function NikkiManager:_InstallTriggerHooks(env)
    if self._hooks_installed then
        log.warn("[NikkiManager] Trigger hooks already installed.")
        return
    end

    -- ============================================================
    -- 1. Action 劫持：劫持 BufferedAction:Do
    --    任何 Action 执行前都会经过 trigger:CastAction
    -- ============================================================
    env.AddClassPostConstruct("bufferedaction", function(self)
        local _super_Do = self.Do
        self.Do = function(self)
            local origin_result, origin_reason = _super_Do(self)
            if self.doer and self.doer:IsValid() and self.action and self.action.id then
                local trigger = self.doer.components.nikki_skill_trigger
                if trigger then
                    local params = {
                        act = self,
                        target = self.target,
                        pos = type(self.GetActionPoint) == "function" and self:GetActionPoint() or nil,
                        doer = self.doer,
                        invobject = self.invobject,
                        origin_result = origin_result,
                    }
                    trigger:CastAction(self.action.id, params)
                end
            end
            return origin_result, origin_reason
        end
    end)


    -- ============================================================
    -- 2. Event 劫持：劫持 EntityScript:PushEvent / PushEventImmediate
    --    任何事件触发时都会经过 trigger:CastEvent
    -- ============================================================
    local event_depth = 0
    local MAX_EVENT_DEPTH = 8

    env.AddClassPostConstruct("entityscript", function(self)
        local _super_PushEvent = self.PushEvent
        self.PushEvent = function(self, event, data)
            local result = _super_PushEvent(self, event, data)

            if self and self:IsValid() and self.components and self.components.nikki_skill_trigger then
                if event_depth >= MAX_EVENT_DEPTH then
                    log.error("[NikkiManager] Event loop detected! Max depth (%d) exceeded for event '%s'.",
                        MAX_EVENT_DEPTH, tostring(event))
                    return result
                end

                event_depth = event_depth + 1
                xpcall(function()
                    self.components.nikki_skill_trigger:CastEvent(event, data)
                end, function(err)
                    log.error("[NikkiManager] Error in CastEvent for '%s': %s", tostring(event), tostring(err))
                end)
                event_depth = event_depth - 1
            end

            return result
        end

        local _super_PushEventImmediate = self.PushEventImmediate
        self.PushEventImmediate = function(self, event, data)
            local result = _super_PushEventImmediate(self, event, data)

            if self and self:IsValid() and self.components and self.components.nikki_skill_trigger then
                if event_depth >= MAX_EVENT_DEPTH then
                    log.error("[NikkiManager] Event loop detected! Max depth (%d) exceeded for immediate event '%s'.",
                        MAX_EVENT_DEPTH, tostring(event))
                    return result
                end

                event_depth = event_depth + 1
                xpcall(function()
                    self.components.nikki_skill_trigger:CastEvent(event, data)
                end, function(err)
                    log.error("[NikkiManager] Error in CastEvent for immediate '%s': %s", tostring(event), tostring(err))
                end)
                event_depth = event_depth - 1
            end

            return result
        end
    end)

    self._hooks_installed = true
    log.info("[NikkiManager] Trigger hooks installed (Action + Event routing).")
end

function NikkiManager:_RegisterExtensions(config, mod_env)
    if config.custom_resources then
        for res_id, config_data in pairs(config.custom_resources) do
            ResourceAdapter.RegisterStrategy(res_id, config_data)
            if config_data.ui and config_data.component and config_data.component.name then
                mod_env.AddReplicableComponent(config_data.component.name)
            end
        end
    end
    if config.custom_modifiers then
        for mod_type, strategy_data in pairs(config.custom_modifiers) do
            ModifierAdapter.RegisterStrategy(mod_type, strategy_data, mod_env)
        end
    end
end

function NikkiManager:_LoadDefs(config)
    local defs = config.defs
    if not defs then return end

    local raw_skill_data = nil

    if defs.effect then
        local effect_data = require(defs.effect)
        if effect_data then
            self.effect_resolver:AddDefs(effect_data)
            log.debug("[NikkiManager] Loaded effects from '%s'.", defs.effect)
        end
    end

    if defs.skill then
        raw_skill_data = require(defs.skill)
        if raw_skill_data then
            local string_toggle_map, inline_effect_defs = self.skill_resolver:PreprocessToggles(raw_skill_data)

            for skill_id, effect_id in pairs(string_toggle_map) do
                if not self.effect_resolver:GetDef(effect_id) then
                    log.error("[NikkiManager] Skill '%s' references non-existent effect '%s'. Skill removed.", skill_id,
                        effect_id)
                    raw_skill_data[skill_id] = nil
                end
            end

            if next(inline_effect_defs) then
                self.effect_resolver:AddDefs(inline_effect_defs)
            end

            self.skill_resolver:AddDefs(raw_skill_data)
            log.debug("[NikkiManager] Loaded skills from '%s'.", defs.skill)
        end
    end

    if defs.state then
        local state_cfg = defs.state
        -- 传入 hook 函数以便在 StateResolver 中劫持 Action
        self.state_resolver:AddStateConfig(state_cfg, raw_skill_data)
        log.debug("[NikkiManager] Loaded states.")
    end
end

-- ============================================================
-- 客户端设置
-- ============================================================
function NikkiManager:_LoadSettings()
    TheSim:GetPersistentString(self._settings_file, function(success, str)
        if success and type(str) == "string" and str ~= "" then
            local ok, data = pcall(json.decode, str)
            if ok and type(data) == "table" then
                for k, v in pairs(data) do
                    self._settings[k] = v
                end
            end
        end
        self._settings_loaded = true
    end)
end

function NikkiManager:_SaveSettings()
    local success, str = pcall(json.encode, self._settings)
    if success then
        TheSim:SetPersistentString(self._settings_file, str, false)
    else
        log.error("[NikkiManager] Failed to save settings.")
    end
end

-- ============================================================
-- 装配分发（完整实现）
-- ============================================================
function NikkiManager:_ApplyTo(config, mod_env, default_state)
    local apply_to = config.apply_to or {}
    local custom_resources = config.custom_resources

    for tier_name, tier_cfg in pairs(apply_to) do
        if type(tier_cfg) == "table" then
            if type(tier_cfg.prefabs) == "table" then
                for _, prefab in ipairs(tier_cfg.prefabs) do
                    mod_env.AddPrefabPostInit(prefab, function(inst)
                        self:ApplyFrameworkToInst(inst, tier_name, custom_resources, default_state)
                    end)
                end
            end
            if type(tier_cfg.tag) == "string" then
                local tag_name = tier_cfg.tag
                mod_env.AddPrefabPostInitAny(function(inst)
                    if inst.HasTag and inst:HasTag(tag_name) then
                        self:ApplyFrameworkToInst(inst, tier_name, custom_resources, default_state)
                    end
                end)
            end
        end
    end
end

-- ============================================================
-- 装配单个实体（完整实现）
-- ============================================================
function NikkiManager:ApplyFrameworkToInst(inst, tier_name, custom_resources, default_state)
    local TIER_LEVELS = { skill = 2, player = 3 }
    local tier_level = TIER_LEVELS[tier_name] or 0

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

    if tier_level < 2 then return end

    if custom_resources then
        for res_id, config_data in pairs(custom_resources) do
            if config_data.component and config_data.component.name then
                local c_name = config_data.component.name
                if not inst.components[c_name] then
                    inst:AddComponent(c_name)
                end
            end
        end
    end

    if not inst.components.nikki_effect then inst:AddComponent("nikki_effect") end
    if not inst.components.nikki_skill then inst:AddComponent("nikki_skill") end
    if not inst.components.nikki_skill_trigger then inst:AddComponent("nikki_skill_trigger") end
    if not inst.components.nikki_state then inst:AddComponent("nikki_state") end

    if inst.components.nikki_state and default_state then
        inst.components.nikki_state:SetDefaultState(default_state)
        inst:DoTaskInTime(0, function()
            if not inst.components.nikki_state:GetState()
                and not inst:HasTag("playerghost")
                and not (inst.components.health and inst.components.health:IsDead()) then
                inst.components.nikki_state:SetState(default_state)
            end
        end)
    end

    if tier_level < 3 then return end

    -- if not inst.components.nikki_skillwheel then
    --     inst:AddComponent("nikki_skillwheel")
    -- end
end

-- ============================================================
-- 对外暴露 Resolver 实例
-- ============================================================
function NikkiManager:GetEffectResolver()
    return self.effect_resolver
end

function NikkiManager:GetSkillResolver()
    return self.skill_resolver
end

function NikkiManager:GetStateResolver()
    return self.state_resolver
end

-- ============================================================
-- 公开 API：技能
-- ============================================================
function NikkiManager:AddSkill(inst, skill_id, source)
    source = source or "dynamic"
    if not inst or not inst.components.nikki_skill then
        log.warn("[NikkiManager] AddSkill: inst has no nikki_skill component.")
        return false
    end
    return inst.components.nikki_skill:AddSkill(skill_id, source)
end

function NikkiManager:RemoveSkill(inst, skill_id)
    if not inst or not inst.components.nikki_skill then return false end
    return inst.components.nikki_skill:RemoveSkill(skill_id)
end

function NikkiManager:HasSkill(inst, skill_id)
    if not inst or not inst.components.nikki_skill then return false end
    return inst.components.nikki_skill:IsAdded(skill_id)
end

function NikkiManager:GetCooldown(inst, skill_id)
    if not inst or not inst.components.nikki_skill then return 0 end
    return inst.components.nikki_skill:GetCooldown(skill_id)
end

function NikkiManager:ExecuteSkill(inst, skill_id, params)
    if not inst or not inst.components.nikki_skill then return false, "NO_COMPONENT" end
    return inst.components.nikki_skill:Execute(skill_id, "cast", "default", params or {})
end

-- ============================================================
-- 公开 API：效果
-- ============================================================
function NikkiManager:ApplyEffect(inst, effect_id, source)
    source = source or "dynamic"
    if not inst or not inst.components.nikki_effect then
        log.warn("[NikkiManager] ApplyEffect: inst has no nikki_effect component.")
        return false
    end
    return inst.components.nikki_effect:Apply(effect_id, source)
end

function NikkiManager:RemoveEffect(inst, effect_id, force_all)
    if not inst or not inst.components.nikki_effect then return false end
    return inst.components.nikki_effect:Remove(effect_id, force_all or true)
end

function NikkiManager:HasEffect(inst, effect_id)
    if not inst or not inst.components.nikki_effect then return false end
    return inst.components.nikki_effect:HasEffect(effect_id)
end

-- ============================================================
-- 公开 API：状态
-- ============================================================
function NikkiManager:SetState(inst, state_id)
    if not inst or not inst.components.nikki_state then return false end
    return inst.components.nikki_state:SetState(state_id)
end

function NikkiManager:GetState(inst)
    if not inst or not inst.components.nikki_state then return nil end
    return inst.components.nikki_state:GetState()
end

-- ============================================================
-- 公开 API：触发器
-- ============================================================
function NikkiManager:RegisterTrigger(inst, trigger_type, key, target_type, target, source)
    source = source or "dynamic"
    if not inst or not inst.components.nikki_skill_trigger then
        log.warn("[NikkiManager] RegisterTrigger: inst has no nikki_skill_trigger component.")
        return false
    end
    return inst.components.nikki_skill_trigger:RegisterTrigger(trigger_type, key, target_type, target, source)
end

-- ============================================================
-- 公开 API：查询（Resolver 访问）
-- ============================================================
function NikkiManager:GetSkillDef(skill_id)
    return self.skill_resolver and self.skill_resolver:GetDef(skill_id)
end

function NikkiManager:GetEffectDef(effect_id)
    return self.effect_resolver and self.effect_resolver:GetDef(effect_id)
end

function NikkiManager:GetStateDef(state_id)
    return self.state_resolver and self.state_resolver:GetDef(state_id)
end

function NikkiManager:GetSkillDisplayName(skill_id)
    return self.skill_resolver and self.skill_resolver:GetDisplayName(skill_id) or skill_id
end

-- ============================================================
-- 公开 API：客户端设置
-- ============================================================
function NikkiManager:GetSetting(key)
    return self._settings[key]
end

function NikkiManager:SetSetting(key, val)
    self._settings[key] = val
    self:_SaveSettings()
end

function NikkiManager:ToggleSetting(key)
    if type(self._settings[key]) == "boolean" then
        self._settings[key] = not self._settings[key]
        self:_SaveSettings()
    end
    return self._settings[key]
end

-- ============================================================
-- 单例
-- ============================================================
local instance = nil

function NikkiManager.GetInstance()
    if not instance then
        instance = NikkiManager()
    end
    return instance
end

return NikkiManager
