-- scripts/utils/resource_adapter.lua
local log = require("utils/log")

local ResourceAdapter = {}

-- ========================================================
-- 内部工厂：严格划分 Server 与 Client (基于字符串寻址)
-- ========================================================
local function CreateStrategy(config_data)
    local comp_cfg = config_data.component or {}
    local rep_cfg = config_data.replica or {}

    -- 全局只认一个唯一组件名
    local c_name = comp_cfg.name

    -- 读取重定向字符串，无则使用默认规范命名
    local fn_get_current = comp_cfg.get_current or "GetCurrent"
    local fn_do_delta = comp_cfg.do_delta or "DoDelta"
    local fn_add_regen = comp_cfg.add_regen or "SetRegenMod"
    local fn_remove_regen = comp_cfg.remove_regen or "RemoveRegenMod"

    local fn_get_percent = rep_cfg.get_percent or "GetPercent"
    local fn_get_max = rep_cfg.get_max or "GetMax"
    local fn_get_rate_scale = rep_cfg.get_rate_scale or "GetRateScale"

    local strategy = {
        server = {
            comp_name = c_name,
            get_current = function(comp)
                if type(comp[fn_get_current]) == "function" then return comp[fn_get_current](comp) end
                return comp.current or 0
            end,
            do_delta = function(comp, amount)
                if type(comp[fn_do_delta]) == "function" then comp[fn_do_delta](comp, amount, false) end
            end,
            add_regen = function(inst, comp, amount, src)
                if type(comp[fn_add_regen]) == "function" then comp[fn_add_regen](comp, inst, amount, src) end
            end,
            remove_regen = function(inst, comp, src)
                if type(comp[fn_remove_regen]) == "function" then comp[fn_remove_regen](comp, inst, src) end
            end
        },
        client = {
            -- UI 彻底使用伴生的 component_name 寻址
            get_percent = function(inst)
                local rep = inst.replica and inst.replica[c_name]
                if rep and type(rep[fn_get_percent]) == "function" then return rep[fn_get_percent](rep) end
                return 0
            end,
            get_max = function(inst)
                local rep = inst.replica and inst.replica[c_name]
                if not rep then return 100 end
                if type(rep[fn_get_max]) == "function" then return rep[fn_get_max](rep) end
                if type(rep.Max) == "function" then return rep:Max() end -- 向下兼容官方组件
                return 100
            end,
            get_rate_scale = function(inst)
                local rep = inst.replica and inst.replica[c_name]
                if rep and type(rep[fn_get_rate_scale]) == "function" then return rep[fn_get_rate_scale](rep) end
                return RATE_SCALE.NEUTRAL
            end
        }
    }
    return strategy
end

-- ========================================================
-- 资源策略映射表 (自带饥荒原生资源的特殊处理)
-- ========================================================
local RESOURCE_STRATEGIES = {
    health = {
        server = {
            comp_name = "health",
            get_current = function(comp) return comp.currenthealth or 0 end,
            do_delta = function(comp, amount) comp:DoDelta(amount, false, "nikki_skill") end,
            add_regen = function(inst, comp, amount, src) if comp.AddRegenSource then comp:AddRegenSource(inst, amount, 1, src) end end,
            remove_regen = function(inst, comp, src) if comp.RemoveRegenSource then comp:RemoveRegenSource(inst, src) end end
        },
    },
    sanity = {
        server = {
            comp_name = "sanity",
            get_current = function(comp) return comp.current or 0 end,
            do_delta = function(comp, amount) comp:DoDelta(amount, false) end,
            add_regen = function(inst, comp, amount, src) if comp.externalmodifiers then comp.externalmodifiers:SetModifier(inst, amount, src) end end,
            remove_regen = function(inst, comp, src) if comp.externalmodifiers then comp.externalmodifiers:RemoveModifier(inst, src) end end
        },
    },
    hunger = {
        server = {
            comp_name = "hunger",
            get_current = function(comp) return comp.current or 0 end,
            do_delta = function(comp, amount) comp:DoDelta(amount, false) end,
            add_regen = function(inst, comp, amount, src)
                if not inst._nikki_hunger_tasks then inst._nikki_hunger_tasks = {} end
                if inst._nikki_hunger_tasks[src] then inst._nikki_hunger_tasks[src]:Cancel() end
                inst._nikki_hunger_tasks[src] = inst:DoPeriodicTask(1, function()
                    if type(comp.DoDelta) == "function" then comp:DoDelta(amount, true) end
                end)
            end,
            remove_regen = function(inst, comp, src)
                if inst._nikki_hunger_tasks and inst._nikki_hunger_tasks[src] then
                    inst._nikki_hunger_tasks[src]:Cancel()
                    inst._nikki_hunger_tasks[src] = nil
                end
            end
        },
    },
}

setmetatable(RESOURCE_STRATEGIES, {
    __index = function(t, res_name)
        return CreateStrategy({ component = { name = res_name } })
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
    
    -- 1. 构建 Server / Client 策略
    RESOURCE_STRATEGIES[res_id] = CreateStrategy(config_data)
    
    -- 2. UI 配置归一化处理 (在注册时即补全所有默认约定)
    if config_data.ui then
        if config_data.ui == true then
            -- 极简简写：完全遵循标准约定填充
            RESOURCE_STRATEGIES[res_id].ui_config = {
                bank = res_id .. "badge",
                build = res_id .. "badge",
                anim = "anim",
            }
        elseif type(config_data.ui) == "table" then
            -- 自定义配置：缺什么补什么，默认 build 优先跟随 bank
            local bank = config_data.ui.bank or (res_id .. "badge")
            RESOURCE_STRATEGIES[res_id].ui_config = {
                bank = bank,
                build = config_data.ui.build or bank,
                anim = config_data.ui.anim or "anim",
            }
        end
    end

    log.debug("[ResourceAdapter] Registered custom resource logic: %s -> inst.components.%s", res_id, config_data.component.name)
end

-- ========================================================
-- 公开 API：UI 专用取值接口 (拒绝接口爆炸)
-- ========================================================
function ResourceAdapter.GetUIConfig(res_name)
    local strategy = RESOURCE_STRATEGIES[res_name]
    return strategy and strategy.ui_config or nil
end

function ResourceAdapter.GetUIValue(inst, res_name, key)
    local strategy = RESOURCE_STRATEGIES[res_name]
    if not strategy or not strategy.client then return nil end

    if key == "percent" then return strategy.client.get_percent(inst)
    elseif key == "max" then return strategy.client.get_max(inst)
    elseif key == "rate_scale" then return strategy.client.get_rate_scale(inst)
    end
    return nil
end

-- ========================================================
-- 公开 API：服务端 Server 路由分发
-- ========================================================

function ResourceAdapter.GetComponent(inst, res_name)
    local strategy = RESOURCE_STRATEGIES[res_name]
    return strategy and strategy.server and strategy.server.comp_name and inst.components[strategy.server.comp_name] or nil
end

function ResourceAdapter.GetCurrent(inst, res_name)
    local strategy = RESOURCE_STRATEGIES[res_name]
    local comp = ResourceAdapter.GetComponent(inst, res_name)
    if not comp or not strategy then return 0 end
    return strategy.server.get_current(comp)
end

function ResourceAdapter.DoDelta(inst, res_name, amount)
    local strategy = RESOURCE_STRATEGIES[res_name]
    local comp = ResourceAdapter.GetComponent(inst, res_name)
    if comp and strategy then strategy.server.do_delta(comp, amount) end
end

function ResourceAdapter.SetRegen(inst, res_name, amount, source_id)
    local strategy = RESOURCE_STRATEGIES[res_name]
    local comp = ResourceAdapter.GetComponent(inst, res_name)
    if comp and strategy then strategy.server.add_regen(inst, comp, amount, source_id) end
end

function ResourceAdapter.RemoveRegen(inst, res_name, source_id)
    local strategy = RESOURCE_STRATEGIES[res_name]
    local comp = ResourceAdapter.GetComponent(inst, res_name)
    if comp and strategy then strategy.server.remove_regen(inst, comp, source_id) end
end

return ResourceAdapter