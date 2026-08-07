local log = require("utils/log")

local function GetCasterOwner(inst)
    local parent = inst.entity:GetParent()
    if parent and parent:IsValid() then return parent end
    if inst.components.inventoryitem and inst.components.inventoryitem:GetGrandOwner() then
        return inst.components.inventoryitem:GetGrandOwner()
    end
    return not TheWorld.ismastersim and ThePlayer or nil
end

local function Attach(inst, owner)
    if not owner then return end
    inst.entity:SetParent(owner.entity)
    if inst.components.inventoryitem then
        inst.components.inventoryitem.GetGrandOwner = function(self) return owner end
    end
end

local function OnEntityReplicated(inst)
    inst:DoTaskInTime(1, function()
        local parent = inst.entity:GetParent()
        if parent ~= nil then
            parent.spell_caster = inst
            if inst.replica.inventoryitem then
                inst.replica.inventoryitem.IsGrandOwner = function(self, guy) return guy == parent end
            end
        end
    end)
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddNetwork()

    inst:AddTag("CLASSIFIED")
    inst:AddTag("NOCLICK")
    inst:AddTag("book")

    inst:AddComponent("aoetargeting")
    inst.components.aoetargeting:SetAllowWater(false)

    inst:AddComponent("spellbook")
    inst.components.spellbook:SetRadius(100)
    inst.components.spellbook:SetFocusRadius(102)

    -- 拦截 OpenSpellBook：向宿主的 Replica 索要最新的轮盘数据
    local _OpenSpellBook = inst.components.spellbook.OpenSpellBook
    inst.components.spellbook.OpenSpellBook = function(self, user)
        if user and user.replica.nikki_skillwheel then
            local valid_items = user.replica.nikki_skillwheel:GetWheelItems()
            if #valid_items == 0 then
                log.warn("[Nikki Spell Caster] '%s' 当前状态及 Tag 下没有可用的轮盘技能。", tostring(user))
                return false
            end
            self:SetItems(valid_items)
            return _OpenSpellBook(self, user)
        end
        return false
    end

    local _SelectSpell = inst.components.spellbook.SelectSpell
    inst.components.spellbook.SelectSpell = function(self, index)
        local owner = GetCasterOwner(self.inst)
        if owner and owner.replica.nikki_skillwheel then
            local valid_items = owner.replica.nikki_skillwheel:GetWheelItems()
            self:SetItems(valid_items)
        end
        return _SelectSpell(self, index)
    end

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
