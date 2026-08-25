local log = require("utils/log")
local ResourceAdapter = {}

-- ========================================================
-- 内部工厂：严格划分 Server 与 Client (基于字符串寻址)
-- ========================================================
-- ========================================================
-- 内部工厂：严格划分 Server 与 Client (基于字符串寻址)
-- ========================================================
local function CreateStrategy(config_data)
    local comp_cfg = config_data.component or {}
    local rep_cfg = config_data.replica or {}
    local c_name = comp_cfg.name

    -- 默认的方法寻址键名
    local fn_get_current = comp_cfg.get_current or "GetCurrent"
    local fn_do_delta = comp_cfg.do_delta or "DoDelta"
    local fn_set_regen = comp_cfg.set_regen or "SetRegenMod"
    local fn_remove_regen = comp_cfg.remove_regen or "RemoveRegenMod"

    local fn_get_percent = rep_cfg.get_percent or "GetPercent"
    local fn_get_max = rep_cfg.get_max or "GetMax"
    local fn_get_rate_scale = rep_cfg.get_rate_scale or "GetRateScale"

    -- 【优化】：提前解包并赋默认空表，彻底消灭又臭又长的 nil 判断
    local srv = config_data.server or {}
    local clt = config_data.client or {}

    -- 基础策略：优先取用 config 传入的自定义覆盖函数，若没有则走字符串泛型寻址
    local strategy = {
        server = {
            comp_name = c_name,

            get_current = srv.get_current or function(comp)
                if type(comp[fn_get_current]) == "function" then return comp[fn_get_current](comp) end
                return comp.current or 0
            end,

            do_delta = srv.do_delta or function(comp, amount)
                if type(comp[fn_do_delta]) == "function" then comp[fn_do_delta](comp, amount, false) end
            end,

            set_regen = srv.set_regen or function(inst, comp, rate, key)
                if type(comp[fn_set_regen]) == "function" then comp[fn_set_regen](comp, inst, rate, key) end
            end,

            remove_regen = srv.remove_regen or function(inst, comp, rate, key)
                if type(comp[fn_remove_regen]) == "function" then comp[fn_remove_regen](comp, inst, key, rate) end
            end
        },
        client = {
            get_percent = clt.get_percent or function(inst)
                local rep = inst.replica and inst.replica[c_name]
                if rep and type(rep[fn_get_percent]) == "function" then return rep[fn_get_percent](rep) end
                return 0
            end,

            get_max = clt.get_max or function(inst)
                local rep = inst.replica and inst.replica[c_name]
                if not rep then return 100 end
                if type(rep[fn_get_max]) == "function" then return rep[fn_get_max](rep) end
                if type(rep.Max) == "function" then return rep:Max() end
                return 100
            end,

            get_rate_scale = clt.get_rate_scale or function(inst)
                local rep = inst.replica and inst.replica[c_name]
                if rep and type(rep[fn_get_rate_scale]) == "function" then return rep[fn_get_rate_scale](rep) end
                return RATE_SCALE.NEUTRAL
            end
        }
    }
    return strategy
end

-- ========================================================
-- 资源策略映射表 (初始为空)
-- ========================================================
local RESOURCE_STRATEGIES = {}

setmetatable(RESOURCE_STRATEGIES, {
    __index = function(t, res_id)
        return CreateStrategy({ component = { name = res_id } })
    end
})

-- ========================================================
-- 公开 API：注册接口
-- ========================================================
function ResourceAdapter.RegisterStrategy(res_id, config_data)
    if not config_data or not config_data.component or not config_data.component.name then
        log.warn("[ResourceAdapter] Cannot register resource '%s': missing 'component.name'", tostring(res_id))
        return
    end

    RESOURCE_STRATEGIES[res_id] = CreateStrategy(config_data)

    if config_data.ui then
        if config_data.ui == true then
            RESOURCE_STRATEGIES[res_id].ui_config = {
                bank = res_id .. "badge",
                build = res_id .. "badge",
                anim = "anim",
            }
        elseif type(config_data.ui) == "table" then
            local bank = config_data.ui.bank or (res_id .. "badge")
            RESOURCE_STRATEGIES[res_id].ui_config = {
                bank = bank,
                build = config_data.ui.build or bank,
                anim = config_data.ui.anim or "anim",
            }
        end
    end

    log.debug("[ResourceAdapter] Registered custom resource logic: %s -> inst.components.%s", res_id,
        config_data.component.name)
end

-- ========================================================
-- 内部辅助：获取组件和策略
-- ========================================================
local function GetComponentAndStrategy(inst, res_id)
    local strategy = RESOURCE_STRATEGIES[res_id]
    if not strategy then
        log.warn("[ResourceAdapter] No strategy registered for resource: %s", tostring(res_id))
        return nil, nil
    end
    local comp = inst.components[strategy.server.comp_name]
    if not comp then
        log.warn("[ResourceAdapter] Component '%s' not found for resource: %s", tostring(strategy.server.comp_name),
            tostring(res_id))
        return nil, nil
    end
    return comp, strategy
end

local function ValidateRate(rate, func_name)
    if rate < 0 then
        log.warn("[ResourceAdapter] %s called with negative rate (%.2f), clamping to 0", func_name, rate)
        return 0
    end
    return rate
end

-- ========================================================
-- 公开 API：UI / 服务端查询与操作 (保持不变)
-- ========================================================
function ResourceAdapter.GetUIConfig(res_id)
    local strategy = RESOURCE_STRATEGIES[res_id]
    return strategy and strategy.ui_config or nil
end

function ResourceAdapter.GetUIValue(inst, res_id, func_key)
    local strategy = RESOURCE_STRATEGIES[res_id]
    if not strategy or not strategy.client then return nil end

    if func_key == "percent" then
        return strategy.client.get_percent(inst)
    elseif func_key == "max" then
        return strategy.client.get_max(inst)
    elseif func_key == "rate_scale" then
        return strategy.client.get_rate_scale(inst)
    end
    return nil
end

function ResourceAdapter.GetCurrent(inst, res_id)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if not comp or not strategy then return 0 end
    return strategy.server.get_current(comp)
end

function ResourceAdapter.DoDelta(inst, res_id, amount)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if comp and strategy then strategy.server.do_delta(comp, amount) end
end

function ResourceAdapter.SetRegen(inst, res_id, rate, key)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if not comp or not strategy then return end
    rate = ValidateRate(rate, "SetRegen")
    if rate == 0 then
        ResourceAdapter.RemoveRegen(inst, res_id, 0, key)
        return
    end
    strategy.server.set_regen(inst, comp, rate, key)
end

function ResourceAdapter.SetDrain(inst, res_id, rate, key)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if not comp or not strategy then return end
    rate = ValidateRate(rate, "SetDrain")
    if rate == 0 then
        ResourceAdapter.RemoveDrain(inst, res_id, 0, key)
        return
    end
    strategy.server.set_regen(inst, comp, -rate, key)
end

function ResourceAdapter.RemoveRegen(inst, res_id, rate, key)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if not comp or not strategy then return end
    strategy.server.remove_regen(inst, comp, rate, key)
end

function ResourceAdapter.RemoveDrain(inst, res_id, rate, key)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if not comp or not strategy then return end
    strategy.server.remove_regen(inst, comp, rate, key)
end

function ResourceAdapter.GetAllKeys()
    local keys = {}
    for k, _ in pairs(RESOURCE_STRATEGIES) do
        table.insert(keys, k)
    end
    return keys
end


return ResourceAdapter
