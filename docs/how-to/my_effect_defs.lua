--[[
    效果定义文件
    位置：scripts/defs/my_effect_defs.lua
    Effect 代表持续影响的能力（加速、属性修改、周期性消耗/回复等）
]]

local effects = {
    -- ============================================================
    -- 永久效果（无 duration）
    -- ============================================================

    -- 轻盈脚步：永久移速 +20%
    brisk = {
        stack = { mode = "ignore" },
        mods = {
            spd = 1.2,
        },
        tags = { "fast" },
    },

    -- 召唤师基础：增加召唤容量 + 授予召唤能力标签
    summoner_basic = {
        stack = { mode = "ignore" },
        mods = {
            power = 4, -- 自定义修饰器，需要在 config 中注册
        },
        tags = { "can_summon_basic" },
    },

    -- 青蛙友好：永久标签
    frog_pal = {
        stack = { mode = "ignore" },
        tags = { "frog_friendly" },
    },

    -- ============================================================
    -- 限时效果（有 duration）
    -- ============================================================

    -- 净化之风：伤害 +20%，持续 10 秒
    wind_edge = {
        stack = { mode = "refresh" }, -- 重复施加刷新持续时间
        duration = 10,
        mods = {
            atk = 1.2,
        },
    },

    -- 星愿祝福：法力回复 +3/秒，持续 8 秒
    stellar = {
        stack = { mode = "ignore" },
        duration = 8,
        mods = {
            mana_regen = 3,
            mana_hit_regen = 0.2,
        },
    },

    -- ============================================================
    -- 带消耗的效果（drain / cost）
    -- ============================================================

    -- 电力蓄能：持续消耗电力，层数 >= 2 时消耗加倍
    beam = {
        stack = { mode = "add", max = 2 },
        drain = {
            res = "spark",
            rate = function(inst, def, context)
                return context.layer >= 2 and 2 or 1
            end,
        },
        -- 自定义参数，供回调使用
        params = {
            base = {
                falloff = 0.7,
                intensity = 0.75,
                radius = 2.5,
                colour = { 250 / 255, 225 / 255, 175 / 255 },
            },
            enhanced = {
                falloff = 0.4,
                intensity = 0.9,
                radius = 7.5,
                colour = { 250 / 255, 225 / 255, 175 / 255 },
            },
        },
        on_layer_update = function(inst, layers, def)
            local params = def.params
            local cfg = (layers >= 2) and params.enhanced or params.base
            if not inst.Light then
                inst.entity:AddLight()
            end
            inst.Light:SetFalloff(cfg.falloff)
            inst.Light:SetIntensity(cfg.intensity)
            inst.Light:SetRadius(cfg.radius)
            inst.Light:SetColour(cfg.colour[1], cfg.colour[2], cfg.colour[3])
            inst.Light:Enable(true)
        end,
        on_remove = function(inst, def, context)
            if inst.Light then
                inst.Light:Enable(false)
            end
        end,
    },

    -- 爆裂弹：切换模式，激活时消耗理智
    blast_round = {
        stack = { mode = "toggle" },
        cost = { res = "sanity", amount = 10 },
        duration = 10,
        tags = { "blast_round" },
        bind_to_state = true, -- 切换 State 时自动移除
        on_apply = function(inst, def, context)
            inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
        end,
        on_remove = function(inst, def, context)
            inst.AnimState:ClearBloomEffectHandle()
        end,
    },

    -- 不灭火：火焰免疫 + 火焰附近理智回复
    tamed_fire = {
        stack = { mode = "ignore" },
        tags = { "fireimmune" },
        mods = {
            fire_damage_scale = 0, -- 火焰伤害缩放为 0，即免疫
        },
        params = {
            fire_regen = {
                rate = 50 / TUNING.TOTAL_DAY_TIME,
                range = 10,
            },
        },
        fn = function(inst, dt, def, context)
            -- 每帧检查周围是否有火源，动态修改理智回复
            inst.components.sanity.custom_rate_fn = function(custom_inst)
                local rate = def.params.fire_regen and def.params.fire_regen.rate or 0
                local range = def.params.fire_regen and def.params.fire_regen.range or 0
                if rate > 0 and FindEntity(custom_inst, range, nil, { "fire" }) ~= nil then
                    return rate
                end
                return 0
            end
        end,
    },

    -- ============================================================
    -- 自定义修饰器测试
    -- ============================================================
    eff_custom_mod_test = {
        stack = { mode = "ignore" },
        mods = {
            defense = 0.5,    -- 减伤 50%
            fire_scale = 2.0, -- 火焰伤害 2 倍（与 tamed_fire 配合测试）
        },
    },
}

return effects
