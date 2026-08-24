local TEXTURE_SIZE = 256
local assets = {
    Asset("ANIM", "anim/shader_circle.zip"),
}

local function SetRadius(inst, radius)
    local r = tonumber(radius) or 5.0
    local scale = math.sqrt(r * 300 / TEXTURE_SIZE)
    inst.Transform:SetScale(scale, scale, scale)
end

local function Attach(inst, owner)
    if owner and owner:IsValid() then
        inst.Follower:FollowSymbol(owner.GUID, "", 0, 0, 0, false, false)
        inst.Transform:SetNoFaced()
        inst.owner = owner
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddFollower()
    inst.entity:AddNetwork()

    inst.Transform:SetNoFaced()
    inst.entity:SetCanSleep(false)
    inst.persists = false

    inst:AddTag("NOCLICK")
    inst:AddTag("FX")

    inst.AnimState:SetBank("shader_circle")
    inst.AnimState:SetBuild("shader_circle")
    inst.AnimState:PlayAnimation("idle", true)
    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    inst.AnimState:SetLayer(LAYER_WORLD_BACKGROUND)
    inst.AnimState:SetSortOrder(3)
    inst:Hide()

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("nikki_aura")

    -- 基础便捷操作接口
    inst.SetRadius = SetRadius
    inst.Attach = Attach

    return inst
end

return Prefab("nikki_aura", fn, assets)