-- scripts/components/nikki_effect.lua
local ResolverRegistry = require("nikki_resolver_registry")
local log = require("utils/log")

-- 私有懒加载：首次调用时向注册表查一次并缓存到 self._resolver，后续直接读缓存
local function GetResolver(self)
    if not self._resolver then
        self._resolver = ResolverRegistry.Get("effect")
    end
    return self._resolver
end

local NikkiEffect = Class(function(self, inst)
    self.inst = inst

    -- 结构: [effect_id] = { layers = 1, context = {}, timers = { task1, task2... } }
    self._active_effects = {}
    self._resolver = nil -- 私有缓存

    self.inst:ListenForEvent("death", function()
        log.debug("[NikkiEffect] %s died, clearing all active effects.", tostring(self.inst))
        self:Clear()
    end)

    self.inst:StartUpdatingComponent(self)
end)

-- 内部方法：添加定时器与时间队列
function NikkiEffect:_AddTimer(id, duration, active_ref)
    if not duration or duration <= 0 then return end

    local end_time = GetTime() + duration
    local task = self.inst:DoTaskInTime(duration, function()
        self:Remove(id, false)
    end)

    -- 严格同步：定时器与时间戳队列同时入栈
    table.insert(active_ref.timers, task)
    table.insert(active_ref.context.end_times, end_time)
end

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

    local duration, max, mode = resolver:GetEffectConfig(id)
    local active = self._active_effects[id]

    -- 情况 A：首次挂载 (从 0 到 1，需要支付启动成本)
    if not active then
        -- 【激活验资】：检查并扣除单次启动费用 (cost)
        if not resolver:PayActivationCost(self.inst, id) then
            return false
        end

        self._active_effects[id] = {
            layers = 1,
            timers = {},
            context = {
                layer = 1,
                start_time = GetTime(),
                end_times = {},  -- 时间队列 (先进先出)
                source = source, -- 记录施法者，解决伤害归属
                data = {},       -- 留给开发者的状态机黑盒
                max = max,       -- 顺手把上限传进去
                -- 供开发者在 fn 中直接获取剩余时间
                GetTotalRemain = function(ctx)
                    if #ctx.end_times == 0 then return 0 end
                    return math.max(0, ctx.end_times[#ctx.end_times] - GetTime())
                end,
                GetNextRemain = function(ctx)
                    if #ctx.end_times == 0 then return 0 end
                    return math.max(0, ctx.end_times[1] - GetTime())
                end
            }
        }
        active = self._active_effects[id]

        resolver:OnEffectStart(self.inst, id, active.context)
        resolver:UpdateEffectLayers(self.inst, id, 1, active.context)
        self:_AddTimer(id, duration, active) -- 传入 active 本身
        return true
    end

    -- 情况 B：已经存在，处理叠加与开关规则 (从 1 往后走，跳过启动成本)
    if mode == "toggle" then
        -- 【开关模式】：二次 Apply 触发直接关闭 (免单卸载)
        self:Remove(id, true)
        return true
    elseif mode == "ignore" then
        log.debug("[NikkiEffect] Effect %s is already active on %s, ignoring new application.", tostring(id),
            tostring(self.inst))
        return false
    elseif mode == "refresh" then
        -- 刷新：清除所有旧定时器与旧时间戳
        for _, t in ipairs(active.timers) do t:Cancel() end
        active.timers = {}
        active.context.end_times = {} -- 必须同步清空
        self:_AddTimer(id, duration, active)
        return true
    elseif mode == "add" then
        -- 叠加：独立计算当前这层的时间
        if active.layers < max then
            active.layers = active.layers + 1
            active.context.layer = active.layers
            resolver:UpdateEffectLayers(self.inst, id, active.layers, active.context)
            self:_AddTimer(id, duration, active)
        else
            -- 达到上限时：剔除最老的一层 (严格同步剔除 Task 和 end_times)
            if #active.timers > 0 then
                local oldest_timer = table.remove(active.timers, 1)
                table.remove(active.context.end_times, 1) -- 严格同步出栈
                if oldest_timer then oldest_timer:Cancel() end
            end
            self:_AddTimer(id, duration, active)
        end
        return true
    end
end

-- ============================================
-- 公开 API：移除 Effect
-- force_all: true 则直接清空所有层数，false 则按层递减
-- ============================================
function NikkiEffect:Remove(id, force_all)
    local resolver = GetResolver(self)
    if not resolver or not self._active_effects[id] then return end

    local active = self._active_effects[id]

    -- 取消最早的一个定时器
    if not force_all and #active.timers > 0 then
        local timer = table.remove(active.timers, 1)
        table.remove(active.context.end_times, 1) -- 严格同步出栈
        if timer then timer:Cancel() end
    end

    local target_layer = force_all and 0 or (active.layers - 1)

    if target_layer > 0 then
        -- 还有剩余层数，仅降级
        active.layers = target_layer
        active.context.layer = target_layer
        resolver:UpdateEffectLayers(self.inst, id, target_layer, active.context)
    else
        -- 层数归零，彻底注销
        for _, t in ipairs(active.timers) do t:Cancel() end
        resolver:OnEffectEnd(self.inst, id, active.context)
        self._active_effects[id] = nil
    end
end

-- ============================================
-- 公开 API：查询 Effect 是否为永久效果（无 duration）
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
    local active_ids = {}
    for id, _ in pairs(self._active_effects) do
        table.insert(active_ids, id)
    end

    for _, id in ipairs(active_ids) do
        self:Remove(id, true)
    end

    self._active_effects = {}
end

-- ============================================
-- 帧更新：处理业务 Tick 与持续扣费卸载
-- ============================================
function NikkiEffect:OnUpdate(dt)
    local resolver = GetResolver(self)
    if not resolver then return end

    -- 安全屏障：实体死亡后停止挂载的 fn 轮询
    if self.inst.components.health and self.inst.components.health:IsDead() then
        return
    end

    for id, active in pairs(self._active_effects) do
        -- 交由 Resolver 处理周期性消耗/回复 (drain) 与 fn，返回 false 时触发自我卸载
        local should_keep = resolver:OnUpdateEffect(self.inst, id, dt, active.context, active.layers)
        if not should_keep then
            self:Remove(id)
        end
    end
end

return NikkiEffect
