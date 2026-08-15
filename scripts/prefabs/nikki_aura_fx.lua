local TEXTURE_SIZE = 256
local assets = {
    Asset("ANIM", "anim/shader_circle.zip"),
    Asset("SHADER", "shaders/default_aura.ksh"),
}



local function ApplyScale(inst)
    local scale = math.sqrt(inst._range * 300 / TEXTURE_SIZE)
    inst.Transform:SetScale(scale, scale, scale)
end

local function SetRange(inst, range)
    inst._range = tonumber(range) or 0
    if inst._range > 0 then
        ApplyScale(inst)
    end
end

local function Attach(inst, owner)
    if owner then
        -- 挂载到角色身上，但不继承旋转角度（保持世界坐标系方向）
        inst.Follower:FollowSymbol(owner.GUID, "", 0, 0, 0, false, false)
        -- 关键：锁定世界朝向
        inst.Transform:SetNoFaced() -- 或者不在跟随中继承父级旋转
        ApplyScale(inst)
    end
end

local function SetShader(inst, shader_path)
    if shader_path then
        inst.AnimState:SetDefaultEffectHandle(resolvefilepath(shader_path))
        log.debug("[Nikki Aura FX] Shader set to: %s", shader_path)
    end
end

-- 直接传入周期间隔秒数（如 1.0、2.5）
local function SetPulseInterval(inst, seconds)
    local sec = tonumber(seconds) or 1.0
    inst._pulse_interval = sec
    -- 直接将秒数传给 Shader 的 FLOAT_PARAMS.x
    inst.AnimState:SetFloatParams(sec, 1.0, 1.0)
end

-- 快捷应用整个 def.aura 配置
local function ApplyAuraDef(inst, aura_def)
    if not aura_def then return end
    
    if aura_def.radius then
        inst:SetRange(aura_def.radius)
    end
    if aura_def.pulse_interval then
        inst:SetPulseInterval(aura_def.pulse_interval)
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddFollower()

    inst.Transform:SetNoFaced()

    inst.entity:SetCanSleep(false)
    inst.persists = false

    inst:AddTag("CLASSIFIED")
    inst:AddTag("NOCLICK")
    inst:AddTag("FX")

    inst.AnimState:SetBank("shader_circle")
    inst.AnimState:SetBuild("shader_circle")
    inst.AnimState:PlayAnimation("idle", true)

    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(1)

    inst.AnimState:SetDefaultEffectHandle(resolvefilepath("shaders/default_aura.ksh"))

    inst.owner = nil
    inst._range = 5.0
    inst._pulse_interval = 1.0
    ApplyScale(inst)

    -- 对外暴露的通用接口
    inst.SetRange = SetRange
    inst.Attach = Attach
    inst.SetShader = SetShader
    inst.SetPulseInterval = SetPulseInterval
    inst.ApplyAuraDef = ApplyAuraDef

    return inst
end

return Prefab("nikki_aura_fx", fn, assets)