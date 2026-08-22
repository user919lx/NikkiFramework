local log = require("utils/log")

local NikkiAura = Class(function(self, inst)
    self.inst = inst

    self.owner = nil
    self.radius = 8
    self.pulse_interval = 1.0
    self.exclude_owner = false
    self.selector = nil
    self.effect_id = nil

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
-- 内部辅助：目标身上的光环计数管理
-- ============================================================
local function AddAuraTarget(target, effect_id, owner)
    if not target or not target:IsValid() or not effect_id then return end
    target._nikki_aura_counts = target._nikki_aura_counts or {}
    local count = target._nikki_aura_counts[effect_id] or 0
    -- 只有第一次进入同类光环覆盖区时，才真正施加 Effect
    if count == 0 then
        NikkiManager:ApplyEffect(target, effect_id, owner)
    end
    target._nikki_aura_counts[effect_id] = count + 1
end

local function RemoveAuraTarget(target, effect_id)
    if not target or not target:IsValid() or not effect_id then return end
    if not target._nikki_aura_counts or not target._nikki_aura_counts[effect_id] then
        return
    end
    local count = target._nikki_aura_counts[effect_id] - 1
    if count <= 0 then
        target._nikki_aura_counts[effect_id] = nil
        NikkiManager:RemoveEffect(target, effect_id)
    else
        target._nikki_aura_counts[effect_id] = count
    end
end

-- ============================================================
-- 目标搜索与周期检测
-- ============================================================
local function FindTargets(self)
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

function NikkiAura:OnPulse()
    if not self.effect_id then
        log.error("[NikkiAura] No effect_id set for aura, skipping pulse.", self.inst)
        return
    end

    if self.owner and not self.owner:IsValid() then
        self.inst:Remove()
        log.error("[NikkiAura] Owner is invalid, removing aura entity.", self.inst)
        return
    end

    local new_targets = FindTargets(self)

    -- 1. 离开光环：扣除该目标身上的光环计数
    for target, _ in pairs(self._current_targets) do
        if not new_targets[target] then
            RemoveAuraTarget(target, self.effect_id)
        end
    end

    -- 2. 进入光环：增加该目标身上的光环计数
    for target, _ in pairs(new_targets) do
        if not self._current_targets[target] then
            AddAuraTarget(target, self.effect_id, self.owner)
        end
    end

    self._current_targets = new_targets
end

-- ============================================================
-- 控制接口
-- ============================================================
function NikkiAura:Setup(cfg)
    if not cfg then return end

    self.owner = cfg.owner
    self.radius = cfg.radius or self.radius
    self.pulse_interval = cfg.pulse_interval or self.pulse_interval
    self.exclude_owner = cfg.exclude_owner or false
    self.selector = cfg.selector
    self.effect_id = cfg.effect_id

    if self.owner and self.owner:IsValid() then
        self.inst:ListenForEvent("death", function() self.inst:Remove() end, self.owner)
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
    if not self.effect_id then return end

    for target, _ in pairs(self._current_targets) do
        RemoveAuraTarget(target, self.effect_id)
    end

    self._current_targets = {}
end

return NikkiAura
