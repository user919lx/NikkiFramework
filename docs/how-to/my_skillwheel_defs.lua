--[[
    技能轮盘 UI 配置
    位置：scripts/defs/my_skillwheel_defs.lua
    此文件独立于技能定义，便于 UI 配置与核心逻辑分离
]]

local ICON_SCALE = 0.6

-- ============================================================
-- 瞄准圈辅助函数
-- ============================================================

-- 自由选点：在玩家前方 7 格范围内寻找可通行点
local function ReticuleTargetAllowWaterFn()
    local player = ThePlayer
    if not player then
        return Vector3(0, 0, 0)
    end
    local ground = TheWorld.Map
    local pos = Vector3()
    for radius = 7, 0, -0.25 do
        pos.x, pos.y, pos.z = player.entity:LocalToWorldSpace(radius, 0, 0)
        if ground:IsPassableAtPoint(pos.x, 0, pos.z, true) and not ground:IsGroundTargetBlocked(pos) then
            return pos
        end
    end
    return pos
end

-- 方向施法：返回玩家前方 5 格位置
local function LineReticuleTargetFn(inst)
    if ThePlayer and ThePlayer.components.playercontroller and
        ThePlayer.components.playercontroller.isclientcontrollerattached then
        return Vector3(ThePlayer.entity:LocalToWorldSpace(5, 0, 0))
    end
end

-- 方向施法鼠标瞄准
local function LineReticuleMouseTargetFn(inst, mousepos)
    if not mousepos then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local dx = mousepos.x - x
    local dz = mousepos.z - z
    local l = dx * dx + dz * dz
    if l <= 0 then
        return inst.components.reticule.targetpos
    end
    l = 6.5 / math.sqrt(l)
    return Vector3(x + dx * l, 0, z + dz * l)
end

-- 方向施法瞄准圈更新
local function LineReticuleUpdatePositionFn(inst, pos, reticule, ease, smoothing, dt)
    if not ThePlayer then return end
    reticule.Transform:SetPosition(ThePlayer.Transform:GetWorldPosition())
    local rot = reticule:GetAngleToPoint(inst.components.reticule.targetpos)
    if ease and dt then
        local current_rot = reticule.Transform:GetRotation()
        rot = Lerp(current_rot, current_rot + ReduceAngle(rot - current_rot), dt * smoothing)
    end
    reticule.Transform:SetRotation(rot)
end

-- ============================================================
-- 轮盘技能配置
-- ============================================================

return {
    -- 暗影囚牢：范围选点
    ["shadow_prison"] = {
        ui = {
            image = {
                atlas = "images/spell_icons.xml",
                normal = "shadow_pillars.tex",
            },
        },
        aoe = {
            allow_water = true,
            reticule = {
                reticuleprefab = "reticuleaoe",
                pingprefab = "reticuleaoeping",
                targetfn = ReticuleTargetAllowWaterFn,
            },
        },
    },

    -- 月焰：方向施法（动画方式）
    ["lunar_fire"] = {
        ui = {
            widget_scale = ICON_SCALE,
            anim = {
                bank = "spell_icons_willow",
                build = "spell_icons_willow",
                anims = {
                    idle = { anim = "lunar_fire" },
                    focus = { anim = "lunar_fire_focus", loop = true },
                    down = { anim = "lunar_fire_pressed" },
                    cooldown = { anim = "lunar_fire_cooldown" },
                },
                cooldowncolor = { 1, 0.5, 0.5, 0.5 },
            },
        },
        aoe = {
            state = "castspellmind",
            allow_water = true,
            deploy_radius = 0,
            reticule = {
                reticuleprefab = "reticuleline",
                pingprefab = "reticulelineping",
                mousetargetfn = LineReticuleMouseTargetFn,
                targetfn = LineReticuleTargetFn,
                updatepositionfn = LineReticuleUpdatePositionFn,
            },
        },
    },

    -- 召唤蜘蛛：召唤类型（小范围指示）
    ["summon_spider"] = {
        ui = {
            image = {
                atlas = "images/nikki_spell_icons.xml",
                normal = "summon_spider.tex",
            },
        },
        aoe = {
            deploy_radius = 0,
            reticule = {
                reticuleprefab = "reticuleaoe_1_6",
                pingprefab = "reticuleaoeping_1_6",
            },
            target_fx = "reticuleaoesummontarget_1",
        },
    },
}
