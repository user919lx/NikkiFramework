-- scripts/prefabs/nikki_range_indicator.lua
local log = require("utils/log")
local TEXTURE_SIZE = 1900
local assets = {
    Asset("ANIM", "anim/firefighter_placement.zip"),
}

local function CalcScaleByRange(range)
    return math.sqrt(range * 300 / TEXTURE_SIZE)
end

-- ============================================================
-- ApplyScale：根据传入的 range 计算并应用缩放
-- ============================================================
local function ApplyScale(inst, range)
    local scale = CalcScaleByRange(range)
    local owner = inst.owner
    if owner and owner.Transform then
        local sx, sy, sz = owner.Transform:GetScale()
        sx = sx == 0 and 1 or sx
        sy = sy == 0 and 1 or sy
        sz = sz == 0 and 1 or sz
        inst.Transform:SetScale(scale / sx, scale / sy, scale / sz)
    else
        inst.Transform:SetScale(scale, scale, scale)
    end
end

-- ============================================================
-- UpdateVisibility：决定显示/隐藏 + 应用缩放
-- ============================================================
local function UpdateVisibility(inst)
    local should_show = false
    local display_range = 0

    if inst._override_active then
        should_show = inst._override_range and inst._override_range > 0
        display_range = inst._override_range or 0
        log.debug("[Nikki Range Indicator] Override mode active: should_show=%s, display_range=%s", tostring(should_show), display_range)
    else
        should_show = inst._is_toggled_on and inst._range > 0
        display_range = inst._range
        log.debug("[Nikki Range Indicator] Normal mode: should_show=%s, display_range=%s", tostring(should_show), display_range)
    end

    if should_show then
        ApplyScale(inst, display_range)
        inst:Show()
    else
        inst:Hide()
    end
end

-- ============================================================
-- SetRange：只更新 _range 数据
-- ============================================================
local function SetRange(inst, range)
    local value = tonumber(range) or 0
    inst._range = value
    UpdateVisibility(inst)
end

function SetOwner(inst, owner)
    if owner and owner.entity then
        inst.owner = owner
        inst.entity:SetParent(owner.entity)

        inst._override_active = false
        inst._override_range = nil
        inst._range = 0
        inst._is_toggled_on = false

        inst:ListenForEvent("skill_range_toggle_changed", function(owner_inst, data)
            if data ~= nil and data.new_state ~= nil then
                log.debug("[Nikki Range Indicator] Received toggle event: new_state = %s", tostring(data.new_state))
                inst._is_toggled_on = data.new_state
                if not inst._override_active then
                    UpdateVisibility(inst)
                end
            end
        end, owner)

        inst:ListenForEvent("skill_max_range_dirty", function(owner_inst, data)
            if data ~= nil and data.max_range ~= nil then
                SetRange(inst, data.max_range)
            end
        end, owner)

        if owner.replica.nikki_skill then
            SetRange(inst, owner.replica.nikki_skill:GetMaxRange() or 0)
        end
    end
end

-- ============================================================
-- 覆盖模式：进入瞄准状态时调用
-- ============================================================
function EnterOverride(inst, skill_range)
    if skill_range == nil or skill_range <= 0 then
        return
    end

    inst._override_active = true
    inst._override_range = skill_range
    UpdateVisibility(inst)

    log.debug("[Nikki Range Indicator] Entered override mode with range: %s", skill_range)
end

-- ============================================================
-- 退出覆盖模式：退出瞄准时调用
-- ============================================================
function ExitOverride(inst)
    if not inst._override_active then
        return
    end

    inst._override_active = false
    inst._override_range = nil
    UpdateVisibility(inst)

    log.debug("[Nikki Range Indicator] Exited override mode")
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:SetCanSleep(false)
    inst.persists = false

    inst:AddTag("CLASSIFIED")
    inst:AddTag("NOCLICK")
    inst:AddTag("FX")
    inst:AddTag("placer")

    inst.AnimState:SetBank("firefighter_placement")
    inst.AnimState:SetBuild("firefighter_placement")
    inst.AnimState:PlayAnimation("idle", true)
    inst.AnimState:SetLightOverride(1)
    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(1)
    inst.AnimState:SetAddColour(.5, .1, .2, 0)

    inst:Hide()

    inst.owner = nil
    inst._range = 0
    inst._is_toggled_on = false
    inst._override_active = false
    inst._override_range = nil

    inst.SetRange = SetRange
    inst.SetOwner = SetOwner

    inst.EnterOverride = EnterOverride
    inst.ExitOverride = ExitOverride

    return inst
end

return Prefab("nikki_range_indicator", fn, assets)
