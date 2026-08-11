--[[
    形态定义文件
    位置：scripts/defs/my_state_defs.lua
    State 代表一组能力的集合（Effect + Skill + Trigger + 外观）
]]

local CORE_ACT_KEY = TUNING_NIKKI and TUNING_NIKKI.ACT_KEY or "KEY_Z"

local states = {
    -- ============================================================
    -- basic：所有形态的模板
    -- ============================================================
    ["basic"] = {
        skills = {
            "state_switch",
            "open_wheel",
            "whim_space",
        },
        triggers = {
            keys = {
                ["KEY_Z"] = "state_switch",
                ["KEY_X"] = "open_wheel",
            },
        },
    },

    -- ============================================================
    -- default：角色初始形态
    -- ============================================================
    ["default"] = {
        visuals = { build = "wilson" },
        -- 依赖 basic 继承 skills 和 triggers
    },

    -- ============================================================
    -- 跳跃形态
    -- ============================================================
    ["state_jump"] = {
        visuals = { build = "wilson_jump" },
        effects = { "brisk" },
        tags = { "can_jump" },
        skills = { "jump" },
        triggers = {
            keys = {
                ["KEY_C"] = "jump",
            },
        },
    },

    -- ============================================================
    -- 攻击形态
    -- ============================================================
    ["state_attack"] = {
        visuals = { build = "wilson_attack" },
        badges = { "mana" },
        effects = { "wind_edge" },
        skills = { "purify", "summon_spider" },
        triggers = {
            keys = {
                [CORE_ACT_KEY] = "purify",
            },
            events = {
                ["onhitother"] = {
                    ["spark_burst"] = true,
                },
            },
            actions = {
                ["CHOP"] = {
                    ["summon_spider"] = true,
                },
            },
        },
    },

    -- ============================================================
    -- 火形态：绑定 State，切换时自动移除
    -- ============================================================
    ["state_fire"] = {
        visuals = { build = "wilson_fire" },
        badges = { "spark" },
        effects = {
            "tamed_fire",
            "blast_round", -- bind_to_state = true，切形态自动移除
        },
        skills = { "lunar_fire" },
        triggers = {
            keys = {
                [CORE_ACT_KEY] = "lunar_fire",
            },
        },
    },

    -- ============================================================
    -- 暗影形态
    -- ============================================================
    ["state_shadow"] = {
        visuals = { build = "wilson_shadow" },
        badges = { "mana" },
        effects = {
            "shadow_weave",
        },
        skills = { "shadow_prison" },
        triggers = {
            keys = {
                [CORE_ACT_KEY] = "shadow_prison",
            },
        },
    },

    -- ============================================================
    -- 月形态
    -- ============================================================
    ["state_lunar"] = {
        visuals = { build = "wilson_lunar" },
        badges = { "mana" },
        effects = {
            "lunar_grace",
            "stellar",
        },
        skills = { "lunar_fire" },
        triggers = {
            keys = {
                [CORE_ACT_KEY] = "lunar_fire",
            },
        },
    },
}

return states
