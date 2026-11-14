local SourceModifierList = require("util/sourcemodifierlist")
local UpvalueHelper = require("utils/upvalue_helper")

return {
    -- ========================================================
    -- 基础定义文件路径
    -- ========================================================
    defs = {
        actions = "defs/default_action_defs",
        sgs = "defs/default_sg_defs",
    },
    -- ========================================================
    -- 自定义基础属性修饰 (Modifiers)
    -- ========================================================
    custom_modifiers = {
        -- 攻击倍率增量 (正数为加攻)
        atk = {
            apply = function(inst, val, key)
                if inst.components.combat and inst.components.combat.externaldamagemultipliers then
                    inst.components.combat.externaldamagemultipliers:SetModifier(inst, val, key)
                end
            end,
            remove = function(inst, key)
                if inst.components.combat and inst.components.combat.externaldamagemultipliers then
                    inst.components.combat.externaldamagemultipliers:RemoveModifier(inst, key)
                end
            end
        },
        -- 承受伤害倍率增量 (正数为易伤，负数为减伤，在防具结算后生效)
        dmg_taken = {
            apply = function(inst, val, key)
                if inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
                    inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, val, key)
                end
            end,
            remove = function(inst, key)
                if inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
                    inst.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, key)
                end
            end
        },
        -- 移速倍率增量 (正数为加速)
        spd = {
            apply = function(inst, val, key)
                if inst.components.locomotor then
                    inst.components.locomotor:SetExternalSpeedMultiplier(inst, key, val)
                end
            end,
            remove = function(inst, key)
                if inst.components.locomotor then
                    inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, key)
                end
            end
        },
        -- 火焰伤害倍率
        fire_dmg = {
            apply = function(inst, val, key)
                if inst.components.health then
                    inst.components.health.fire_damage_scale = val
                end
            end,
            remove = function(inst, key)
                if inst.components.health then
                    inst.components.health.fire_damage_scale = 1
                end
            end
        },
        -- 免疫昏睡
        no_sleep = {
            apply = function(inst, val, key)
                if val ~= true then return end
                if inst.components.grogginess then
                    inst.components.grogginess:AddImmunitySource(key)
                end
            end,
            remove = function(inst, key)
                if inst.components.grogginess then
                    inst.components.grogginess:RemoveImmunitySource(key)
                end
            end
        },
        -- 免疫禁锢（钢羊浓痰）
        no_pin = {
            apply = function(inst, val, key)
                if val ~= true then return end
                local comp = inst.components.pinnable
                if not comp then return end
                if not comp._nikki_pin_sources then
                    comp._nikki_pin_sources = {}
                end
                comp._nikki_pin_sources[key] = true
                comp.canbepinned = false
                if comp:IsStuck() then
                    comp:Unstick()
                end
            end,
            remove = function(inst, key)
                local comp = inst.components.pinnable
                if not comp or not comp._nikki_pin_sources then return end
                comp._nikki_pin_sources[key] = nil
                if not next(comp._nikki_pin_sources) then
                    comp.canbepinned = true
                end
            end
        },
        -- 皮弗娄牛驯化获取速度加成
        beefalo = {
            -- 注册时自动完成底层 Upvalue Patch（全局单次执行）
            init = function(env)
                local Domesticatable = require("components/domesticatable")
                local DoDeltaDomestication = UpvalueHelper.GetUpvalue(Domesticatable.DeltaDomestication,
                    "DoDeltaDomestication")
                if not DoDeltaDomestication then return end
                local old_ApplyDomesticationSkillMult = UpvalueHelper.GetUpvalue(DoDeltaDomestication,
                    "ApplyDomesticationSkillMult")
                if not old_ApplyDomesticationSkillMult then return end
                local function New_ApplyDomesticationSkillMult(inst, delta, doer)
                    local trainer = doer or (inst.components.rideable ~= nil and inst.components.rideable:GetRider()) or
                        nil
                    local bonus = trainer and trainer._nikki_domestication_bonus and
                        trainer._nikki_domestication_bonus:Get() or 0
                    if bonus > 0 then
                        delta = delta * (1 + bonus)
                    end
                    return old_ApplyDomesticationSkillMult(inst, delta, doer)
                end
                UpvalueHelper.SetUpvalue(DoDeltaDomestication, "ApplyDomesticationSkillMult",
                    New_ApplyDomesticationSkillMult)
            end,
            apply = function(inst, val, key)
                if not inst._nikki_domestication_bonus then
                    inst._nikki_domestication_bonus = SourceModifierList(inst, 0, SourceModifierList.additive)
                end
                inst._nikki_domestication_bonus:SetModifier(key, val, key)
            end,
            remove = function(inst, key)
                if inst._nikki_domestication_bonus then
                    inst._nikki_domestication_bonus:RemoveModifier(key, key)
                end
            end
        },
    },
    -- ========================================================
    -- 自定义基础消耗资源池 (Resources)
    -- ========================================================
    custom_resources = {
        health = {
            component = {
                name = "health",
                get_current = function(comp) return comp.currenthealth or 0 end,
                do_delta = function(comp, amount) comp:DoDelta(amount, false, "nikki_skill") end,
                set_regen = function(inst, comp, rate, key)
                    if comp.AddRegenSource then
                        comp:AddRegenSource(inst, rate * FRAMES, FRAMES, key)
                    end
                end,
                remove_regen = function(inst, comp, rate, key)
                    if comp.RemoveRegenSource then
                        comp:RemoveRegenSource(inst, key)
                    end
                end
            }
        },
        sanity = {
            component = {
                name = "sanity",
                get_current = function(comp) return comp.current or 0 end,
                do_delta = function(comp, amount) comp:DoDelta(amount, false) end,
                set_regen = function(inst, comp, rate, key)
                    if comp.externalmodifiers then
                        comp.externalmodifiers:SetModifier(inst, rate, key)
                    end
                end,
                remove_regen = function(inst, comp, rate, key)
                    if comp.externalmodifiers then
                        comp.externalmodifiers:RemoveModifier(inst, key)
                    end
                end
            }
        },
        hunger = {
            component = {
                name = "hunger",
                get_current = function(comp) return comp.current or 0 end,
                do_delta = function(comp, amount) comp:DoDelta(amount, false) end,
                set_regen = function(inst, comp, rate, key)
                    if not comp.nikki_regen_modifiers then
                        comp.nikki_regen_modifiers = SourceModifierList(inst, 0, SourceModifierList.additive)
                        local _OldDoDec = comp.DoDec
                        comp.DoDec = function(self, dt, ignore_damage)
                            local extra_rate = self.nikki_regen_modifiers:Get()
                            if extra_rate ~= 0 then
                                local original_rate = self.hungerrate
                                self.hungerrate = original_rate - extra_rate
                                _OldDoDec(self, dt, ignore_damage)
                                self.hungerrate = original_rate
                            else
                                _OldDoDec(self, dt, ignore_damage)
                            end
                        end
                    end
                    comp.nikki_regen_modifiers:SetModifier(inst, rate, key)
                end,
                remove_regen = function(inst, comp, rate, key)
                    if comp.nikki_regen_modifiers then
                        comp.nikki_regen_modifiers:RemoveModifier(inst, key)
                    end
                end
            }
        }
    }
}
