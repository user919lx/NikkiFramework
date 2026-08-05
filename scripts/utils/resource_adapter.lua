-- scripts/utils/resource_adapter.lua
local ResourceAdapter = {}

-- 提取：自定义/通用资源的默认操作策略生成器
local function CreateCustomStrategy(comp_name)
    return {
        get_comp = function(inst) return inst.components[comp_name] end,
        get_current = function(comp)
            if type(comp.GetCurrent) == "function" then return comp:GetCurrent() end
            return comp.current or 0
        end,
        add_regen = function(inst, comp, amount, src)
            if type(comp.SetRegenMod) == "function" then comp:SetRegenMod(inst, amount, src) end
        end,
        remove_regen = function(inst, comp, src)
            if type(comp.RemoveRegenMod) == "function" then comp:RemoveRegenMod(inst, src) end
        end
    }
end

-- 【新增】：资源操作策略映射表。彻底解耦 if/elseif 分支！
local RESOURCE_STRATEGIES = {
    health = {
        get_comp = function(inst) return inst.components.health end,
        get_current = function(comp) return comp.currenthealth or 0 end,
        add_regen = function(inst, comp, amount, src)
            if comp.AddRegenSource then comp:AddRegenSource(inst, amount, 1, src) end
        end,
        remove_regen = function(inst, comp, src)
            if comp.RemoveRegenSource then comp:RemoveRegenSource(inst, src) end
        end
    },
    sanity = {
        get_comp = function(inst) return inst.components.sanity end,
        get_current = function(comp) return comp.current or 0 end,
        add_regen = function(inst, comp, amount, src)
            if comp.externalmodifiers then comp.externalmodifiers:SetModifier(inst, amount, src) end
        end,
        remove_regen = function(inst, comp, src)
            if comp.externalmodifiers then comp.externalmodifiers:RemoveModifier(inst, src) end
        end
    },
    hunger = {
        get_comp = function(inst) return inst.components.hunger end,
        get_current = function(comp) return comp.current or 0 end,
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

-- 【黑魔法】：利用元表进行智能兜底 (Fallback)
-- 如果外部请求了一个策略表中未显式定义的资源名 (例如 "stamina")
-- 它会自动回退到通用逻辑去寻找 inst.components.stamina
setmetatable(RESOURCE_STRATEGIES, {
    __index = function(t, key)
        return CreateCustomStrategy(key)
    end
})

-- ============================================
-- 公开 API：大幅瘦身，直接路由给策略表
-- ============================================

function ResourceAdapter.GetComponent(inst, res_name)
    return RESOURCE_STRATEGIES[res_name].get_comp(inst)
end

function ResourceAdapter.GetCurrent(comp, res_name)
    if not comp then return 0 end
    return RESOURCE_STRATEGIES[res_name].get_current(comp)
end

-- 注：DoDelta 不需要策略分发，因为无论什么资源，瞬时扣除的方法名在饥荒中高度统一
function ResourceAdapter.DoDelta(comp, amount)
    if comp and type(comp.DoDelta) == "function" then
        comp:DoDelta(amount)
    end
end

function ResourceAdapter.AddRegen(inst, comp, res_name, amount, source_id)
    if comp then
        RESOURCE_STRATEGIES[res_name].add_regen(inst, comp, amount, source_id)
    end
end

function ResourceAdapter.RemoveRegen(inst, comp, res_name, source_id)
    if comp then
        RESOURCE_STRATEGIES[res_name].remove_regen(inst, comp, source_id)
    end
end

return ResourceAdapter
