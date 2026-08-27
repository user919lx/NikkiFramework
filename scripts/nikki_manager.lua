-- scripts/nikki_manager.lua
local log = require("utils/log")
local EffectResolver = require("resolvers/effect_resolver")
local SkillResolver = require("resolvers/skill_resolver")
local StateResolver = require("resolvers/state_resolver")
local TriggerResolver = require("resolvers/trigger_resolver")
local ModifierAdapter = require("adapters/modifier_adapter")
local ResourceAdapter = require("adapters/resource_adapter")
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

--- 检查目标是否具有基础交互有效性
local function IsValidTargetForSkill(target)
    if not target or not target:IsValid() then return false end
    -- 排除不可交互对象与进入 Limbo 状态（如在背包中、消失中）的实体
    if target:HasTag("INLIMBO") then
        return false
    end
    return true
end

--- 检查是否需要让位给原版核心交互（如骑乘/上下牛）
local function ShouldYieldToNativeInteractions(inst, target)
    if not inst.replica.rider then return false end
    -- 当目标可骑乘、且未被拴住，且满足骑乘标签时，优先让位给骑乘交互
    if target and target:HasTag("rideable") and not target:HasTag("hitched") then
        if not target:HasTag("dogrider_only") or inst:HasTag("dogrider") then
            return true
        end
    end
    return false
end

local function MakeClickOverride(is_right_click)
    return function(inst, target, pos)
        if not inst or not inst:IsValid() then return {}, true end
        if is_right_click and target then
            if not IsValidTargetForSkill(target) or ShouldYieldToNativeInteractions(inst, target) then
                return {}, true
            end
        end
        local cmp_caster = inst.components.nikki_skill_caster
        if cmp_caster then
            local act = cmp_caster:GetAvailableSkillAction(target, pos, is_right_click)
            if act then
                return { act }
            end
        end
        return {}, true
    end
end

-- ============================================================
-- 统一管理器（全局单例）
-- ============================================================
local NikkiManager = Class(function(self)
    self.resolvers = {}

    self._settings_file = "nikki_framework_settings"
    self._settings = {
        show_range = true,
    }
    self._settings_loaded = false

    self._is_initialized = false
    self._hooks_installed = false
end)

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
    self:_LoadFrameworkResources(config, mod_env)
    self:_ApplyTo(config, mod_env)
    log.info("[NikkiManager] Mod %s registered.", tostring(mod_env.modname))
end

function NikkiManager:_CreateResolvers()
    self.resolvers = {
        effect = EffectResolver(),
        skill = SkillResolver(),
        state = StateResolver(),
        trigger = TriggerResolver(),
    }
end

function NikkiManager:_InstallTriggerHooks(env)
    if self._hooks_installed then
        log.warn("[NikkiManager] Trigger hooks already installed.")
        return
    end

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

function NikkiManager:_LoadDefs(config)
    local defs = config.defs
    if not defs then return end

    local effect_resolver = self:GetResolver("effect")
    local skill_resolver = self:GetResolver("skill")
    local state_resolver = self:GetResolver("state")
    local trigger_resolver = self:GetResolver("trigger")

    -- 1. 加载 Effect
    if defs.effect and effect_resolver then
        local effect_data = require(defs.effect)
        if effect_data then
            effect_resolver:AddDefs(effect_data)
            log.debug("[NikkiManager] Loaded effects from '%s'.", defs.effect)
        end
    end

    -- 2. 加载并编译 Skill
    if defs.skill and skill_resolver and trigger_resolver then
        local raw_skill_data = require(defs.skill)
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
                        def.is_toggle = true
                        def.toggle = nil
                    end

                    local new_skills, new_triggers = self:_ProcessDefaultTriggers(skill_id, def)

                    for sid, sdef in pairs(new_skills) do
                        all_skills[sid] = sdef
                    end

                    for sid, trigs in pairs(new_triggers) do
                        trigger_data[sid] = trigs
                    end
                end
            end

            if next(effect_defs) and effect_resolver then
                effect_resolver:AddDefs(effect_defs)
            end

            if next(all_skills) then
                skill_resolver:AddDefs(all_skills)
            end

            if next(trigger_data) then
                trigger_resolver:AddDefs(trigger_data)
            end

            log.debug("[NikkiManager] Loaded and processed skills from '%s'.", defs.skill)
        end
    end

    -- 3. 加载 State
    if defs.state and state_resolver then
        local raw_state_data = require(defs.state)
        if raw_state_data then
            state_resolver:AddDefs(raw_state_data)
            log.debug("[NikkiManager] Loaded states from '%s'.", defs.state)
        end
    end
end

function NikkiManager:_LoadFrameworkResources(config, mod_env)
    local defs = config.defs
    if not defs or type(defs) ~= "table" then return end

    local function getAPI(name) return mod_env[name] or _G[name] end

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

    if defs.recipes then
        loadFile(defs.recipes, function(recipes_data)
            if recipes_data.Recipes then
                for _, data in pairs(recipes_data.Recipes) do
                    local cfg = {
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
                    if data.tab and #filters == 0 then table.insert(filters, data.tab) end
                    if #filters == 0 then table.insert(filters, "MODS") end
                    AddRecipe2(data.name, data.ingredients, tech_required, cfg, filters)
                end
            end
            if recipes_data.DeconstructRecipes then
                for _, data in pairs(recipes_data.DeconstructRecipes) do
                    AddDeconstructRecipe(data.name, data.return_ingredients)
                end
            end
            if recipes_data.IngredientValues then
                for _, data in pairs(recipes_data.IngredientValues) do
                    AddIngredientValues(data.names, data.tags, data.cancook, data.candry)
                end
            end
            if recipes_data.CookerRecipes then
                for cooker, recipes in pairs(recipes_data.CookerRecipes) do
                    for _, recipe in ipairs(recipes) do
                        AddCookerRecipe(cooker, recipe)
                    end
                end
            end
        end)
    end

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

function NikkiManager:_ProcessToggle(skill_id, def)
    if not def.toggle then return nil end

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

function NikkiManager:_ProcessDefaultTriggers(skill_id, def)
    local skills_to_add = {}
    local triggers_to_add = {}

    local processed_def = {}
    for k, v in pairs(def) do
        if k ~= "default_triggers" then
            processed_def[k] = v
        end
    end
    skills_to_add[skill_id] = processed_def

    local default_triggers = def.default_triggers
    if not default_triggers then
        return skills_to_add, triggers_to_add
    end

    local trigger_types = { "events", "actions" }
    local sub_skill_list = {}
    local parent_triggers = {}

    for _, trigger_type in ipairs(trigger_types) do
        local trigger_map = default_triggers[trigger_type]
        if trigger_map then
            for trigger_key, trigger_value in pairs(trigger_map) do
                if trigger_value == true then
                    if not parent_triggers[trigger_type] then
                        parent_triggers[trigger_type] = {}
                    end
                    table.insert(parent_triggers[trigger_type], trigger_key)
                else
                    local sub_skill_id = GenerateSubSkillId(skill_id, trigger_type, trigger_key)
                    local sub_def = self:_BuildSubSkillDef(skill_id, def, trigger_value)

                    table.insert(sub_skill_list, sub_skill_id)
                    skills_to_add[sub_skill_id] = sub_def
                    triggers_to_add[sub_skill_id] = {
                        [trigger_type] = { trigger_key }
                    }
                end
            end
        end
    end

    if next(parent_triggers) then
        triggers_to_add[skill_id] = parent_triggers
    end

    if #sub_skill_list > 0 then
        processed_def._sub_skills = sub_skill_list
    end

    return skills_to_add, triggers_to_add
end

function NikkiManager:_BuildSubSkillDef(skill_id, parent_def, trigger_value)
    local sub_def = {}

    -- 【黑名单】：拦截主动机制与挂载副作用
    local BLACKLIST = {
        action = true,
        cost = true,
        cd = true,
        aoe = true,
        targeting = true,
        wheel = true,
        effects = true,          -- 防止子技能挂载时重复触发 Effect
        tags = true,             -- 防止重复挂载 Tag
        on_add = true,           -- 防止重复执行初始化
        on_remove = true,        -- 防止重复清理
        default_triggers = true, -- 防止无限递归
        toggle = true,
        client_only = true,
    }

    -- 封装黑名单元表：被访问的 key 如果在黑名单里，返回 nil；否则去父表里拿实时数据
    local filtered_mt = {
        __index = function(t, k)
            if not BLACKLIST[k] then
                return parent_def[k]
            end
            return nil
        end
    }

    if type(trigger_value) == "function" then
        -- 规则 1：独立的 fn
        sub_def.fn = trigger_value
        setmetatable(sub_def, filtered_mt)
    elseif type(trigger_value) == "table" then
        -- 无论是有 fn 还是没 fn，开发者手写的属性都要赋给子表自身
        for k, v in pairs(trigger_value) do
            sub_def[k] = v
        end

        if trigger_value.fn ~= nil then
            -- 规则 2：有独立 fn，挂载带黑名单的元表
            setmetatable(sub_def, filtered_mt)
        else
            -- 规则 3：没有独立 fn，挂载全量放行的元表
            setmetatable(sub_def, { __index = parent_def })
        end
    else
        log.error("[NikkiManager] Invalid trigger_value type for skill '%s': %s", skill_id, type(trigger_value))
    end

    sub_def.is_sub = true
    sub_def.parent_skill = skill_id
    return sub_def
end

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
            local initial_cfg = tier_cfg.initial
            if type(tier_cfg.prefabs) == "table" then
                for _, prefab in ipairs(tier_cfg.prefabs) do
                    mod_env.AddPrefabPostInit(prefab, function(inst)
                        self:ApplyFrameworkToInst(inst, tier_name, custom_resources)
                        if initial_cfg then
                            inst._nikki_initial = initial_cfg
                            self:ApplyInitial(inst, initial_cfg)
                        end
                    end)
                end
            end
            if type(tier_cfg.tag) == "string" then
                local tag_name = tier_cfg.tag
                mod_env.AddPrefabPostInitAny(function(inst)
                    if inst.HasTag and inst:HasTag(tag_name) then
                        self:ApplyFrameworkToInst(inst, tier_name, custom_resources)
                        if initial_cfg then
                            inst._nikki_initial = initial_cfg
                            self:ApplyInitial(inst, initial_cfg)
                        end
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
        inst:DoTaskInTime(0, function()
            if inst.components.playeractionpicker then
                inst.components.playeractionpicker.leftclickoverride = MakeClickOverride(false)
                inst.components.playeractionpicker.rightclickoverride = MakeClickOverride(true)
            end
            if not inst.components.nikki_skill_caster then
                inst:AddComponent("nikki_skill_caster")
            end
            if not TheNet:IsDedicated() and inst == ThePlayer then
                if not inst.range_indicator or not inst.range_indicator:IsValid() then
                    local indicator = SpawnPrefab("nikki_range_indicator")
                    indicator:SetOwner(inst)
                    inst.range_indicator = indicator
                end
                inst:PushEvent("skill_range_toggle_changed", { new_state = self:GetSetting("show_range") })
            end
        end)
    end

    if not TheWorld.ismastersim or tier_level < 2 then return end

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
    if not inst.components.nikki_skill_caster then inst:AddComponent("nikki_skill_caster") end
    if not inst.components.nikki_state then inst:AddComponent("nikki_state") end
end

-- ============================================================
-- 公开门面 API：初始状态与一键清理
-- ============================================================
--- 为实体应用初始配置（供内部与外部开发者直接调用）
function NikkiManager:ApplyInitial(inst, initial_cfg)
    log.debug("[NikkiManager] Applying initial config to %s: %s", tostring(inst), tostring(initial_cfg))
    if not inst or not initial_cfg then return false end
    -- 1. 初始技能
    if initial_cfg.skills and type(initial_cfg.skills) == "table" and inst.components.nikki_skill then
        log.debug("[NikkiManager] Adding initial skills to %s: %s", tostring(inst), tostring(initial_cfg.skills))
        inst.components.nikki_skill:AddSkills(initial_cfg.skills)
    end
    -- 2. 初始形态
    if initial_cfg.state and type(initial_cfg.state) == "string" and inst.components.nikki_state then
        log.debug("[NikkiManager] Setting initial state for %s: %s", tostring(inst), tostring(initial_cfg.state))
        inst.components.nikki_state:SetState(initial_cfg.state)
    end
    -- 3. 初始效果
    if initial_cfg.effects and type(initial_cfg.effects) == "table" and inst.components.nikki_effect then
        log.debug("[NikkiManager] Applying initial effects to %s: %s", tostring(inst), tostring(initial_cfg.effects))
        for _, effect_id in ipairs(initial_cfg.effects) do
            self:ApplyEffect(inst, effect_id, inst)
        end
    end
    -- 4. 初始按键绑定
    if initial_cfg.keys and type(initial_cfg.keys) == "table" then
        local parsed_keys = {}
        -- 单次循环：解析键码、缓存结果、并立刻给服务端组件装配
        for k, skill_id in pairs(initial_cfg.keys) do
            local key_code = type(k) == "string" and rawget(_G, k) or k
            parsed_keys[key_code] = skill_id
            if inst.components.nikki_skill_trigger then
                inst.components.nikki_skill_trigger:Add("keys", key_code, skill_id)
            end
        end
        -- 抽离 Replica 装配闭包
        local function add_keys_to_replica(_inst, keys)
            if _inst.replica and _inst.replica.nikki_skill_trigger then
                for key_code, skill_id in pairs(keys) do
                    _inst.replica.nikki_skill_trigger:AddKey(key_code, skill_id)
                end
            end
        end
        -- 鸭子判定与短轮询兜底
        if inst.replica and inst.replica.nikki_skill_trigger then
            add_keys_to_replica(inst, parsed_keys)
        else
            local max_retries = 20
            local retries = 0
            local task
            task = inst:DoPeriodicTask(0.1, function(_inst)
                -- 2. 闭包内部捕获外部的 retry_task
                if not _inst:IsValid() then
                    if task then
                        task:Cancel()
                        task = nil
                    end
                    return
                end

                if _inst.replica and _inst.replica.nikki_skill_trigger then
                    add_keys_to_replica(_inst, parsed_keys)
                    if task then
                        task:Cancel()
                        task = nil
                    end
                else
                    retries = retries + 1
                    if retries >= max_retries then
                        if task then
                            task:Cancel()
                            task = nil
                        end
                    end
                end
            end)
        end
    end
    return true
end

--- 一键清空实体上所有框架提供的状态、技能和效果
function NikkiManager:ClearAll(inst)
    if not inst or not inst:IsValid() then return false end
    if inst.components.nikki_effect then inst.components.nikki_effect:Clear() end
    if inst.components.nikki_state then inst.components.nikki_state:Clear() end
    if inst.replica and inst.replica.nikki_skill_trigger then inst.replica.nikki_skill_trigger:Clear() end
    if inst.components.nikki_skill_trigger then inst.components.nikki_skill_trigger:Clear() end
    if inst.components.nikki_skill then inst.components.nikki_skill:Clear() end
    return true
end

--- 将实体还原到装配时的预设状态
function NikkiManager:ResetToInitial(inst)
    if not inst or not inst._nikki_initial then return false end
    self:ClearAll(inst)
    self:ApplyInitial(inst, inst._nikki_initial)
    return true
end

-- ============================================================
-- 公开门面 API：行为操作
-- ============================================================
function NikkiManager:OpenSkillWheel(inst)
    local cmp_caster = inst and inst.components.nikki_skill_caster
    if cmp_caster then
        if cmp_caster:IsWheelOpen() then
            cmp_caster:CloseWheel()
        else
            cmp_caster:OpenWheel()
        end
    end
    return true
end

function NikkiManager:ExecuteSkill(inst, skill_id, params)
    local cmp_caster = inst and inst.components.nikki_skill_caster
    if cmp_caster then
        return cmp_caster:Execute(skill_id, params)
    end
    return true
end

function NikkiManager:ApplyEffect(target, effect_id, source)
    if not target or not effect_id then return false end
    if not target.components.nikki_effect then
        target:AddComponent("nikki_effect")
    end
    return target.components.nikki_effect:Apply(effect_id, source)
end

function NikkiManager:RemoveEffect(target, effect_id, force_all)
    if not target or not target.components.nikki_effect then return false end
    return target.components.nikki_effect:Remove(effect_id, force_all or true)
end

function NikkiManager:HasEffect(target, effect_id)
    if not target or not target.components.nikki_effect then return false end
    return target.components.nikki_effect:HasEffect(effect_id)
end

function NikkiManager:SetState(inst, state_id, force)
    if not inst or not inst.components.nikki_state then return false end
    return inst.components.nikki_state:SetState(state_id, force)
end

function NikkiManager:GetState(inst)
    if not inst or not inst.components.nikki_state then return nil end
    return inst.components.nikki_state:GetState()
end

-- ============================================================
-- 纯正服务定位器 API：获取 Resolver
-- ============================================================
function NikkiManager:GetResolver(resolver_name)
    return self.resolvers[resolver_name]
end

-- ============================================================
-- 适配器查询 API
-- ============================================================
function NikkiManager:GetModifierKeys()
    return ModifierAdapter.GetAllKeys()
end

function NikkiManager:GetResourceKeys()
    return ResourceAdapter.GetAllKeys()
end

-- ============================================================
-- 客户端设置 API
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
-- Wiki 数据导出 API
-- ============================================================

function NikkiManager:GetWikiData()
    local effect_resolver = self:GetResolver("effect")
    local skill_resolver = self:GetResolver("skill")
    local state_resolver = self:GetResolver("state")
    local trigger_resolver = self:GetResolver("trigger")

    local effect_items = effect_resolver:BuildWikiItemsByIds(effect_resolver:GetAllIds())
    local skill_items = skill_resolver:BuildWikiItemsByIds(skill_resolver:GetAllIds())
    local state_items = state_resolver:BuildWikiItemsByIds(state_resolver:GetAllIds())

    for _, item in pairs(skill_items) do
        item.triggers = trigger_resolver:GetTriggers(item.id)
    end

    return {
        effects = effect_items,
        skills = skill_items,
        states = state_items
    }
end

function NikkiManager:ExportWikiData()
    local data = self:GetWikiData()
    local success, str = pcall(json.encode, data)
    if success then
        TheSim:SetPersistentString("nikki_wiki_data.json", str, false)
        log.info("[NikkiManager] Successfully exported wiki data to 'nikki_wiki_data.json'")
    end
end

-- 单例出口
-- ============================================================
local instance = nil

function NikkiManager.GetInstance()
    if not instance then
        instance = NikkiManager()
    end
    return instance
end

return NikkiManager
