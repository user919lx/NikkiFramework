--[[
    框架启动配置文件
    位置：scripts/defs/my_config.lua
    在 modmain.lua 中通过 NikkiFrameworkManager.Init(my_config, env) 加载
]]

local config = {
    -- ============================================================
    -- 自定义资源注册
    -- ============================================================
    custom_resources = {
        -- 法力资源（极简写法）
        ["mana"] = {
            component = { name = "nikki_mana" },
            ui = true,
        },
        -- 电力资源（自定义方法名 + 自定义UI）
        ["spark"] = {
            component = {
                name = "nikki_spark",
                get_current = "GetCurrent",
                do_delta = "DoDelta",
                set_regen = "SetRegenMod",
                remove_regen = "RemoveRegenMod",
            },
            replica = {
                get_percent = "GetPercent",
                get_max = "GetMax",
                get_rate_scale = "GetRateScale",
            },
            ui = { bank = "sparkbadge", build = "sparkbadge", anim = "anim" },
        },
    },

    -- ============================================================
    -- 自定义属性修饰器注册
    -- ============================================================
    custom_modifiers = {
        -- 防御：利用官方 externalabsorbmodifiers
        ["defense"] = {
            apply = function(inst, val, effect_id)
                if inst.components.health and inst.components.health.externalabsorbmodifiers then
                    inst.components.health.externalabsorbmodifiers:SetModifier(inst, val, effect_id)
                end
            end,
            remove = function(inst, effect_id)
                if inst.components.health and inst.components.health.externalabsorbmodifiers then
                    inst.components.health.externalabsorbmodifiers:RemoveModifier(inst, effect_id)
                end
            end,
        },
        -- 火焰缩放（覆盖式赋值）
        ["fire_scale"] = {
            apply = function(inst, val, effect_id)
                if inst.components.health then
                    inst.components.health.fire_damage_scale = val
                end
            end,
            remove = function(inst, effect_id)
                if inst.components.health then
                    inst.components.health.fire_damage_scale = 1
                end
            end,
        },
    },

    -- ============================================================
    -- 数据源路径
    -- ============================================================
    defs = {
        effect = "defs/my_effect_defs",
        skill = "defs/my_skill_defs",
        state = {
            file = "defs/my_state_defs",
            basic = "basic",
            default = "default",
        },
    },

    -- ============================================================
    -- 装配目标
    -- ============================================================
    apply_to = {
        player = {
            prefabs = { "wilson", "wendy" },
            tag = "player",
        },
        skill = {
            prefabs = { "deerclops", "bearger" },
        },
        effect = {
            tag = "_combat",
        },
    },
}

return config
