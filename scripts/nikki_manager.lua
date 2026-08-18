-- scripts/nikki_manager.lua
local log = require("utils/log")
local EffectResolver = require("resolvers/effect_resolver")
local SkillResolver = require("resolvers/skill_resolver")
local StateResolver = require("resolvers/state_resolver")
local TriggerResolver = require("resolvers/trigger_resolver")
local ModifierAdapter = require("utils/modifier_adapter")
local ResourceAdapter = require("utils/resource_adapter")
local json = require("json")

-- ============================================================
-- ID 生成器
-- ============================================================
local function GenerateSubSkillId(skill_id, trigger_type, trigger_key)
    return "_skill_sub_" .. skill_id .. "_" .. trigger_type .. "_" .. tostring(trigger_key)
end

local function GenerateToggleEffectId(skill_id)
    return "_skill_toggle_" .. skill_id
end

-- ============================================================
-- 统一管理器（全局单例）
-- ============================================================
local NikkiManager = Class(function(self)
    self.effect_resolver = nil
    self.skill_resolver = nil
    self.state_resolver = nil
    self.trigger_resolver = nil

    self._settings_file = "nikki_framework_settings"
    self._settings = {
        show_range = true,
    }
    self._settings_loaded = false

    self._is_initialized = false
    self._hooks_installed = false
end)

-- ============================================================
-- 初始化框架
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
-- 注册 Mod 配置
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
    -- 加载传统框架资源（配方、动作、SG、图集）—— 路径位于 defs 下
    self:_LoadFrameworkResources(config, mod_env)
    self:_ApplyTo(config, mod_env)
    log.info("[NikkiManager] Mod %s registered.", tostring(mod_env.modname))
end

-- ============================================================
-- 私有方法
-- ============================================================
function NikkiManager:_CreateResolvers()
    self.effect_resolver = EffectResolver()
    self.skill_resolver = SkillResolver()
    self.state_resolver = StateResolver()
    self.trigger_resolver = TriggerResolver()
end

-- ============================================================
-- 安装劫持
-- ============================================================
function NikkiManager:_InstallTriggerHooks(env)
    if self._hooks_installed then
        log.warn("[NikkiManager] Trigger hooks already installed.")
        return
    end

    -- Action 劫持：拦截 BufferedAction:Do
    local _old_Do = BufferedAction.Do
    ---@diagnostic disable-next-line: duplicate-set-field
    BufferedAction.Do = function(self)
        local origin_result, origin_reason = _old_Do(self)
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
                trigger:Trigger("actions", self.action.id, params)
            end
        end
        return origin_result, origin_reason
    end

    -- Event 劫持：拦截 PushEvent / PushEventImmediate
    local event_depth = 0
    local MAX_EVENT_DEPTH = 8

    local _old_PushEvent = EntityScript.PushEvent
    EntityScript.PushEvent = function(self, event, data)
        local result = _old_PushEvent(self, event, data)
        if self and self:IsValid() and self.components and self.components.nikki_skill_trigger then
            if event_depth >= MAX_EVENT_DEPTH then
                log.error("[NikkiManager] Event loop detected! Max depth (%d) exceeded for event '%s'.",
                    MAX_EVENT_DEPTH, tostring(event))
                return result
            end
            event_depth = event_depth + 1
            xpcall(function()
                self.components.nikki_skill_trigger:Trigger("events", event, data)
            end, function(err)
                log.error("[NikkiManager] Error in Trigger for event '%s': %s", tostring(event), tostring(err))
            end)
            event_depth = event_depth - 1
        end
        return result
    end

    local _old_PushEventImmediate = EntityScript.PushEventImmediate
    EntityScript.PushEventImmediate = function(self, event, data)
        local result = _old_PushEventImmediate(self, event, data)
        if self and self:IsValid() and self.components and self.components.nikki_skill_trigger then
            if event_depth >= MAX_EVENT_DEPTH then
                log.error("[NikkiManager] Event loop detected! Max depth (%d) exceeded for immediate event '%s'.",
                    MAX_EVENT_DEPTH, tostring(event))
                return result
            end
            event_depth = event_depth + 1
            xpcall(function()
                self.components.nikki_skill_trigger:Trigger("events", event, data)
            end, function(err)
                log.error("[NikkiManager] Error in Trigger for immediate event '%s': %s", tostring(event), tostring(err))
            end)
            event_depth = event_depth - 1
        end
        return result
    end

    self._hooks_installed = true
    log.info("[NikkiManager] Trigger hooks installed.")
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

-- ============================================================
-- _LoadDefs：核心编译逻辑（一次性加载）
-- ============================================================
function NikkiManager:_LoadDefs(config)
    local defs = config.defs
    if not defs then return end

    local raw_skill_data = nil

    -- 1. 加载 Effect
    if defs.effect then
        local effect_data = require(defs.effect)
        if effect_data then
            self.effect_resolver:AddDefs(effect_data)
            log.debug("[NikkiManager] Loaded effects from '%s'.", defs.effect)
        end
    end

    -- 2. 加载并编译 Skill
    if defs.skill then
        raw_skill_data = require(defs.skill)
        if raw_skill_data then
            local all_skills = {}
            local trigger_data = {}
            local effect_defs = {}

            for skill_id, def in pairs(raw_skill_data) do
                if def then
                    local toggle_result = self:_ProcessToggle(skill_id, def)
                    if toggle_result then
                        if toggle_result.effect_def then
                            effect_defs[toggle_result.effect_id] = toggle_result.effect_def
                        end
                        def.fn = function(inst, params, def)
                            inst.components.nikki_effect:Toggle(toggle_result.effect_id)
                            return true
                        end
                        def.toggle = nil
                    end

                    local processed_def, triggers, sub_skills = self:_ProcessDefaultTriggers(skill_id, def)
                    all_skills[skill_id] = processed_def
                    if triggers and next(triggers) then
                        trigger_data[skill_id] = triggers
                    end
                    for sub_id, sub_def in pairs(sub_skills) do
                        all_skills[sub_id] = sub_def
                    end
                end
            end

            if next(effect_defs) then
                self.effect_resolver:AddDefs(effect_defs)
            end

            if next(all_skills) then
                self.skill_resolver:AddDefs(all_skills)
            end

            if next(trigger_data) then
                self.trigger_resolver:AddDefs(trigger_data)
            end

            log.debug("[NikkiManager] Loaded and processed skills from '%s'.", defs.skill)
        end
    end

    -- 3. 加载 State
    if defs.state then
        local state_cfg = defs.state
        local state_file = type(state_cfg) == "table" and state_cfg.file or
            (type(state_cfg) == "string" and state_cfg or nil)
        if state_file then
            local raw_state_data = require(state_file)
            if raw_state_data then
                self.state_resolver:AddDefs(raw_state_data)
                log.debug("[NikkiManager] Loaded states from '%s'.", state_file)
            end
        end
        -- 提取 basic 和 default 并保存到 resolver
        if type(state_cfg) == "table" then
            if state_cfg.basic then
                self.state_resolver:SetBasicState(state_cfg.basic)
            end
            if state_cfg.default then
                self.state_resolver:SetDefaultState(state_cfg.default)
            end
        end
    end
end

-- ============================================================
-- 新增：加载 Framework 资源（食谱、动作、SG、图集）
-- 路径均位于 config.defs 下
-- ============================================================
function NikkiManager:_LoadFrameworkResources(config, mod_env)
    local defs = config.defs
    if not defs or type(defs) ~= "table" then
        return
    end

    -- 获取 Mod API（优先 mod_env，否则全局）
    local function getAPI(name)
        return mod_env[name] or _G[name]
    end

    local AddRecipe2 = getAPI("AddRecipe2")
    local AddDeconstructRecipe = getAPI("AddDeconstructRecipe")
    local AddIngredientValues = getAPI("AddIngredientValues")
    local AddCookerRecipe = getAPI("AddCookerRecipe")
    local AddAction = getAPI("AddAction")
    local AddStategraphActionHandler = getAPI("AddStategraphActionHandler")
    local AddComponentAction = getAPI("AddComponentAction")
    local AddStategraphState = getAPI("AddStategraphState")
    local AddStategraphEvent = getAPI("AddStategraphEvent")
    local RegisterInventoryItemAtlas = getAPI("RegisterInventoryItemAtlas")
    local ActionHandler = getAPI("ActionHandler") or ActionHandler
    local EventHandler = getAPI("EventHandler") or EventHandler

    -- 辅助加载函数
    local function loadFile(path, callback)
        if not path then return end
        local ok, data = pcall(require, path)
        if ok then
            callback(data)
            log.info("[NikkiManager] Loaded framework resource: %s", path)
        else
            log.error("[NikkiManager] Failed to load framework resource '%s': %s", path, tostring(data))
        end
    end

    -- 1. 处理配方（recipes）
    if defs.recipes then
        loadFile(defs.recipes, function(recipes_data)
            -- 制作配方
            if recipes_data.Recipes then
                for _, data in pairs(recipes_data.Recipes) do
                    local config = {
                        placer = data.placer,
                        min_spacing = data.min_spacing,
                        nounlock = data.nounlock,
                        numtogive = data.numtogive,
                        builder_tag = data.builder_tag,
                        atlas = data.atlas,
                        image = data.image,
                        testfn = data.testfn,
                        product = data.product,
                        build_mode = data.build_mode,
                    }
                    local tech_required = data.level or TECH.NONE
                    local filters = data.filters or {}
                    if data.tab and #filters == 0 then
                        table.insert(filters, data.tab)
                    end
                    if #filters == 0 then
                        table.insert(filters, "MODS")
                    end
                    AddRecipe2(data.name, data.ingredients, tech_required, config, filters)
                end
            end

            -- 分解配方
            if recipes_data.DeconstructRecipes then
                for _, data in pairs(recipes_data.DeconstructRecipes) do
                    AddDeconstructRecipe(data.name, data.return_ingredients)
                end
            end

            -- 食物值
            if recipes_data.IngredientValues then
                for _, data in pairs(recipes_data.IngredientValues) do
                    AddIngredientValues(data.names, data.tags, data.cancook, data.candry)
                end
            end

            -- 烹饪配方
            if recipes_data.CookerRecipes then
                for cooker, recipes in pairs(recipes_data.CookerRecipes) do
                    for _, recipe in ipairs(recipes) do
                        AddCookerRecipe(cooker, recipe)
                    end
                end
            end
        end)
    end

    -- 2. 处理动作（actions）
    if defs.actions then
        loadFile(defs.actions, function(actions_data)
            if actions_data.actions then
                for _, action_data in pairs(actions_data.actions) do
                    local action = AddAction(action_data.id, action_data.str, action_data.fn)
                    if action_data.actiondata then
                        for k, data in pairs(action_data.actiondata) do
                            action[k] = data
                        end
                    end
                    if action_data.state then
                        AddStategraphActionHandler("wilson", ActionHandler(action, action_data.state))
                        AddStategraphActionHandler("wilson_client", ActionHandler(action, action_data.state))
                    end
                end
            end

            if actions_data.component_actions then
                for _, v in pairs(actions_data.component_actions) do
                    local parm_idx = v.type == "POINT" and -3 or -2
                    local testfn = function(...)
                        local actions = select(parm_idx, ...)
                        for _, data in pairs(v.tests) do
                            if data and data.testfn and data.testfn(...) then
                                data.action = string.upper(data.action)
                                table.insert(actions, ACTIONS[data.action])
                            end
                        end
                    end
                    AddComponentAction(v.type, v.component, testfn)
                end
            end
        end)
    end

    -- 3. 处理 SG（状态图）
    if defs.sg then
        loadFile(defs.sg, function(sg_data)
            if sg_data.sgs then
                for sg, sg_states in pairs(sg_data.sgs) do
                    for _, state in pairs(sg_states) do
                        AddStategraphState(sg, state)
                    end
                end
            end
            if sg_data.events then
                for sg, event_data in pairs(sg_data.events) do
                    for event, fn in pairs(event_data) do
                        AddStategraphEvent(sg, EventHandler(event, fn))
                    end
                end
            end
        end)
    end

    -- 4. 处理图集注册（images）
    if defs.images then
        loadFile(defs.images, function(images_data)
            for _, atlas_data in ipairs(images_data) do
                local atlas = resolvefilepath(atlas_data.atlas)
                if atlas_data.images then
                    for _, image_name in ipairs(atlas_data.images) do
                        RegisterInventoryItemAtlas(atlas, string.format("%s.tex", image_name))
                    end
                end
            end
        end)
    end
end

-- ============================================================
-- _ProcessToggle：处理单个技能的 toggle
-- ============================================================
function NikkiManager:_ProcessToggle(skill_id, def)
    if not def.toggle then
        return nil
    end

    if type(def.toggle) == "string" then
        return { effect_id = def.toggle }
    elseif type(def.toggle) == "table" then
        local effect_id = GenerateToggleEffectId(skill_id)
        local effect_def = def.toggle
        effect_def.stack = { mode = "toggle" }
        return { effect_id = effect_id, effect_def = effect_def }
    else
        log.error("[NikkiManager] Skill '%s' has invalid toggle type: expected string or table.", skill_id)
        return nil
    end
end

-- ============================================================
-- _ProcessDefaultTriggers：处理单个技能的 default_triggers
-- ============================================================
function NikkiManager:_ProcessDefaultTriggers(skill_id, def)
    local processed_def = {}
    local triggers = {}
    local sub_skills = {}

    for k, v in pairs(def) do
        if k ~= "default_triggers" then
            processed_def[k] = v
        end
    end

    local default_triggers = def.default_triggers
    if not default_triggers then
        return processed_def, nil, {}
    end

    local trigger_types = { "events", "actions" }
    local sub_skill_list = {}

    for _, trigger_type in ipairs(trigger_types) do
        local trigger_map = default_triggers[trigger_type]
        if trigger_map then
            for trigger_key, trigger_value in pairs(trigger_map) do
                if not triggers[trigger_type] then
                    triggers[trigger_type] = {}
                end
                table.insert(triggers[trigger_type], trigger_key)

                if trigger_value ~= true then
                    local sub_skill_id = GenerateSubSkillId(skill_id, trigger_type, trigger_key)
                    local sub_def = self:_BuildSubSkillDef(skill_id, def, trigger_value)
                    sub_skills[sub_skill_id] = sub_def
                    table.insert(sub_skill_list, sub_skill_id)
                end
            end
        end
    end

    if #sub_skill_list > 0 then
        processed_def._sub_skills = sub_skill_list
    end

    return processed_def, triggers, sub_skills
end

-- ============================================================
-- _BuildSubSkillDef：构建子技能定义
-- ============================================================
function NikkiManager:_BuildSubSkillDef(skill_id, parent_def, trigger_value)
    local sub_def = {}

    if type(trigger_value) == "function" then
        trigger_value = { fn = trigger_value }
    end

    if type(trigger_value) == "table" then
        if trigger_value.fn ~= nil then
            sub_def.fn = trigger_value.fn
            if trigger_value.cost then sub_def.cost = trigger_value.cost end
            if trigger_value.cd then sub_def.cd = trigger_value.cd end
            if trigger_value.required_tags then sub_def.required_tags = trigger_value.required_tags end
        else
            sub_def.fn = parent_def.fn
            sub_def.cost = trigger_value.cost or parent_def.cost
            sub_def.cd = trigger_value.cd or parent_def.cd
            sub_def.required_tags = trigger_value.required_tags or parent_def.required_tags
        end
    else
        log.error("[NikkiManager] Invalid trigger_value type for skill '%s': %s", skill_id, type(trigger_value))
    end

    return sub_def
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
-- 装配分发
-- ============================================================
function NikkiManager:_ApplyTo(config, mod_env)
    local apply_to = config.apply_to or {}
    local custom_resources = config.custom_resources
    for tier_name, tier_cfg in pairs(apply_to) do
        if type(tier_cfg) == "table" then
            if type(tier_cfg.prefabs) == "table" then
                for _, prefab in ipairs(tier_cfg.prefabs) do
                    mod_env.AddPrefabPostInit(prefab, function(inst)
                        self:ApplyFrameworkToInst(inst, tier_name, custom_resources)
                    end)
                end
            end
            if type(tier_cfg.tag) == "string" then
                local tag_name = tier_cfg.tag
                mod_env.AddPrefabPostInitAny(function(inst)
                    if inst.HasTag and inst:HasTag(tag_name) then
                        self:ApplyFrameworkToInst(inst, tier_name, custom_resources)
                    end
                end)
            end
        end
    end
end

function NikkiManager:ApplyFrameworkToInst(inst, tier_name, custom_resources)
    local TIER_LEVELS = { skill = 2, player = 3 }
    local tier_level = TIER_LEVELS[tier_name] or 0

    inst:AddTag("nikki_framework")

    if tier_level >= 3 then
        -- HUD 处理
        inst:DoTaskInTime(0, function()
            if not TheNet:IsDedicated() and inst == ThePlayer then
                local indicator = SpawnPrefab("nikki_range_indicator")
                indicator:Attach(inst)
                inst.components.playeractionpicker.leftclickoverride = function(inst, target, position)
                    local actions = {}
                    if inst:HasTag("aiming_point") then
                        table.insert(actions, ACTIONS.TARGETING)
                        target = position
                    end
                    if #actions > 0 then
                        return inst.components.playeractionpicker:SortActionList(actions, target)
                    end
                    return {}, true
                end
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

    -- 从 resolver 获取 basic/default
    local basic_state = self.state_resolver:GetBasicState()
    local default_state = self.state_resolver:GetDefaultState()

    if inst.components.nikki_state and basic_state then
        inst.components.nikki_state:ApplyBasic(basic_state)
    end

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

function NikkiManager:GetTriggerResolver()
    return self.trigger_resolver
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
    return inst.components.nikki_skill:Execute(skill_id, params or {})
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
-- 公开 API：查询
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
