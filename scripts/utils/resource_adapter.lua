-- scripts/utils/resource_adapter.lua
local log = require("utils/log")
local SourceModifierList = require("util/sourcemodifierlist")
local ResourceAdapter = {}

-- ========================================================
-- 内部工厂：严格划分 Server 与 Client (基于字符串寻址)
-- ========================================================
local function CreateStrategy(config_data)
    local comp_cfg = config_data.component or {}
    local rep_cfg = config_data.replica or {}

    local c_name = comp_cfg.name

    local fn_get_current = comp_cfg.get_current or "GetCurrent"
    local fn_do_delta = comp_cfg.do_delta or "DoDelta"
    local fn_set_regen = comp_cfg.set_regen or "SetRegenMod"
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
            set_regen = function(inst, comp, rate, key)
                if type(comp[fn_set_regen]) == "function" then comp[fn_set_regen](comp, inst, rate, key) end
            end,
            remove_regen = function(inst, comp, rate, key)
                if type(comp[fn_remove_regen]) == "function" then comp[fn_remove_regen](comp, inst, key, rate) end
            end
        },
        client = {
            get_percent = function(inst)
                local rep = inst.replica and inst.replica[c_name]
                if rep and type(rep[fn_get_percent]) == "function" then return rep[fn_get_percent](rep) end
                return 0
            end,
            get_max = function(inst)
                local rep = inst.replica and inst.replica[c_name]
                if not rep then return 100 end
                if type(rep[fn_get_max]) == "function" then return rep[fn_get_max](rep) end
                if type(rep.Max) == "function" then return rep:Max() end
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
-- 资源策略映射表
-- ========================================================
local RESOURCE_STRATEGIES = {
    health = {
        server = {
            comp_name = "health",
            get_current = function(comp) return comp.currenthealth or 0 end,
            do_delta = function(comp, amount) comp:DoDelta(amount, false, "nikki_skill") end,
            set_regen = function(inst, comp, rate, key)
                if comp.AddRegenSource then
                    comp:AddRegenSource(inst, rate * FRAMES, FRAMES, key)
                end
            end,
            remove_regen = function(inst, comp, rate, key)
                if comp.RemoveRegenSource then
                    comp:RemoveRegenSource(inst, key)
                end
            end
        },
    },
    sanity = {
        server = {
            comp_name = "sanity",
            get_current = function(comp) return comp.current or 0 end,
            do_delta = function(comp, amount) comp:DoDelta(amount, false) end,
            set_regen = function(inst, comp, rate, key)
                -- Sanity: externalmodifiers 接受绝对值（正=回复，负=消耗）
                if comp.externalmodifiers then
                    comp.externalmodifiers:SetModifier(inst, rate, key)
                end
            end,
            remove_regen = function(inst, comp, rate, key)
                if comp.externalmodifiers then
                    comp.externalmodifiers:RemoveModifier(inst, key)
                end
            end
        },
    },
    hunger = {
        server = {
            comp_name = "hunger",
            get_current = function(comp) return comp.current or 0 end,
            do_delta = function(comp, amount) comp:DoDelta(amount, false) end,
            set_regen = function(inst, comp, rate, key)
                -- 1. 懒加载：注入加法计算的 SourceModifierList
                if not comp.nikki_regen_modifiers then
                    -- 基础值为 0，合并方式为 additive (累加)
                    comp.nikki_regen_modifiers = SourceModifierList(inst, 0, SourceModifierList.additive)
                    -- 2. 挂钩原生的 DoDec，进行安全的“状态伪装”
                    local _OldDoDec = comp.DoDec
                    comp.DoDec = function(self, dt, ignore_damage)
                        local extra_rate = self.nikki_regen_modifiers:Get()
                        if extra_rate ~= 0 then
                            -- 饥荒中 hungerrate 是正数代表掉落。我们传进来的 rate 是负数（drain）。
                            -- 所以：伪装速率 = 原速率 - 我们的rate（例如 1 - (-10) = 11，意味着以11倍速掉落）
                            local original_rate = self.hungerrate
                            self.hungerrate = original_rate - extra_rate
                            -- 放行原生逻辑，此时原生代码会用伪装后的 hungerrate 去乘以装备乘区！
                            _OldDoDec(self, dt, ignore_damage)
                            -- 【极其重要】：结算完毕后，完璧归赵，把原本的 hungerrate 还回去
                            self.hungerrate = original_rate
                        else
                            _OldDoDec(self, dt, ignore_damage)
                        end
                    end
                end
                -- 3. 将单次速率记录进 ModifierList（自动处理同源覆盖）
                comp.nikki_regen_modifiers:SetModifier(inst, rate, key)
            end,
            remove_regen = function(inst, comp, rate, key)
                if comp.nikki_regen_modifiers then
                    comp.nikki_regen_modifiers:RemoveModifier(inst, key)
                end
            end
        },
    },
}

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
-- 公开 API：UI 专用取值接口
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

-- ========================================================
-- 公开 API：资源操作 (服务端)
-- ========================================================
function ResourceAdapter.GetCurrent(inst, res_id)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if not comp or not strategy then return 0 end
    return strategy.server.get_current(comp)
end

function ResourceAdapter.DoDelta(inst, res_id, amount)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if comp and strategy then strategy.server.do_delta(comp, amount) end
end

-- ========================================================
--                  Regen / Drain
-- ========================================================
function ResourceAdapter.SetRegen(inst, res_id, rate, key)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if not comp or not strategy then return end
    rate = ValidateRate(rate, "SetRegen")
    if rate == 0 then
        ResourceAdapter.RemoveRegen(inst, res_id, 0, key)
        return
    end
    log.debug("[ResourceAdapter] Setting regen for resource '%s' on %s (rate: %.2f, key: %s)", res_id,
        tostring(inst),
        rate, tostring(key))
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
    log.debug("[ResourceAdapter] Setting drain for resource '%s' on %s (rate: %.2f, key: %s)", res_id,
        tostring(inst),
        rate, tostring(key))
    strategy.server.set_regen(inst, comp, -rate, key)
end

function ResourceAdapter.RemoveRegen(inst, res_id, rate, key)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if not comp or not strategy then return end
    log.debug("[ResourceAdapter] Removing regen for resource '%s' on %s (rate: %.2f, key: %s)", res_id,
        tostring(inst),
        rate, tostring(key))
    strategy.server.remove_regen(inst, comp, rate, key)
end

function ResourceAdapter.RemoveDrain(inst, res_id, rate, key)
    local comp, strategy = GetComponentAndStrategy(inst, res_id)
    if not comp or not strategy then return end
    log.debug("[ResourceAdapter] Removing drain for resource '%s' on %s (rate: %.2f, key: %s)", res_id,
        tostring(inst),
        rate, tostring(key))
    strategy.server.remove_regen(inst, comp, rate, key)
end

return ResourceAdapter
