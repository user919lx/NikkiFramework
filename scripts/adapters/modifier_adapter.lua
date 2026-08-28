local log = require("utils/log")

local ModifierAdapter = {}

-- 属性修饰策略表，初始为空，全靠外部配置注入
local MODIFIER_STRATEGIES = {}

-- 对外开放的注册接口，允许配置字典注入新的属性算法
function ModifierAdapter.RegisterStrategy(mod_type, strategy, env)
    if not strategy or type(strategy.apply) ~= "function" or type(strategy.remove) ~= "function" then
        log.warn("[ModifierAdapter] Cannot register strategy for '%s': missing apply or remove function",
            tostring(mod_type))
        return
    end

    -- 如果策略提供了 init 函数，在注册时执行（全局一次），并传入 mod 环境
    if type(strategy.init) == "function" then
        local ok, err = pcall(strategy.init, env)
        if not ok then
            log.error("[ModifierAdapter] Strategy '%s' init failed: %s", tostring(mod_type), tostring(err))
            return
        end
        log.debug("[ModifierAdapter] Strategy '%s' initialized globally", tostring(mod_type))
    end

    MODIFIER_STRATEGIES[mod_type] = strategy
    log.debug("[ModifierAdapter] Registered custom modifier strategy: %s", tostring(mod_type))
end

function ModifierAdapter.Apply(inst, mod_type, value, effect_id)
    local strategy = MODIFIER_STRATEGIES[mod_type]
    if strategy then
        log.debug("[ModifierAdapter] Applying modifier '%s' with value %.2f to %s (effect_id: %s)", tostring(mod_type),
            value, tostring(inst), tostring(effect_id))
        strategy.apply(inst, value, effect_id)
    else
        log.warn("[ModifierAdapter] Unsupported mod_type or missing component: " .. tostring(mod_type))
    end
end

function ModifierAdapter.Remove(inst, mod_type, effect_id)
    local strategy = MODIFIER_STRATEGIES[mod_type]
    if strategy then
        log.debug("[ModifierAdapter] Removing modifier '%s' with effect_id '%s' from %s", tostring(mod_type),
            tostring(effect_id), tostring(inst))
        strategy.remove(inst, effect_id)
    end
end

function ModifierAdapter.GetAllKeys()
    local keys = {}
    for k, _ in pairs(MODIFIER_STRATEGIES) do
        table.insert(keys, k)
    end
    return keys
end
return ModifierAdapter
