---@diagnostic disable: need-check-nil
-- scripts/tests/core/test_nikki_framework_manager.lua
local TestUtils = require("tests/test_utils")
local NikkiFrameworkManager = require("nikki_framework_manager")
local ResolverRegistry = require("nikki_resolver_registry")

return function()
    local suite = TestUtils.CreateSuite("NikkiFrameworkManager (Deep)")
    local inst = suite:Track(CreateEntity())

    -- 【新增修复】：为测试裸实体伪造一个 AnimState 替身，防止 state 切换时空指针崩溃
    inst.AnimState = {
        SetBank = function() end,
        SetBuild = function() end,
        PlayAnimation = function() end,
        PushAnimation = function() end,
        OverrideSymbol = function() end,
        ClearOverrideSymbol = function() end,
    }
    
    -- (为了防止其它组件在后续测试中也找茬，顺手给个伪造的 Transform)
    inst.Transform = { GetWorldPosition = function() return 0, 0, 0 end }

    package.loaded["mock_skill_data"] = {
        ["fireball"] = { default_triggers = { keys = { ["KEY_V"] = true } } }
    }
    package.loaded["mock_state_data"] = {
        ["basic"] = { skills = { "fireball" }, triggers = { keys = { ["KEY_V"] = false } } }, 
        ["fire_mode"] = { skills = { "extra_skill" } }
    }
    package.loaded["mock_effect_data"] = {}

    local post_init_fn = nil
    local mock_env = {
        AddPrefabPostInit = function(prefab, fn)
            if prefab == "samansha" then post_init_fn = fn end
        end
    }

    ACTIONS = ACTIONS or {}
    local old_action_fn = function(act) return "OLD_RESULT" end
    ACTIONS.MOCK_ACTION = { id = "MOCK_ACTION", fn = old_action_fn }

    local config = {
        samansha_profile = {
            basic_state = "basic",
            prefabs = { "samansha" },
            skill = "mock_skill_data",
            state = "mock_state_data",
            effect = "mock_effect_data",
            custom_resources = {
                ["mana"] = { component = { name = "nikki_mana" } }
            }
        }
    }
    NikkiFrameworkManager.Init(config, mock_env)

    local resolvers = {
        effect = ResolverRegistry.Get("effect"),
        skill = ResolverRegistry.Get("skill"),
        state = ResolverRegistry.Get("state"),
    }
    suite:assert(resolvers.effect ~= nil and resolvers.skill ~= nil and resolvers.state ~= nil,
        "Init 成功将三个 Resolver 实例化并注入 Registry")

    local fire_mode_def = resolvers.state:GetStateDef("fire_mode")
    suite:assert(fire_mode_def.skills[1] == "fireball", "子形态成功继承了 basic 的 skills")
    suite:assert(fire_mode_def.compiled_triggers.keys["KEY_V"] == nil, "basic 中的 trigger overrides (false) 成功清除了 V 键绑定")
    suite:assert(post_init_fn ~= nil, "成功向 mod_env 注册了预制物钩子")

    local old_ismastersim = TheWorld.ismastersim
    TheWorld.ismastersim = true
    post_init_fn(inst)
    TheWorld.ismastersim = old_ismastersim

    suite:assert(inst.components.nikki_skill ~= nil, "PostInit 成功为实体挂载核心组件")
    suite:assert(inst.components.nikki_state:GetResolver() == resolvers.state, "PostInit 成功为组件注入 Resolver")
    
    suite:assert(inst.components.nikki_mana ~= nil, "PostInit 成功自动挂载 config 中注册的缺失资源组件")

    suite:assert(ACTIONS.MOCK_ACTION._nikki_hooked == nil, "未被配置中指定的 Action 不会被无故 Hook")

    package.loaded["mock_state_data"]["fire_mode"].triggers = { 
        actions = { MOCK_ACTION = "extra_skill" } 
    }
    NikkiFrameworkManager.Init(config, mock_env) 

    suite:assert(ACTIONS.MOCK_ACTION._nikki_hooked == true, "配置中的 Action 成功被 Hook")

    local cast_action_called = false
    inst.components.nikki_skill_trigger.CastAction = function()
        cast_action_called = true; return "NEW_RESULT"
    end
    local mock_act = { action = ACTIONS.MOCK_ACTION, doer = inst }

    local res = ACTIONS.MOCK_ACTION.fn(mock_act)
    suite:assert(cast_action_called == true, "被劫持的动作成功路由至 Trigger 组件")

    package.loaded["mock_skill_data"] = nil
    package.loaded["mock_state_data"] = nil
    package.loaded["mock_effect_data"] = nil
    ACTIONS.MOCK_ACTION = nil

    suite:Cleanup()
end