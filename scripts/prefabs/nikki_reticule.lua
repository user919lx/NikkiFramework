local TEXTURE_SIZE = 256
local PAD_DURATION = .1
local FLASH_TIME = .3
local DEFAULT_RADIUS = 5.0

local assets =
{
    Asset("ANIM", "anim/shader_square.zip"),
    Asset("SHADER", "shaders/nikki_reticule.ksh"),
    Asset("ANIM", "anim/reticuleaoe.zip"), -- 子目标脚底标记需要用到
}

local prefabs =
{
    "nikki_reticule_sub",
}

local function ApplyScale(inst)
    local radius = inst._radius or DEFAULT_RADIUS
    local scale = math.sqrt(radius * 300 / TEXTURE_SIZE)
    inst._base_scale = scale
    inst.Transform:SetScale(scale, scale, scale)
end

-- =========================================================================
-- 形状与参数设置接口
-- =========================================================================
local function SetShape(inst, shape_name, radius, opt1)
    shape_name = shape_name and string.upper(shape_name) or "CIRCLE"
    inst._shape = shape_name
    inst._radius = tonumber(radius) or inst._radius or DEFAULT_RADIUS
    inst._opt1 = opt1 or inst._opt1
    ApplyScale(inst)
    local r = inst._radius
    if shape_name == "CIRCLE" then
        inst.AnimState:SetFloatParams(0.0, 0.0, r)
    elseif shape_name == "CONE" then
        local total_angle = (tonumber(inst._opt1) or 60) * DEGREES
        inst.AnimState:SetFloatParams(1.0, total_angle * 0.5, r)
    elseif shape_name == "LINE" then
        local width = tonumber(inst._opt1) or 1.0
        local width_ratio = math.clamp((width / r) * 0.5, 0.01, 1.0)
        inst.AnimState:SetFloatParams(2.0, width_ratio, r)
    elseif shape_name == "ARROW" then
        local width = tonumber(inst._opt1) or 1.0
        local width_ratio = math.clamp((width / r) * 0.5, 0.01, 1.0)
        inst.AnimState:SetFloatParams(3.0, width_ratio, r)
    else
        inst.AnimState:SetFloatParams(0.0, 0.0, r)
    end
end

local function SetRadius(inst, radius)
    SetShape(inst, inst._shape or "CIRCLE", radius, inst._opt1)
end

-- =========================================================================
-- 子目标搜索与标记管理 (优化缓存版)
-- =========================================================================
local function ClearSubTargets(inst)
    if inst._targets ~= nil then
        for ent, fx in pairs(inst._targets) do
            if fx:IsValid() then
                fx:Remove()
            end
        end
        inst._targets = nil
    end
end

local function OnUpdateTargets(inst, dt)
    if inst.search_fn == nil then
        ClearSubTargets(inst)
        return
    end

    local pos = inst:GetPosition()
    local ents = inst.search_fn(inst, pos)

    -- 获取主瞄准器当前的颜色（同步合法/非法状态）
    local r, g, b, a = inst.AnimState:GetMultColour()

    if ents ~= nil and #ents > 0 then
        if inst._targets == nil then
            inst._targets = {}
        end

        -- 1. 找出当前帧被选中的有效实体表
        local current_ents = {}
        for _, ent in ipairs(ents) do
            if ent:IsValid() then
                current_ents[ent] = true

                -- 如果是新目标，则创建特效
                if inst._targets[ent] == nil then
                    local newfx = SpawnPrefab("nikki_reticule_sub")
                    if newfx ~= nil then
                        ent:AddChild(newfx)
                        inst._targets[ent] = newfx
                    end
                end

                -- 实时同步颜色
                if inst._targets[ent] ~= nil and inst._targets[ent]:IsValid() then
                    inst._targets[ent].AnimState:SetMultColour(r, g, b, a)
                end
            end
        end

        -- 2. 清理已经不在当前选区内的老目标特效
        for old_ent, fx in pairs(inst._targets) do
            if not current_ents[old_ent] then
                if fx:IsValid() then
                    fx:Remove()
                end
                inst._targets[old_ent] = nil
            end
        end
    else
        ClearSubTargets(inst)
    end
end

local function SetSearchFn(inst, fn)
    inst.search_fn = fn
    if fn ~= nil then
        if inst.components.updatelooper == nil then
            inst:AddComponent("updatelooper")
        end
        inst.components.updatelooper:AddOnUpdateFn(OnUpdateTargets)
    else
        if inst.components.updatelooper ~= nil then
            inst.components.updatelooper:RemoveOnUpdateFn(OnUpdateTargets)
            inst:RemoveComponent("updatelooper")
        end
        ClearSubTargets(inst)
    end
end

-- =========================================================================
-- 动画更新
-- =========================================================================
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

-- =========================================================================
-- 实体工厂
-- =========================================================================
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

        inst.AnimState:SetDefaultEffectHandle(resolvefilepath("shaders/nikki_reticule.ksh"))

        inst._base_scale = 1.0
        inst._radius = DEFAULT_RADIUS
        inst._shape = "CIRCLE"
        inst._opt1 = nil

        inst.SetShape = SetShape
        inst.SetRadius = SetRadius
        inst.SetSearchFn = SetSearchFn

        SetShape(inst, "CIRCLE", DEFAULT_RADIUS)
        inst:ListenForEvent("onremove", ClearSubTargets)

        return inst
    end
    return Prefab(name, fn, assets, prefabs)
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
    return Prefab(name, fn, assets, prefabs)
end

-- 独立的子目标实体（参考官方 reticulemultitargetsub）
local function MakeSub(name)
    local function fn()
        local inst = CreateEntity()
        inst:AddTag("FX")
        inst:AddTag("NOCLICK")
        inst.entity:SetCanSleep(false)
        inst.persists = false

        inst.entity:AddTransform()
        inst.entity:AddAnimState()

        -- 借用官方原版的小圈圈动画
        inst.AnimState:SetBank("reticuleaoe")
        inst.AnimState:SetBuild("reticuleaoe")
        inst.AnimState:PlayAnimation("idle_target_1")
        inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
        inst.AnimState:SetLayer(LAYER_WORLD_BACKGROUND)
        inst.AnimState:SetSortOrder(3)

        return inst
    end
    return Prefab(name, fn, assets)
end

return MakeReticule("nikki_reticule"),
    MakePing("nikki_reticule_ping", 1.08),
    MakeSub("nikki_reticule_sub")
