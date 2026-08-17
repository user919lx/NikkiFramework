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
function NikkiManager:Init()
    if self._is_initialized then
        log.warn("[NikkiManager] Already initialized. Skipping.")
        return
    end

    -- 1. 创建 Resolver 实例
    self:_CreateResolvers()

    -- 2. 加载客户端设置
    self:_LoadSettings()

    -- 3. 安装 Action 劫持（默认启用，但可以注释掉）
    -- self:_InstallActionHook()

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
        -- self.state_resolver:AddStateConfig(state_cfg, raw_skill_data, function(action_id)
            -- self:_HookAction(action_id)
        -- end)
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
-- Action 劫持（完整实现）
-- ============================================================
function NikkiManager:_InstallActionHook()
    if self._hook_installed then return end

    local function hook_action(action_id)
        local action = ACTIONS[action_id]
        if not action or action._nikki_hooked then return end
        local old_fn = action.fn
        action.fn = function(act)
            local origin_result, origin_reason = old_fn and old_fn(act) or nil, nil
            if act.doer and act.doer.components.nikki_skill_trigger then
                local params = {
                    act = act,
                    target = act.target,
                    pos = type(act.GetActionPoint) == "function" and act:GetActionPoint() or nil,
                    doer = act.doer,
                    invobject = act.invobject,
                    origin_result = origin_result
                }
                local result, reason = act.doer.components.nikki_skill_trigger:CastAction(act.action.id, params)
                return result, reason
            end
            return origin_result, origin_reason
        end
        action._nikki_hooked = true
    end

    -- 劫持已注册的 ACTIONS
    for action_id, action in pairs(ACTIONS) do
        if action and action.id then
            hook_action(action_id)
        end
    end

    self._hook_installed = true
end

-- 单独劫持某个 Action（供 StateResolver 调用）
function NikkiManager:_HookAction(action_id)
    if self._hook_installed then
        local action = ACTIONS[action_id]
        if action and not action._nikki_hooked then
            local old_fn = action.fn
            action.fn = function(act)
                local origin_result, origin_reason = old_fn and old_fn(act) or nil, nil
                if act.doer and act.doer.components.nikki_skill_trigger then
                    local params = {
                        act = act,
                        target = act.target,
                        pos = type(act.GetActionPoint) == "function" and act:GetActionPoint() or nil,
                        doer = act.doer,
                        invobject = act.invobject,
                        origin_result = origin_result
                    }
                    local result, reason = act.doer.components.nikki_skill_trigger:CastAction(act.action.id, params)
                    return result, reason
                end
                return origin_result, origin_reason
            end
            action._nikki_hooked = true
        end
    else
        self:_InstallActionHook()
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
    return inst.components.nikki_skill:ExecuteTrigger(skill_id, "cast", "default", params or {})
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
