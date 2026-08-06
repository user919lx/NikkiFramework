-- scripts/utils/resource_adapter.lua
local log = require("utils/log")

local ResourceAdapter = {}

-- ========================================================
-- 内部工厂：生成标准的资源操作策略，并支持局部覆盖
-- ========================================================
local function CreateStrategy(comp_name, overrides)
    local strategy = {
        comp_name = comp_name,
        get_current = function(comp)
            if type(comp.GetCurrent) == "function" then return comp:GetCurrent() end
            return comp.current or 0
        end,
        do_delta = function(comp, amount)
            if type(comp.DoDelta) == "function" then comp:DoDelta(amount, false) end
        end,
        add_regen = function(inst, comp, amount, src)
            if type(comp.SetRegenMod) == "function" then comp:SetRegenMod(inst, amount, src) end
        end,
        remove_regen = function(inst, comp, src)
            if type(comp.RemoveRegenMod) == "function" then comp:RemoveRegenMod(inst, src) end
        end
    }

    if overrides and type(overrides) == "table" then
        if type(overrides.get_current) == "function" then strategy.get_current = overrides.get_current end
        if type(overrides.do_delta) == "function" then strategy.do_delta = overrides.do_delta end
        if type(overrides.add_regen) == "function" then strategy.add_regen = overrides.add_regen end
        if type(overrides.remove_regen) == "function" then strategy.remove_regen = overrides.remove_regen end
    end

    return strategy
end

-- ========================================================
-- 资源策略映射表 (自带饥荒原生资源的特殊处理)
-- ========================================================
local RESOURCE_STRATEGIES = {
    health = {
        comp_name = "health",
        get_current = function(comp) return comp.currenthealth or 0 end,
        do_delta = function(comp, amount) comp:DoDelta(amount, false, "nikki_skill") end,
        add_regen = function(inst, comp, amount, src)
            if comp.AddRegenSource then comp:AddRegenSource(inst, amount, 1, src) end
        end,
        remove_regen = function(inst, comp, src)
            if comp.RemoveRegenSource then comp:RemoveRegenSource(inst, src) end
        end
    },
    sanity = {
        comp_name = "sanity",
        get_current = function(comp) return comp.current or 0 end,
        do_delta = function(comp, amount) comp:DoDelta(amount, false) end,
        add_regen = function(inst, comp, amount, src)
            if comp.externalmodifiers then comp.externalmodifiers:SetModifier(inst, amount, src) end
        end,
        remove_regen = function(inst, comp, src)
            if comp.externalmodifiers then comp.externalmodifiers:RemoveModifier(inst, src) end
        end
    },
    hunger = {
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
}

setmetatable(RESOURCE_STRATEGIES, {
    __index = function(t, key)
        return CreateStrategy(key)
    end
})

-- ========================================================
-- 公开 API：注册接口
-- ========================================================
function ResourceAdapter.RegisterStrategy(res_id, comp_config)
    if not comp_config or not comp_config.name then
        log.warn("[ResourceAdapter] Cannot register resource '%s': missing 'component.name'", tostring(res_id))
        return
    end
    RESOURCE_STRATEGIES[res_id] = CreateStrategy(comp_config.name, comp_config)
    log.debug("[ResourceAdapter] Registered custom resource logic: %s -> inst.components.%s", res_id, comp_config.name)
end

-- ========================================================
-- 公开 API：路由分发 (统一接收 inst 与 res_name)
-- ========================================================

function ResourceAdapter.GetComponent(inst, res_name)
    local strategy = RESOURCE_STRATEGIES[res_name]
    return strategy and strategy.comp_name and inst.components[strategy.comp_name] or nil
end

function ResourceAdapter.GetCurrent(inst, res_name)
    local comp = ResourceAdapter.GetComponent(inst, res_name)
    if not comp then return 0 end
    return RESOURCE_STRATEGIES[res_name].get_current(comp)
end

function ResourceAdapter.DoDelta(inst, res_name, amount)
    local comp = ResourceAdapter.GetComponent(inst, res_name)
    if comp then
        RESOURCE_STRATEGIES[res_name].do_delta(comp, amount)
    end
end

function ResourceAdapter.AddRegen(inst, res_name, amount, source_id)
    local comp = ResourceAdapter.GetComponent(inst, res_name)
    if comp then
        RESOURCE_STRATEGIES[res_name].add_regen(inst, comp, amount, source_id)
    end
end

function ResourceAdapter.RemoveRegen(inst, res_name, source_id)
    local comp = ResourceAdapter.GetComponent(inst, res_name)
    if comp then
        RESOURCE_STRATEGIES[res_name].remove_regen(inst, comp, source_id)
    end
end

return ResourceAdapter