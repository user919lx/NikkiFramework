local log = require("utils/log")
-- ============================================================
-- 内部辅助：统一回调派发
-- ============================================================
local function DispatchCallback(fn, owner, targets, aura_inst, custom_params)
    if not fn or #targets == 0 then return end
    local params = {}
    if custom_params then
        for k, v in pairs(custom_params) do
            params[k] = v
        end
    end
    params.targets = targets
    params.aura = aura_inst
    local ok, err = pcall(fn, owner, params)
    if not ok then
        log.error("[NikkiAura] Error in callback function. %s", tostring(err))
    end
end

local NikkiAura = Class(function(self, inst)
    self.inst = inst

    self.owner = nil
    self.radius = 1
    self.pulse_interval = 1.0
    self.exclude_owner = false
    self.selector = nil
    self.effect_id = nil
    self.params = nil

    -- 生命周期钩子: fn(inst, params)
    -- params 结构: { targets = table, aura = EntityScript, ... }
    self.on_enter = nil
    self.on_pulse = nil
    self.on_exit = nil

    self._task = nil
    self._current_targets = {} -- table<EntityScript, boolean>

    self.inst:ListenForEvent("onremove", function()
        self:ClearAllTargets()
        if self._task then
            self._task:Cancel()
            self._task = nil
        end
        log.debug("[NikkiAura] Aura component removed, cleared all targets and canceled pulse task.")
    end)
end)

-- ============================================================
-- 内部辅助：效果施加与移除 (带重叠计数保护)
-- ============================================================
function NikkiAura:_ApplyEffect(target)
    if not self.effect_id or not target or not target:IsValid() then return end
    target._nikki_aura_counts = target._nikki_aura_counts or {}
    local count = target._nikki_aura_counts[self.effect_id] or 0
    if count == 0 then
        NikkiManager:ApplyEffect(target, self.effect_id, self.owner or self.inst)
    end
    target._nikki_aura_counts[self.effect_id] = count + 1
end

function NikkiAura:_RemoveEffect(target)
    if not self.effect_id or not target or not target:IsValid() then return end
    if not target._nikki_aura_counts or not target._nikki_aura_counts[self.effect_id] then
        return
    end
    local count = target._nikki_aura_counts[self.effect_id] - 1
    if count <= 0 then
        target._nikki_aura_counts[self.effect_id] = nil
        NikkiManager:RemoveEffect(target, self.effect_id)
    else
        target._nikki_aura_counts[self.effect_id] = count
    end
end

-- ============================================================
-- 空间检测与周期处理
-- ============================================================
function NikkiAura:_FindTargets()
    local x, y, z = self.inst.Transform:GetWorldPosition()

    local must_have = self.selector and self.selector.must_have or nil
    local must_have_one_of = self.selector and self.selector.must_have_one_of or nil
    local cant_have = self.selector and self.selector.cant_have or nil

    local entities = TheSim:FindEntities(x, y, z, self.radius, must_have, cant_have, must_have_one_of)
    local targets_map = {}

    for _, target in ipairs(entities) do
        if target and target:IsValid() then
            if not (self.exclude_owner and target == self.owner) then
                targets_map[target] = true
            end
        end
    end
    return targets_map
end

-- ============================================================
-- 生命周期统一管线 (Effect 挂卸载 + 用户自定义回调)
-- ============================================================
function NikkiAura:_OnEnter(targets)
    if not targets or #targets == 0 then return end
    for _, target in ipairs(targets) do
        self:_ApplyEffect(target)
    end
    local owner = (self.owner and self.owner:IsValid()) and self.owner or self.inst
    DispatchCallback(self.on_enter, owner, targets, self.inst, self.params)
end

function NikkiAura:_OnExit(targets)
    if not targets or #targets == 0 then return end
    for _, target in ipairs(targets) do
        self:_RemoveEffect(target)
    end
    local owner = (self.owner and self.owner:IsValid()) and self.owner or self.inst
    DispatchCallback(self.on_exit, owner, targets, self.inst, self.params)
end

-- ============================================================
-- 空间检测与周期驱动
-- ============================================================
function NikkiAura:OnPulse()
    if self.owner and not self.owner:IsValid() then
        self.inst:Remove()
        log.error("[NikkiAura] Owner is invalid, removing aura entity.", self.inst)
        return
    end

    local new_targets = self:_FindTargets() or {}
    local entered_targets = {}
    local exited_targets = {}
    local current_active_targets = {}

    -- 1. 离开检测 (当前已记录但新扫描中不存在)
    for target, _ in pairs(self._current_targets) do
        if not new_targets[target] then
            table.insert(exited_targets, target)
        end
    end

    -- 2. 进入检测与活跃列表收集
    for target, _ in pairs(new_targets) do
        if not self._current_targets[target] then
            table.insert(entered_targets, target)
        end
        table.insert(current_active_targets, target)
    end

    self._current_targets = new_targets

    -- 3. 触发统一生命周期管线
    self:_OnExit(exited_targets)
    self:_OnEnter(entered_targets)
    self:_OnPulse(current_active_targets)
end

-- ============================================================
-- 配置与控制接口
-- ============================================================
function NikkiAura:Setup(cfg)
    if not cfg then return end

    self.owner = cfg.owner
    self.radius = cfg.radius or self.radius
    self.pulse_interval = cfg.pulse_interval or self.pulse_interval
    self.exclude_owner = cfg.exclude_owner or false
    self.selector = cfg.selector
    self.effect_id = cfg.effect_id
    self.params = cfg.params

    self.on_enter = cfg.on_enter
    self.on_pulse = cfg.on_pulse
    self.on_exit = cfg.on_exit

    if self.owner and self.owner:IsValid() then
        self.inst:ListenForEvent("onremove", function() self.inst:Remove() end, self.owner)
    end

    self:OnPulse()

    if self._task then
        self._task:Cancel()
    end
    self._task = self.inst:DoPeriodicTask(self.pulse_interval, function()
        self:OnPulse()
    end)
end

function NikkiAura:ClearAllTargets()
    local exited_targets = {}
    for target, _ in pairs(self._current_targets) do
        table.insert(exited_targets, target)
    end
    self:_OnExit(exited_targets)
    self._current_targets = {}
end

return NikkiAura
