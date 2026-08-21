local TEXTURE_SIZE = 256
local PAD_DURATION = .1
local FLASH_TIME = .3
local DEFAULT_RADIUS = 5.0

local assets =
{
    Asset("ANIM", "anim/shader_square.zip"),
    Asset("SHADER", "shaders/nikki_reticule.ksh"),
}

local function ApplyScale(inst)
    local radius = inst._radius or DEFAULT_RADIUS
    local scale = math.sqrt(radius * 300 / TEXTURE_SIZE)
    inst._base_scale = scale
    inst.Transform:SetScale(scale, scale, scale)
end

-- =========================================================================
-- 形状与参数设置接口
-- @param shape_name: "CIRCLE" | "CONE" | "LINE" | "ARROW"
-- @param radius: 作用半径 / 投射长度（世界坐标单位）
-- @param opt1: 扇形夹角(度数) 或 弹道宽度(世界坐标单位)
-- =========================================================================
local function SetShape(inst, shape_name, radius, opt1)
    shape_name = shape_name and string.upper(shape_name) or "CIRCLE"
    inst._shape = shape_name
    inst._radius = tonumber(radius) or inst._radius or DEFAULT_RADIUS
    inst._opt1 = opt1 or inst._opt1

    ApplyScale(inst)

    local r = inst._radius

    if shape_name == "CIRCLE" then
        -- p0 = 0.0(圆), p1 = 0.0, p2 = radius
        inst.AnimState:SetFloatParams(0.0, 0.0, r)
    elseif shape_name == "CONE" then
        local total_angle = (tonumber(inst._opt1) or 60) * DEGREES
        -- p0 = 1.0(扇), p1 = 半角弧度, p2 = radius
        inst.AnimState:SetFloatParams(1.0, total_angle * 0.5, r)
    elseif shape_name == "LINE" then
        local width = tonumber(inst._opt1) or 1.0
        local width_ratio = math.clamp((width / r) * 0.5, 0.01, 1.0)
        -- p0 = 2.0(双轨), p1 = 相对半宽, p2 = radius
        inst.AnimState:SetFloatParams(2.0, width_ratio, r)
    elseif shape_name == "ARROW" then
        local width = tonumber(inst._opt1) or 1.0
        local width_ratio = math.clamp((width / r) * 0.5, 0.01, 1.0)
        -- p0 = 3.0(单轨/箭头), p1 = 相对半宽, p2 = radius
        inst.AnimState:SetFloatParams(3.0, width_ratio, r)
    else
        inst.AnimState:SetFloatParams(0.0, 0.0, r)
    end
end

local function SetRadius(inst, radius)
    SetShape(inst, inst._shape or "CIRCLE", radius, inst._opt1)
end

local function UpdatePing(inst, scaleup, t0, duration, multcolour, addcolour)
    if next(multcolour) == nil then
        multcolour[1], multcolour[2], multcolour[3], multcolour[4] = inst.AnimState:GetMultColour()
    end
    if next(addcolour) == nil then
        addcolour[1], addcolour[2], addcolour[3], addcolour[4] = inst.AnimState:GetAddColour()
    end

    local t = GetTime() - t0
    local k = 1 - math.max(0, t - PAD_DURATION) / duration
    k = 1 - k * k

    local s = (inst._base_scale or 1.0) * Lerp(1.0, scaleup, k)
    local c = Lerp(1, 0, k)

    inst.Transform:SetScale(s, s, s)
    inst.AnimState:SetMultColour(multcolour[1], multcolour[2], multcolour[3], c * multcolour[4])

    k = math.min(FLASH_TIME, t) / FLASH_TIME
    c = math.max(0, 1 - k * k)
    inst.AnimState:SetAddColour(c * addcolour[1], c * addcolour[2], c * addcolour[3], c * addcolour[4])
end

local function MakeReticule(name)
    local function fn()
        local inst = CreateEntity()

        inst:AddTag("FX")
        inst:AddTag("NOCLICK")
        inst.entity:SetCanSleep(false)
        inst.persists = false

        inst.entity:AddTransform()
        inst.entity:AddAnimState()

        inst.AnimState:SetBank("shader_square")
        inst.AnimState:SetBuild("shader_square")
        inst.AnimState:PlayAnimation("idle", true)
        inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
        inst.AnimState:SetLayer(LAYER_WORLD_BACKGROUND)
        inst.AnimState:SetSortOrder(3)

        -- Base Shader 与 Bloom Shader 全部指定为自定义着色器
        inst.AnimState:SetDefaultEffectHandle(resolvefilepath("shaders/nikki_reticule.ksh"))

        inst._base_scale = 1.0
        inst._radius = DEFAULT_RADIUS
        inst._shape = "CIRCLE"
        inst._opt1 = nil

        inst.SetShape = SetShape
        inst.SetRadius = SetRadius

        SetShape(inst, "CIRCLE", DEFAULT_RADIUS)

        return inst
    end
    return Prefab(name, fn, assets)
end

local function MakePing(name, scaleup)
    local function fn()
        local inst = CreateEntity()

        inst:AddTag("FX")
        inst:AddTag("NOCLICK")
        inst.entity:SetCanSleep(false)
        inst.persists = false

        inst.entity:AddTransform()
        inst.entity:AddAnimState()

        inst.AnimState:SetBank("shader_square")
        inst.AnimState:SetBuild("shader_square")
        inst.AnimState:PlayAnimation("idle", true)
        inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
        inst.AnimState:SetLayer(LAYER_WORLD_BACKGROUND)
        inst.AnimState:SetSortOrder(3)

        inst.AnimState:SetDefaultEffectHandle(resolvefilepath("shaders/nikki_reticule.ksh"))

        inst._base_scale = 1.0
        inst._radius = DEFAULT_RADIUS
        inst._shape = "CIRCLE"
        inst._opt1 = nil

        inst.SetShape = SetShape
        inst.SetRadius = SetRadius

        SetShape(inst, "CIRCLE", DEFAULT_RADIUS)

        local duration = .4
        inst:DoPeriodicTask(0, UpdatePing, nil, scaleup or 1.08, GetTime(), duration, {}, {})
        inst:DoTaskInTime(duration + PAD_DURATION, inst.Remove)

        return inst
    end
    return Prefab(name, fn, assets)
end

return MakeReticule("nikki_reticule"),
    MakePing("nikki_reticule_ping", 1.08)
