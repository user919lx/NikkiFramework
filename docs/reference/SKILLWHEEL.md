# SkillWheel 参考手册

SkillWheel 是 Skill 在 UI 上的可视化入口。通过在 Skill 定义中添加 `wheel` 字段，可以将技能挂载到技能轮盘上，供玩家点击施放。

**注意**：`wheel` 字段属于 Skill 定义的一部分，不单独定义文件。本手册仅说明 `wheel` 字段的配置方式。

## 配置方式

`wheel` 字段可以直接写在 Skill 定义中：

```lua
-- defs/skill_defs.lua
local skills = {
    ["shadow_prison"] = {
        name = "影牢",
        cost = { res = "mana", amount = 25 },
        cd = 10,
        fn = function(inst, params, def)
            local pos = params and params.pos
            if not pos then return false end
            local spell = SpawnPrefab("shadow_pillar_spell")
            spell.Transform:SetPosition(pos:Get())
            return true
        end,
        wheel = {
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
    },
}
```
但对于轮盘技能较多的 Mod，**建议将 wheel 配置拆分到单独的文件中**（如 defs/skillwheel_defs.lua），然后在 Skill 定义文件中通过 pcall 加载并合并：
```lua
-- defs/skillwheel_defs.lua
return {
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
    ["lunar_fire"] = {
        ui = {
            widget_scale = 0.6,
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
}
```
```lua
-- 在 skill_defs.lua 末尾加载并合并
local ok, skillwheels = pcall(require, "defs/skillwheel_defs")
if ok and type(skillwheels) == "table" then
    for id, wheel_data in pairs(skillwheels) do
        if skills[id] then
            skills[id].wheel = skills[id].wheel or wheel_data
        end
    end
end
```

**这样做的原因**：wheel 配置通常包含大量 UI 和瞄准圈相关字段（atlas、reticule、targetfn 等），与技能核心逻辑（fn、cost、cd）混在一起会显得臃肿。拆分后，技能逻辑与 UI 配置分离，便于维护

### 设计说明
SkillWheel 的配置本质上是对官方 SpellBook 组件 UI 参数的一层透传。wheel.ui 中的 image 和 anim 配置、aoe 中的 reticule 配置，均与官方 SpellBook 的 UI 规范保持一致。

因此，本手册不逐一展开每个字段的详尽解释。如需深入了解各字段的具体含义和用法，请直接参考官方 SpellBook 相关代码（如 `waxwelljournal.lua` `willow_ember.lua` ）。框架的配置只是将这些参数以结构化方式暴露出来。

## 施法模式

SkillWheel 支持三种施法行为模式，由 `instant` 和 `aoe` 两个字段共同决定：

**瞬发模式（instant = true）**：点击轮盘图标后立即施放，无选点流程，无施法动画。适用于自我增益、切换状态等无需选择目标的技能。

**瞄准模式（有 aoe 配置）**：点击轮盘图标后进入选点状态，玩家选择位置或目标后执行技能。适用于范围技能、召唤技能、指向性技能等。

**标准模式（instant = false / 未设置，且无 aoe）**：点击轮盘图标后进入官方 SpellBook 的标准施法流程（通常会播放施法动画，然后执行技能逻辑）。适用于需要施法动作配合的技能。

三种模式互斥，按 `instant` → `aoe` → 标准模式的优先级判定。


## 字段概览

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `ui` | table | 是 | UI 显示配置，详见下方 |
| `aoe` | table | 否 | 范围指示配置，详见下方 |
| `instant` | boolean | 否 | `true` 时点击立即释放，无动画 |


## ui

UI 显示配置，决定技能在轮盘上的外观和行为。

**两种展示方式（二选一）：**

**图片方式（image）**：
| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `atlas` | string | 是 | 图集路径 |
| `normal` | string | 是 | 正常状态贴图 |
| `focus` | string | 否 | 焦点状态贴图 |
| `disabled` | string | 否 | 禁用状态贴图 |
| `down` | string | 否 | 按下状态贴图 |
| `selected` | string | 否 | 选中状态贴图 |
```lua
ui = {
    image = {
        atlas = "images/spell_icons.xml",
        normal = "shadow_pillars.tex",
        focus = "shadow_pillars_focus.tex",
        disabled = "shadow_pillars_disabled.tex",
        down = "shadow_pillars_down.tex",
        selected = "shadow_pillars_selected.tex",
    },
    widget_scale = 0.6,
    hit_radius = 50,
    clicksound = "dontstarve/common/spellbook_cast",
    helptext = "在目标区域召唤暗影囚牢",
}
```
**动画方式（anim）**：
| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `bank` | string | 是 | 动画 bank |
| `build` | string | 是 | 动画 build |
| `anims` | table | 是 | 各状态动画名，含 `idle`、`focus`、`down`、`cooldown` |
| `cooldowncolor` | table | 否 | 冷却遮罩颜色，默认 `{ 0.65, 0.65, 0.65, 0.75 }` |
```lua
ui = {
    widget_scale = 0.6,
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
    checkenabled = function(owner)
        local rider = owner and owner.replica.rider
        return not (rider and rider:IsRiding())
    end,
}
```
**通用字段**：
| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `widget_scale` | number | 否 | 图标缩放，默认 0.6 |
| `hit_radius` | number | 否 | 点击命中半径。图片模式下默认为 50，动画模式下无默认值 |
| `clicksound` | string | 否 | 点击音效 |
| `helptext` | string | 否 | 帮助文本，显示在轮盘图标下方 |
| `checkenabled` | function | 否 | `function(owner)` 自定义可用状态判断，返回 `true` 或 `false` |


## aoe

范围指示器配置，用于需要选择释放位置的技能。

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `state` | string | 否 | 选中时挂载的 SG State 标签（如 `"book"`、`"castspellmind"`） |
| `allow_water` | boolean | 否 | 是否允许释放在水上，默认 `false` |
| `deploy_radius` | number | 否 | 部署半径，默认 0 |
| `target_fx` | string | 否 | 目标点特效 prefab |
| `should_repeat_cast_fn` | function | 否 | 是否重复施放的判断函数 |
| `reticule` | table | 否 | 瞄准圈配置，见下方 |

**reticule 字段**：
| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| `reticuleprefab` | string | 瞄准圈 prefab |
| `pingprefab` | string | 落点指示器 prefab |
| `targetfn` | function | 自定义目标位置计算函数 |
| `mousetargetfn` | function | 鼠标悬停时的目标位置计算函数 |
| `updatepositionfn` | function | 每帧更新瞄准圈位置的回调 |

```lua
aoe = {
    state = "castspellmind",
    allow_water = true,
    deploy_radius = 0,
    target_fx = "reticuleaoesummontarget_1",
    should_repeat_cast_fn = function(inst, doer)
        return doer.replica.inventory:Has("willow_ember", 5)
    end,
    reticule = {
        reticuleprefab = "reticuleline",
        pingprefab = "reticulelineping",
        mousetargetfn = function(inst, mousepos)
            if mousepos == nil then return end
            local x, y, z = inst.Transform:GetWorldPosition()
            local dx = mousepos.x - x
            local dz = mousepos.z - z
            local l = dx * dx + dz * dz
            if l <= 0 then return inst.components.reticule.targetpos end
            l = 6.5 / math.sqrt(l)
            return Vector3(x + dx * l, 0, z + dz * l)
        end,
        targetfn = function(inst)
            if ThePlayer and ThePlayer.components.playercontroller
                and ThePlayer.components.playercontroller.isclientcontrollerattached then
                return Vector3(ThePlayer.entity:LocalToWorldSpace(5, 0, 0))
            end
        end,
        updatepositionfn = function(inst, pos, reticule, ease, smoothing, dt)
            if not ThePlayer then return end
            reticule.Transform:SetPosition(ThePlayer.Transform:GetWorldPosition())
            local rot = reticule:GetAngleToPoint(inst.components.reticule.targetpos)
            if ease and dt then
                local current_rot = reticule.Transform:GetRotation()
                rot = Lerp(current_rot, current_rot + ReduceAngle(rot - current_rot), dt * smoothing)
            end
            reticule.Transform:SetRotation(rot)
        end,
    },
}
```
## 轮盘显示控制

技能是否出现在轮盘上由三个条件共同决定：

1. 技能必须在当前 State 生效的 `skills` 列表中（含从 `basic` 继承的）
2. 技能必须定义了 `wheel` 字段
3. 实体必须满足技能的 `required_tags` 条件（空或未设置则始终满足）

任一条件不满足，技能都不会出现在轮盘中。


```lua
-- 以下技能会出现在轮盘上
-- 条件：在当前 State 的 skills 列表中 + 有 wheel 定义 + required_tags 满足（或无）
["purify"] = {
    name = "净化",
    required_tags = { "can_cast_purify" },
    wheel = { ui = { image = { atlas = "images/spell_icons.xml", normal = "purify.tex" } } },  -- 有 wheel
},

-- 以下技能不会出现在轮盘上：不在 skills 列表中（虽然 required_tags 满足且有 wheel）
-- （假设当前 State 的 skills 列表中没有 "shadow_prison"）
["shadow_prison"] = {
    name = "影牢",
    required_tags = { "shadow_master" },
    wheel = { ui = { image = { atlas = "images/spell_icons.xml", normal = "shadow_pillars.tex" } } },
},

-- 以下技能不会出现在轮盘上：有 wheel 但 required_tags 不满足
["lunar_fire"] = {
    name = "月焰",
    required_tags = { "lunar_master" },   -- 实体缺少此 tag
    wheel = { ui = { anim = { bank = "spell_icons_willow", build = "spell_icons_willow", anims = { idle = { anim = "lunar_fire" } } } } },
},

-- 以下技能不会出现在轮盘上：在 skills 列表中且 required_tags 满足，但没有 wheel 定义
["jump"] = {
    name = "跳跃",
    -- 没有 wheel 字段，所以不会出现在轮盘上
},

-- 以下技能始终显示在轮盘上（在 skills 列表中 + 有 wheel + 无 required_tags）
["open_wheel"] = {
    name = "打开轮盘",
    client_only = true,
    client_fn = function(inst) inst.replica.nikki_skillwheel:OpenWheel() end,
    wheel = { ui = { image = { atlas = "images/ui_icons.xml", normal = "wheel.tex" } } },
},
```

## 完整示例

```lua
-- defs/skillwheel_defs.lua
local ICON_SCALE = 0.6

local function ReticuleTargetAllowWaterFn()
    local player = ThePlayer
    if not player then return Vector3(0, 0, 0) end
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

local function LineReticuleTargetFn(inst)
    if ThePlayer and ThePlayer.components.playercontroller and
        ThePlayer.components.playercontroller.isclientcontrollerattached then
        return Vector3(ThePlayer.entity:LocalToWorldSpace(5, 0, 0))
    end
end

local function LineReticuleMouseTargetFn(inst, mousepos)
    if not mousepos then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local dx = mousepos.x - x
    local dz = mousepos.z - z
    local l = dx * dx + dz * dz
    if l <= 0 then return inst.components.reticule.targetpos end
    l = 6.5 / math.sqrt(l)
    return Vector3(x + dx * l, 0, z + dz * l)
end

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

return {
    -- 范围选点技能
    shadow_prison = {
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

    -- 方向施法技能（动画方式）
    lunar_fire = {
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

    -- 召唤技能（工厂函数生成）
    summon_spider = {
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
```

```lua
-- defs/skill_defs.lua
local skills = {
    -- 技能定义...
    shadow_prison = {
        name = "影牢",
        cost = { res = "mana", amount = 25 },
        cd = 10,
        fn = function(inst, params, def)
            local pos = params and params.pos
            if not pos then return false end
            local spell = SpawnPrefab("shadow_pillar_spell")
            spell.Transform:SetPosition(pos:Get())
            return true
        end,
    },

    lunar_fire = {
        name = "月焰",
        cost = { res = "mana", amount = 25 },
        cd = 20,
        required_tags = { "lunar_master" },
        fn = function(inst, params, def)
            if inst.components.rider and inst.components.rider:IsRiding() then
                return false, "CANT_SPELL_MOUNTED"
            end
            local fx = SpawnPrefab("flamethrower_fx")
            fx.entity:SetParent(inst.entity)
            -- ...
            return true
        end,
    },

    summon_spider = {
        name = "召唤蜘蛛",
        cost = { res = "spark", amount = 10 },
        required_tags = { "can_summon_basic" },
        fn = function(inst, params, def)
            if inst.components.summoner then
                return inst.components.summoner:Summon("spider", params.pos)
            end
        end,
    },
}
-- 加载外部轮盘配置
local ok, skillwheels = pcall(require, "defs/skillwheel_defs")
if ok and type(skillwheels) == "table" then
    for id, wheel_data in pairs(skillwheels) do
        if skills[id] then
            skills[id].wheel = skills[id].wheel or wheel_data
        end
    end
end
return skills
```