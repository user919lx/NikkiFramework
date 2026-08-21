local SourceModifierList = require("util/sourcemodifierlist")

return {
    -- ========================================================
    -- 基础定义文件路径
    -- ========================================================
    defs = {
        actions = "defs/default_action_defs"
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
    },

    -- ========================================================
    -- 自定义基础消耗资源池 (Resources)
    -- ========================================================
    custom_resources = {
        health = {
            component = { name = "health" },
            server = {
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
            component = { name = "sanity" },
            server = {
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
            component = { name = "hunger" },
            server = {
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
