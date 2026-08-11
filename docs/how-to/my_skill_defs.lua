--[[
    技能定义文件
    位置：scripts/defs/my_skill_defs.lua
    Skill 代表瞬间影响的能力（按键触发、事件响应、资源消耗等）
]]

-- 辅助：形态切换映射表
local STATE_MAP = {
    ["default"] = "state_jump",
    ["state_jump"] = "state_attack",
    ["state_attack"] = "default",
}

local skills = {
    -- ============================================================
    -- 基础技能
    -- ============================================================

    -- 打开技能轮盘（纯客户端）
    open_wheel = {
        name = "打开技能轮盘",
        client_only = true,
        client_fn = function(inst)
            if inst.replica.nikki_skillwheel then
                inst.replica.nikki_skillwheel:OpenWheel()
            end
        end,
    },

    -- 切换形态（服务端）
    state_switch = {
        name = "切换形态",
        fn = function(inst, params, def)
            local current = inst.components.nikki_state:GetState()
            local next_state = STATE_MAP[current] or "default"
            inst.components.nikki_state:SetState(next_state)
            return true
        end,
    },

    -- ============================================================
    -- 简单技能（无消耗、无冷却）
    -- ============================================================

    -- 释放基础效果
    apply_brisk = {
        name = "轻盈脚步",
        fn = function(inst, params, def)
            inst.components.nikki_effect:Apply("brisk", inst)
            return true
        end,
    },

    -- ============================================================
    -- 带消耗和冷却的技能
    -- ============================================================

    -- 召唤蜘蛛
    summon_spider = {
        name = "召唤蜘蛛",
        required_tags = { "can_summon_basic" },
        cost = { res = "spark", amount = 10 },
        cd = 5,
        fn = function(inst, params, def)
            local pos = params and params.pos or inst:GetPosition()
            local minion = SpawnPrefab("spider")
            minion.Transform:SetPosition(pos:Get())
            return true
        end,
    },

    -- 月焰（带冷却 + 服务端逻辑）
    lunar_fire = {
        name = "月焰",
        cost = { res = "mana", amount = 25 },
        cd = 20,
        required_tags = { "lunar_master" },
        fn = function(inst, params, def)
            if inst.components.rider and inst.components.rider:IsRiding() then
                return false, "CANT_SPELL_MOUNTED"
            end
            if inst.components.channelcaster and not inst.components.channelcaster:IsChanneling() then
                local fx = SpawnPrefab("flamethrower_fx")
                fx.entity:SetParent(inst.entity)
                fx:SetFlamethrowerAttacker(inst)
                local endtask = fx:DoTaskInTime(3, function(_, doer)
                    if doer.components.channelcaster then
                        doer.components.channelcaster:StopChanneling()
                    end
                end, inst)
                fx:ListenForEvent("stopchannelcast", function()
                    if fx then
                        endtask:Cancel()
                        fx:KillFX()
                        fx = nil
                    end
                end, inst)
                if inst.components.channelcaster:StartChanneling() then
                    return true
                end
                fx:Remove()
            end
            return false
        end,
    },

    -- ============================================================
    -- 双端技能（client_fn + fn）
    -- ============================================================

    -- 净化弹：客户端预测 + 服务端执行
    purify = {
        name = "净化",
        range = 15,
        cost = { res = "mana", amount = 10 },
        cd = 3,
        required_tags = { "can_cast_purify" },
        tags = { "is_casting" },
        -- 服务端逻辑
        fn = function(inst, params, def)
            local target = params and params.target
            if not target or not target:IsValid() then
                return false, "INVALID_TARGET"
            end
            target.components.health:DoDelta(-50)
            return true
        end,
        -- 客户端预测
        client_fn = function(inst, params, def)
            if inst.replica.rider and inst.replica.rider:IsRiding() then
                return false, "IS_RIDING"
            end
            -- 客户端表现
            inst.components.talker:Say("净化！")
            return true
        end,
    },

    -- ============================================================
    -- 带默认触发器的事件技能
    -- ============================================================

    -- 蛙卫：被攻击时触发
    frog_guard = {
        name = "蛙卫",
        fn = function(inst, params, def)
            local attacker = params.attacker
            if attacker and not attacker:HasTag("frog") then
                inst.components.combat:ShareTarget(attacker, 30,
                    function(dude) return dude:HasTag("frog") and not dude.components.health:IsDead() end,
                    30
                )
            end
            return true
        end,
        default_triggers = {
            events = {
                attacked = true,
            },
        },
    },

    -- 迸火：攻击命中时触发（带上下文覆盖）
    spark_burst = {
        name = "迸火",
        params = {
            aoe_damage = 85,
            aoe_range = 5,
        },
        fn = function(inst, params, def)
            inst.components.nikki_effect:Apply("blast_round", inst)
            return true
        end,
        default_triggers = {
            events = {
                onhitother = {
                    required_tags = { "blast_round" },
                    cost = { res = "spark", amount = 1 },
                    cd = 1,
                    fn = function(inst, params, def)
                        local target = params and params.target
                        if not target or not target:IsValid() then
                            return false
                        end
                        local x, y, z = target.Transform:GetWorldPosition()
                        local fx = SpawnPrefab("explosivehit")
                        fx.Transform:SetPosition(x, y, z)
                        -- AOE 伤害逻辑
                        local entities = TheSim:FindEntities(x, y, z, def.params.aoe_range, nil,
                            { "INLIMBO", "notarget", "playerghost", "FX" })
                        for _, ent in ipairs(entities) do
                            if ent.components.combat and ent.components.health and not ent.components.health:IsDead() then
                                ent.components.combat:GetAttacked(inst, def.params.aoe_damage)
                            end
                        end
                        return true
                    end,
                },
            },
        },
    },

    -- ============================================================
    -- 带生命周期回调的技能
    -- ============================================================

    -- 跳跃：添加/移除时挂载/卸载组件
    jump = {
        name = "跳跃",
        client_only = true,
        on_add = function(inst, def)
            if not inst.components.jumper then
                inst:AddComponent("jumper")
            end
            inst.components.jumper:OnAirStateExit()
        end,
        on_remove = function(inst, def)
            -- 注意：不要移除带 net_var 的组件
        end,
        client_fn = function(inst, params, def)
            if inst.replica.jumper then
                return inst.replica.jumper:TryJump()
            end
            return false
        end,
    },

    -- ============================================================
    -- 瞬发轮盘技能（无选点流程）
    -- ============================================================

    whim_space = {
        name = "奇想衣橱",
        fn = function(inst, params, def)
            if inst and inst._wardrobe then
                local container = inst._wardrobe.components.container
                if container then
                    if container:IsOpenedBy(inst) then
                        container:Close(inst)
                    else
                        container:Open(inst)
                    end
                end
            end
            return true
        end,
        on_add = function(inst, def)
            if not inst._wardrobe or not inst._wardrobe:IsValid() then
                inst._wardrobe = SpawnPrefab("nikki_wardrobe")
                inst._wardrobe.entity:SetParent(inst.entity)
            end
        end,
        on_remove = function(inst, def)
            -- 保留 wardrobe，避免服装丢失
        end,
        wheel = {
            instant = true,
            ui = {
                image = {
                    atlas = "images/nikki_spell_icons.xml",
                    normal = "whim_space.tex",
                },
            },
        },
    },
}

-- ============================================================
-- 加载外部轮盘配置（拆分 wheel 配置到单独文件）
-- ============================================================
local ok, skillwheels = pcall(require, "defs/my_skillwheel_defs")
if ok and type(skillwheels) == "table" then
    for id, wheel_data in pairs(skillwheels) do
        if skills[id] then
            skills[id].wheel = skills[id].wheel or wheel_data
        end
    end
end

return skills