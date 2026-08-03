local log = require("utils/log")
local TEXTURE_SIZE = 1900
local assets = {
    Asset("ANIM", "anim/firefighter_placement.zip"),
}

local function CalcScaleByRange(range)
    return math.sqrt(range * 300 / TEXTURE_SIZE)
end

local function ApplyScale(inst)
    local scale = CalcScaleByRange(inst._range)
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

-- 统一处理显隐逻辑：只有 (开关开启) 且 (射程 > 0) 时才显示
local function UpdateVisibility(inst)
    if inst._is_toggled_on and inst._range > 0 then
        inst:Show()
    else
        inst:Hide()
    end
end

local function SetRange(inst, range)
    local value = tonumber(range) or 0
    inst._range = value

    if value > 0 then
        ApplyScale(inst)
    end

    -- 每次射程改变，重新评估显隐状态
    UpdateVisibility(inst)
end

local function Attach(inst, owner)
    if owner and owner.entity then
        inst.owner = owner
        inst.entity:SetParent(owner.entity)

        -- ==========================================================
        -- 事件管控 1：纯粹的显隐开关监听 (接收包含 new_state 的 payload)
        -- ==========================================================
        inst:ListenForEvent("skill_range_toggle_changed", function(owner_inst, data)
            if data ~= nil and data.new_state ~= nil then
                log.debug("[Nikki Range Indicator] Received toggle event: new_state = %s", tostring(data.new_state))
                inst._is_toggled_on = data.new_state
                UpdateVisibility(inst)
            end
        end, owner)

        -- ==========================================================
        -- 事件管控 2：纯粹的射程数值更新监听 (接收 max_range 的 payload)
        -- ==========================================================
        inst:ListenForEvent("skill_max_range_dirty", function(owner_inst, data)
            if data ~= nil and data.max_range ~= nil then
                SetRange(inst, data.max_range)
            end
        end, owner)

        -- ==========================================================
        -- 初始状态拉取：仅同步当前射程大小
        -- ==========================================================
        if owner.replica.nikki_skill then
            SetRange(inst, owner.replica.nikki_skill:GetMaxRange() or 0)
        end
    end
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
    -- 内部变量：记录当前 UI 的开关状态
    inst._is_toggled_on = false

    inst.SetRange = SetRange
    inst.Attach = Attach

    return inst
end

return Prefab("nikki_range_indicator", fn, assets)
