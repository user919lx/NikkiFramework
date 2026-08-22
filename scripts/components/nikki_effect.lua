-- scripts/components/nikki_effect.lua
local log = require("utils/log")
local TimerScheduler = require("utils/timer_scheduler")
local ResourceAdapter = require("adapters/resource_adapter")
local ModifierAdapter = require("adapters/modifier_adapter")

-- ============================================================
-- 内部辅助：资源速率处理
-- ============================================================
local function GetResourceRate(inst, id, def, context, layers, kind)
    local source = def[kind]
    local rate = source and source.rate or 0
    if type(rate) == "function" then
        local ok, result = pcall(rate, inst, context)
        if not ok then
            log.error("[NikkiEffect] Error in %s rate func for '%s': %s", kind, id, tostring(result))
            return 0
        end
        return result or 0
    end
    return rate * layers
end

local function ApplyResourceRate(inst, id, def, context, layers, kind)
    local source = def[kind]
    if not source then return end

    local rate = GetResourceRate(inst, id, def, context, layers, kind)
    if context then
        context[kind .. "_rate"] = rate
    end

    if kind == "regen" then
        ResourceAdapter.SetRegen(inst, source.res, rate, id)
    else
        ResourceAdapter.SetDrain(inst, source.res, rate, id)
    end
end

local function RemoveResourceRate(inst, id, def, context, kind)
    local source = def[kind]
    if not source then return end

    local rate = context and context[kind .. "_rate"] or 0
    if kind == "regen" then
        ResourceAdapter.RemoveRegen(inst, source.res, rate, id)
    else
        ResourceAdapter.RemoveDrain(inst, source.res, rate, id)
    end
end

-- ============================================================
-- 组件主体
-- ============================================================
local NikkiEffect = Class(function(self, inst)
    self.inst = inst
    self._active_effects = {}
    self._sources = {} -- table<effect_id, table<source, true>>
    self._resolver = nil
    self._scheduler = TimerScheduler(inst)

    self.inst:ListenForEvent("death", function()
        log.debug("[NikkiEffect] %s died, clearing all active effects.", tostring(self.inst))
        self:Clear()
    end)

    self.inst:ListenForEvent("nikki_state_dirty", function(owner, data)
        local new_state = data and data.state
        local to_remove = {}
        for id, active in pairs(self._active_effects) do
            if active.context.bound_state and active.context.bound_state ~= new_state then
                table.insert(to_remove, id)
            end
        end
        for _, id in ipairs(to_remove) do
            log.debug("[NikkiEffect] State changed to '%s', auto-removing bound effect '%s'.", tostring(new_state), id)
            self:Remove(id, true)
        end
    end)

    self.inst:StartUpdatingComponent(self)
end)

-- ============================================================
-- 内部私有方法
-- ============================================================

function NikkiEffect:_GetDef(id)
    if not self._resolver then return nil end
    return self._resolver:GetDef(id)
end

function NikkiEffect:_GetOrCreateSources(id)
    if not self._sources[id] then
        self._sources[id] = {}
    end
    return self._sources[id]
end

function NikkiEffect:_AddSource(id, source)
    if source == nil then return end
    local sources = self:_GetOrCreateSources(id)
    sources[source] = true
end

function NikkiEffect:_RemoveSource(id, source)
    if source == nil or not self._sources[id] then return end
    self._sources[id][source] = nil
end

function NikkiEffect:_ClearSources(id)
    self._sources[id] = nil
end

function NikkiEffect:_PayActivationCost(id)
    local def = self:_GetDef(id)
    if not def or not def.cost or not def.cost.res or not def.cost.amount or def.cost.amount <= 0 then
        return true
    end

    local current = ResourceAdapter.GetCurrent(self.inst, def.cost.res)
    if current < def.cost.amount then
        log.debug("[NikkiEffect] Activation failed: %s lacks %s for effect '%s'", tostring(self.inst), def.cost.res, id)
        return false
    end

    ResourceAdapter.DoDelta(self.inst, def.cost.res, -def.cost.amount)
    return true
end

function NikkiEffect:_OnEffectStart(id, context)
    local def = self:_GetDef(id)
    if not def then return end

    if def.tags then
        for _, tag in ipairs(def.tags) do
            self.inst:AddTag(tag)
        end
    end
    if def.on_apply then
        pcall(def.on_apply, self.inst, context)
    end
end

function NikkiEffect:_OnEffectEnd(id, context)
    local def = self:_GetDef(id)
    if not def then return end

    if def.tags then
        for _, tag in ipairs(def.tags) do
            self.inst:RemoveTag(tag)
        end
    end
    if def.mods then
        for mod_type, _ in pairs(def.mods) do
            ModifierAdapter.Remove(self.inst, mod_type, id)
        end
    end
    RemoveResourceRate(self.inst, id, def, context, "regen")
    RemoveResourceRate(self.inst, id, def, context, "drain")
    if def.on_remove then
        pcall(def.on_remove, self.inst, context)
    end
end

function NikkiEffect:_UpdateEffectLayers(id, layers, context)
    local def = self:_GetDef(id)
    if not def then return end

    if def.mods then
        for mod_type, value in pairs(def.mods) do
            ModifierAdapter.Apply(self.inst, mod_type, value, id)
        end
    end
    ApplyResourceRate(self.inst, id, def, context, layers, "regen")
    ApplyResourceRate(self.inst, id, def, context, layers, "drain")

    if type(def.on_layer_update) == "function" then
        pcall(def.on_layer_update, self.inst, layers, context)
    end
end

function NikkiEffect:_OnUpdateEffect(id, dt, context, layers)
    local def = self:_GetDef(id)
    if not def then return false end

    if def.drain and def.drain.res and context and context.drain_rate and context.drain_rate > 0 then
        local current = ResourceAdapter.GetCurrent(self.inst, def.drain.res)
        if current <= 0.01 then
            local on_deplete = def.drain.on_deplete or "remove"
            if on_deplete == "remove" then
                log.debug("[NikkiEffect] Effect '%s' on %s auto-removed due to insufficient %s (current: %.2f)", id,
                    tostring(self.inst), def.drain.res, current)
                return false
            end
            context.is_depleted = true
        else
            context.is_depleted = false
        end
    end

    if def.fn then
        local ok, result = pcall(def.fn, self.inst, dt, context)
        if not ok then
            log.error("[NikkiEffect] Error in effect function for '%s': %s", id, tostring(result))
        elseif result == false then
            log.debug("[NikkiEffect] Effect function for '%s' returned false, auto-removing effect", id)
            return false
        end
    end

    return true
end

function NikkiEffect:_ScheduleEffect(id)
    local active = self._active_effects[id]
    if not active or #active.context.end_times == 0 then return end
    local nearest = math.min(unpack(active.context.end_times))
    local duration = math.max(0, nearest - GetTime())
    if duration > 0 then
        self._scheduler:Schedule(id, duration, function()
            self:Remove(id, false)
        end)
    else
        self:Remove(id, false)
    end
end

-- ============================================================
-- 公开查询 API
-- ============================================================

function NikkiEffect:HasEffect(id)
    return self._active_effects[id] ~= nil
end

function NikkiEffect:GetLayers(id)
    return self._active_effects[id] and self._active_effects[id].layers or 0
end

function NikkiEffect:GetSources(id)
    return self._sources[id] or {}
end

function NikkiEffect:IsPermanent(id)
    local resolver = self._resolver
    if not resolver then return false end
    local duration, _, _ = resolver:GetEffectConfig(id)
    return duration == nil
end

-- ============================================================
-- 公开操作 API
-- ============================================================

function NikkiEffect:Apply(id, source)
    local resolver = self._resolver
    if not resolver then return false end

    if self.inst.components.health and self.inst.components.health:IsDead() then
        return false
    end

    local duration, max, mode, bind_to_state = resolver:GetEffectConfig(id)
    local active = self._active_effects[id]

    -- 记录 source 到映射表 (key = source, value = true)
    self:_AddSource(id, source)

    if not active then
        if not self:_PayActivationCost(id) then
            self:_ClearSources(id)
            return false
        end

        local def = resolver:GetDef(id)
        local context = {
            def = def,
            layer = 1,
            start_time = GetTime(),
            end_times = {},
            sources = self:_GetOrCreateSources(id),
            data = {},
            max = max,
            bound_state = (bind_to_state and self.inst.components.nikki_state) and
                self.inst.components.nikki_state:GetState() or nil,
            GetTotalRemain = function(ctx)
                if #ctx.end_times == 0 then return 0 end
                return math.max(0, ctx.end_times[#ctx.end_times] - GetTime())
            end,
            GetNextRemain = function(ctx)
                if #ctx.end_times == 0 then return 0 end
                return math.max(0, ctx.end_times[1] - GetTime())
            end
        }

        self._active_effects[id] = {
            layers = 1,
            context = context,
        }
        active = self._active_effects[id]

        self:_OnEffectStart(id, active.context)
        self:_UpdateEffectLayers(id, 1, active.context)

        if duration and duration > 0 then
            table.insert(active.context.end_times, GetTime() + duration)
            self._scheduler:Schedule(id, duration, function()
                self:Remove(id, false)
            end)
        end
        return true
    end

    if mode == "toggle" then
        self:Remove(id, true, source)
        return true
    elseif mode == "ignore" then
        log.debug("[NikkiEffect] Effect %s is already active on %s, ignoring new application.", tostring(id),
            tostring(self.inst))
        return false
    elseif mode == "refresh" then
        self._scheduler:Cancel(id)
        active.context.end_times = {}
        for i = 1, active.layers do
            table.insert(active.context.end_times, GetTime() + duration)
        end
        if duration and duration > 0 then
            self._scheduler:Schedule(id, duration, function()
                self:Remove(id, false)
            end)
        end
        return true
    elseif mode == "add" then
        if active.layers < max then
            active.layers = active.layers + 1
            active.context.layer = active.layers
            self:_UpdateEffectLayers(id, active.layers, active.context)
            if duration and duration > 0 then
                table.insert(active.context.end_times, GetTime() + duration)
                self._scheduler:Cancel(id)
                self:_ScheduleEffect(id)
            end
        else
            if #active.context.end_times > 0 then
                table.remove(active.context.end_times, 1)
            end
            if duration and duration > 0 then
                table.insert(active.context.end_times, GetTime() + duration)
                self._scheduler:Cancel(id)
                self:_ScheduleEffect(id)
            end
        end
        return true
    end
end

function NikkiEffect:Remove(id, force_all, source)
    local active = self._active_effects[id]
    if not active then return end

    -- 单项移除 source (value = nil)
    if source ~= nil then
        self:_RemoveSource(id, source)
    end

    if not force_all then
        if #active.context.end_times > 0 then
            table.remove(active.context.end_times, 1)
        end
        active.layers = active.layers - 1
    else
        active.context.end_times = {}
        active.layers = 0
    end

    if active.layers <= 0 then
        self._scheduler:Cancel(id)
        self:_OnEffectEnd(id, active.context)
        self._active_effects[id] = nil
        self:_ClearSources(id) -- 彻底结束时清理来源表
        log.debug("[NikkiEffect] Effect '%s' on %s fully removed.", tostring(id), tostring(self.inst))
    else
        active.context.layer = active.layers
        self:_UpdateEffectLayers(id, active.layers, active.context)
        self._scheduler:Cancel(id)
        self:_ScheduleEffect(id)
        log.debug("[NikkiEffect] Effect '%s' on %s reduced to %d layers.", tostring(id), tostring(self.inst),
            active.layers)
    end
end

function NikkiEffect:Toggle(id, source)
    if self:HasEffect(id) then
        self:Remove(id, true, source)
    else
        self:Apply(id, source)
    end
end

function NikkiEffect:Clear()
    self._scheduler:Clear()
    for id, active in pairs(self._active_effects) do
        self:_OnEffectEnd(id, active.context)
    end
    self._active_effects = {}
    self._sources = {}
end

function NikkiEffect:OnUpdate(dt)
    if self.inst.components.health and self.inst.components.health:IsDead() then
        return
    end

    for id, active in pairs(self._active_effects) do
        local should_keep = self:_OnUpdateEffect(id, dt, active.context, active.layers)
        if not should_keep then
            self:Remove(id, true)
        end
    end
end

return NikkiEffect
