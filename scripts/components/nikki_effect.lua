-- scripts/components/nikki_effect.lua
local ResolverRegistry = require("nikki_resolver_registry")
local log = require("utils/log")
local TimerScheduler = require("utils/timer_scheduler") -- 新增

-- 私有懒加载：首次调用时向注册表查一次并缓存到 self._resolver，后续直接读缓存
local function GetResolver(self)
    if not self._resolver then
        self._resolver = ResolverRegistry.Get("effect")
    end
    return self._resolver
end

local NikkiEffect = Class(function(self, inst)
    self.inst = inst
    self._active_effects = {}
    self._resolver = nil
    self._scheduler = TimerScheduler(inst) -- 创建调度器

    self.inst:ListenForEvent("death", function()
        log.debug("[NikkiEffect] %s died, clearing all active effects.", tostring(self.inst))
        self:Clear()
    end)

    -- 监听 State 变化事件，精准清理绑定效果
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

function NikkiEffect:HasEffect(id)
    return self._active_effects[id] ~= nil
end

function NikkiEffect:GetLayers(id)
    return self._active_effects[id] and self._active_effects[id].layers or 0
end

-- ============================================
-- 公开 API：施加 Effect
-- ============================================
function NikkiEffect:Apply(id, source)
    local resolver = GetResolver(self)
    if not resolver then return false end

    -- 安全屏障：若实体死亡则禁止挂载新效果
    if self.inst.components.health and self.inst.components.health:IsDead() then
        return false
    end

    local duration, max, mode, bind_to_state = resolver:GetEffectConfig(id)
    local active = self._active_effects[id]
    log.debug("[NikkiEffect] Applying effect '%s' on %s (duration: %s, max: %d, mode: %s)", tostring(id),
        tostring(self.inst), tostring(duration), max, mode)

    -- 情况 A：首次挂载
    if not active then
        if not resolver:PayActivationCost(self.inst, id) then
            return false
        end

        local context = {
            layer = 1,
            start_time = GetTime(),
            end_times = {},
            source = source,
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

        resolver:OnEffectStart(self.inst, id, active.context)
        resolver:UpdateEffectLayers(self.inst, id, 1, active.context)

        -- 使用调度器管理到期
        if duration and duration > 0 then
            table.insert(active.context.end_times, GetTime() + duration)
            self._scheduler:Schedule(id, duration, function()
                self:Remove(id, false) -- 移除一层
            end)
        end
        return true
    end

    -- 情况 B：已存在，处理叠加模式
    if mode == "toggle" then
        self:Remove(id, true)
        return true
    elseif mode == "ignore" then
        log.debug("[NikkiEffect] Effect %s is already active on %s, ignoring new application.", tostring(id),
            tostring(self.inst))
        return false
    elseif mode == "refresh" then
        -- 刷新：重置所有层的时间
        -- 清空所有待处理的定时器，然后重新添加所有层的时间
        self._scheduler:Cancel(id)
        active.context.end_times = {}
        -- 为每一层重新设定到期时间（假设所有层都刷新到新的 duration）
        for i = 1, active.layers do
            table.insert(active.context.end_times, GetTime() + duration)
        end
        -- 调度新的定时器（使用最后一个到期时间，因为所有层同时刷新，所以所有层同时到期）
        if duration and duration > 0 then
            self._scheduler:Schedule(id, duration, function()
                self:Remove(id, false)
            end)
        end
        return true
    elseif mode == "add" then
        -- 叠加：增加一层
        if active.layers < max then
            active.layers = active.layers + 1
            active.context.layer = active.layers
            resolver:UpdateEffectLayers(self.inst, id, active.layers, active.context)
            if duration and duration > 0 then
                table.insert(active.context.end_times, GetTime() + duration)
                -- 重新调度，因为新层可能比现有层更早到期
                -- 取消旧定时器，重新计算最近到期时间
                self._scheduler:Cancel(id)
                self:_ScheduleEffect(id)
            end
        else
            -- 达到上限：替换最老的一层（FIFO）
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

-- 内部辅助：为某个 effect 调度定时器（基于其最近的到期时间）
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

-- ============================================
-- 公开 API：移除 Effect
-- force_all: true 直接清空所有层数，false 按层递减
-- ============================================
function NikkiEffect:Remove(id, force_all)
    local resolver = GetResolver(self)
    if not resolver or not self._active_effects[id] then return end

    local active = self._active_effects[id]

    if not force_all then
        -- 移除最老的一层 (FIFO)
        if #active.context.end_times > 0 then
            table.remove(active.context.end_times, 1)
        end
        active.layers = active.layers - 1
    else
        -- 清空所有层
        active.context.end_times = {}
        active.layers = 0
    end

    if active.layers <= 0 then
        -- 完全移除
        self._scheduler:Cancel(id)
        resolver:OnEffectEnd(self.inst, id, active.context)
        self._active_effects[id] = nil
        log.debug("[NikkiEffect] Effect '%s' on %s fully removed.", tostring(id), tostring(self.inst))
    else
        -- 剩余层，更新层数并重新调度定时器
        active.context.layer = active.layers
        resolver:UpdateEffectLayers(self.inst, id, active.layers, active.context)
        self._scheduler:Cancel(id)
        self:_ScheduleEffect(id)
        log.debug("[NikkiEffect] Effect '%s' on %s reduced to %d layers.", tostring(id), tostring(self.inst),
            active.layers)
    end
end

-- ============================================
-- 公开 API：查询 Effect 是否为永久效果
-- ============================================
function NikkiEffect:IsPermanent(id)
    local resolver = GetResolver(self)
    if not resolver then return false end
    local duration, _, _ = resolver:GetEffectConfig(id)
    return duration == nil
end

function NikkiEffect:Toggle(id)
    if self:HasEffect(id) then
        self:Remove(id, true)
    else
        self:Apply(id)
    end
end

-- ============================================
-- 清空所有激活的 Effect
-- ============================================
function NikkiEffect:Clear()
    self._scheduler:Clear()
    for id, active in pairs(self._active_effects) do
        local resolver = GetResolver(self)
        if resolver then
            resolver:OnEffectEnd(self.inst, id, active.context)
        end
    end
    self._active_effects = {}
end

-- ============================================
-- 帧更新：处理业务 Tick 与持续扣费
-- ============================================
function NikkiEffect:OnUpdate(dt)
    local resolver = GetResolver(self)
    if not resolver then return end

    if self.inst.components.health and self.inst.components.health:IsDead() then
        return
    end

    for id, active in pairs(self._active_effects) do
        local should_keep = resolver:OnUpdateEffect(self.inst, id, dt, active.context, active.layers)
        if not should_keep then
            self:Remove(id, true)
        end
    end
end

return NikkiEffect
