-- scripts/tests/core/test_nikki_framework_manager.lua
local TestUtils = require("tests/test_utils")
local NikkiFrameworkManager = require("nikki_framework_manager")
local ResolverRegistry = require("nikki_resolver_registry")

return function()
    local suite = TestUtils.CreateSuite("NikkiFrameworkManager (Deep)")
    local inst = suite:Track(CreateEntity())

    -- A. 深度 Mock require 数据
    package.loaded["mock_skill_data"] = {
        ["fireball"] = { default_triggers = { keys = { ["KEY_V"] = true } } }
    }
    package.loaded["mock_state_data"] = {
        ["basic"] = { skills = { "fireball" }, triggers = { keys = { ["KEY_V"] = false } } }, 
        ["fire_mode"] = { skills = { "extra_skill" } }
    }
    package.loaded["mock_effect_data"] = {}

    -- B. Mock mod_env 以捕获 AddPrefabPostInit
    local post_init_fn = nil
    local mock_env = {
        AddPrefabPostInit = function(prefab, fn)
            if prefab == "samansha" then post_init_fn = fn end
        end
    }

    -- C. Mock 饥荒动作拦截系统 (ACTIONS)
    ACTIONS = ACTIONS or {}
    local old_action_fn = function(act) return "OLD_RESULT" end
    ACTIONS.MOCK_ACTION = { id = "MOCK_ACTION", fn = old_action_fn }

    -- D. 执行主装配逻辑
    local config = {
        samansha_profile = {
            basic_state = "basic",
            prefabs = { "samansha" },
            skill = "mock_skill_data",
            state = "mock_state_data",
            effect = "mock_effect_data"
        }
    }
    NikkiFrameworkManager.Init(config, mock_env)

    -- E. 断言 1: Registry 装配结果
    local resolvers = ResolverRegistry.Get("samansha")
    suite:assert(resolvers ~= nil and resolvers.skill and resolvers.state, "Init 成功将三个 Resolver 实例化并注入 Registry")

    -- F. 断言 2: PrecompileStates 编译逻辑 (继承与屏蔽)
    local fire_mode_def = resolvers.state:GetStateDef("fire_mode")
    suite:assert(fire_mode_def.skills[1] == "fireball", "子形态成功继承了 basic 的 skills")
    suite:assert(fire_mode_def.compiled_triggers.keys["KEY_V"] == nil, "basic 中的 trigger overrides (false) 成功清除了 V 键绑定")

    -- G. 断言 3: AddPrefabPostInit 挂载能力
    suite:assert(post_init_fn ~= nil, "成功向 mod_env 注册了预制物钩子")

    -- 模拟生成实体并调用 PostInit
    local old_ismastersim = TheWorld.ismastersim
    TheWorld.ismastersim = true
    post_init_fn(inst)
    TheWorld.ismastersim = old_ismastersim

    suite:assert(inst.components.nikki_skill ~= nil, "PostInit 成功为实体挂载核心组件")
    suite:assert(inst.components.nikki_state:GetResolver() == resolvers.state, "PostInit 成功为组件注入 Resolver")

    -- H. 断言 4: HookActionForSkill 动作拦截能力
    suite:assert(ACTIONS.MOCK_ACTION._nikki_hooked == nil, "未被配置中指定的 Action 不会被无故 Hook")

    -- 【核心修复】：必须绑定一个具体的技能名 (如 "extra_skill")，而不能写 true！
    package.loaded["mock_state_data"]["fire_mode"].triggers = { 
        actions = { MOCK_ACTION = "extra_skill" } 
    }
    NikkiFrameworkManager.Init(config, mock_env) 

    suite:assert(ACTIONS.MOCK_ACTION._nikki_hooked == true, "配置中的 Action 成功被 Hook")

    -- 测试劫持后的执行路由
    local cast_action_called = false
    inst.components.nikki_skill_trigger.CastAction = function()
        cast_action_called = true; return "NEW_RESULT"
    end
    local mock_act = { action = ACTIONS.MOCK_ACTION, doer = inst }

    local res = ACTIONS.MOCK_ACTION.fn(mock_act)
    suite:assert(cast_action_called == true, "被劫持的动作成功路由至 Trigger 组件")

    -- 清理内存
    package.loaded["mock_skill_data"] = nil
    package.loaded["mock_state_data"] = nil
    package.loaded["mock_effect_data"] = nil
    ACTIONS.MOCK_ACTION = nil

    suite:Cleanup()
end