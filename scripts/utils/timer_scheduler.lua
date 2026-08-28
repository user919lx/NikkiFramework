-- scripts/utils/timer_scheduler.lua
local log = require("utils/log")

local TimerScheduler = Class(function(self, inst)
    self.inst = inst
    self._events = {} -- key -> { end_time, callback }
    self._timer_task = nil
end)

-- 添加/刷新定时事件
function TimerScheduler:Schedule(key, duration, callback)
    if duration <= 0 then
        if callback then callback() end
        return
    end
    local end_time = GetTime() + duration
    self._events[key] = {
        end_time = end_time,
        callback = callback,
    }
    self:_Refresh()
end

-- 取消定时事件
function TimerScheduler:Cancel(key)
    if self._events[key] then
        self._events[key] = nil
        self:_Refresh()
    end
end

-- 清除所有事件
function TimerScheduler:Clear()
    self._events = {}
    if self._timer_task then
        self._timer_task:Cancel()
        self._timer_task = nil
    end
end

-- 内部：刷新定时器
function TimerScheduler:_Refresh()
    if self._timer_task then
        self._timer_task:Cancel()
        self._timer_task = nil
    end

    local now = GetTime()
    local next_end = math.huge
    for key, ev in pairs(self._events) do
        if ev.end_time < next_end then
            next_end = ev.end_time
        end
    end

    if next_end == math.huge then
        return
    end

    local duration = math.max(0, next_end - now)
    if duration > 0 then
        self._timer_task = self.inst:DoTaskInTime(duration, function()
            self:_OnTick()
        end)
    else
        self:_OnTick()
    end
end

-- 内部：定时器触发，处理所有到期事件
function TimerScheduler:_OnTick()
    local now = GetTime()
    local expired_keys = {}

    -- 收集所有到期的事件key
    for key, ev in pairs(self._events) do
        if ev.end_time <= now then
            table.insert(expired_keys, key)
        end
    end

    -- 处理到期事件（先移除再回调，避免回调中再次修改导致混乱）
    for _, key in ipairs(expired_keys) do
        local ev = self._events[key]
        if ev then
            self._events[key] = nil
            if ev.callback then
                ev.callback()
            end
        end
    end

    -- 如果还有事件，继续调度
    if next(self._events) ~= nil then
        self:_Refresh()
    end
end

return TimerScheduler
