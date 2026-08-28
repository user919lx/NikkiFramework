local log = require("utils/log")

local function Attach(inst, owner)
    if not owner then return end
    inst.entity:SetParent(owner.entity)
    if inst.components.inventoryitem then
        inst.components.inventoryitem.GetGrandOwner = function(self) return owner end
        -- 不能直接赋值 否则无法打开轮盘界面
        -- inst.components.inventoryitem.owner = owner
    end
    if owner.components.inventory then
        local _CanAccessItem = owner.components.inventory.CanAccessItem
        owner.components.inventory.CanAccessItem = function(self, item)
            -- 若校验的对象是当前虚拟施法器，直接无条件放行
            if item == inst then
                return true
            end
            return _CanAccessItem(self, item)
        end
    end
end
local function CheckAndLinkParent(inst)
    local parent = inst.entity:GetParent()
    if parent ~= nil then
        -- 1. 成功找到宿主，清理任务
        if inst._link_task ~= nil then
            inst._link_task:Cancel()
            inst._link_task = nil
        end
        inst._link_attempts = nil

        -- 2. 绑定数据
        parent.spell_caster = inst
        if inst.replica.inventoryitem then
            inst.replica.inventoryitem.IsGrandOwner = function(self, guy) return guy == parent end
        end
        -- 3. 发送就绪事件
        parent:PushEvent("nikki_spell_caster_ready", inst)
    else
        -- 找不到宿主时，增加重试计数
        inst._link_attempts = (inst._link_attempts or 0) + 1
        -- 超时检测：60 次约等于 2 秒（饥荒默认 30 TPS）
        if inst._link_attempts > 60 then
            if inst._link_task ~= nil then
                inst._link_task:Cancel()
                inst._link_task = nil
            end
            inst._link_attempts = nil
            log.warn("[Nikki Spell Caster] Failed to link to parent after 60 attempts")
            if not TheWorld.ismastersim then inst:Remove() end
        end
    end
end

local function OnEntityReplicated(inst)
    inst._link_attempts = 0
    -- 0 代表每一帧执行一次
    inst._link_task = inst:DoPeriodicTask(0, CheckAndLinkParent)
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddNetwork()
    inst.entity:AddAnimState()

    inst:AddTag("CLASSIFIED")
    inst:AddTag("NOCLICK")

    inst:AddComponent("aoetargeting")
    inst:AddComponent("spellbook")
    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        inst.OnEntityReplicated = OnEntityReplicated
        return inst
    end

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.canbepickedup = false
    inst:AddComponent("aoespell")
    inst.Attach = Attach

    return inst
end

return Prefab("nikki_spell_caster", fn)
