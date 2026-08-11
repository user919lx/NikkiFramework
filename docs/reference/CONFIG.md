# Config 配置手册

`config` 是框架的顶层配置文件，在 `modmain.lua` 中通过 `NikkiFrameworkManager.Init(config, env)` 传入。



## 顶层字段概览

| 字段               | 类型  | 必填 | 说明                 |
| :----------------- | :---- | :--- | :------------------- |
| `defs`             | table | 是   | 数据源文件路径       |
| `apply_to`         | table | 是   | 组件装配目标         |
| `custom_resources` | table | 否   | 自定义资源注册       |
| `custom_modifiers` | table | 否   | 自定义属性修饰器注册 |


## defs

指定 Effect、Skill、State 定义文件的位置。

**类型**：`table`

| 字段            | 类型   | 必填 | 说明                             |
| :-------------- | :----- | :--- | :------------------------------- |
| `effect`        | string | 否   | 效果定义文件路径，不含 `.lua`    |
| `skill`         | string | 否   | 技能定义文件路径，不含 `.lua`    |
| `state`         | table  | 否   | 形态配置                         |
| `state.file`    | string | 是   | 形态定义文件路径，不含 `.lua`    |
| `state.basic`   | string | 是   | 基础形态名，所有形态继承自它     |
| `state.default` | string | 是   | 默认形态名，实体生成时的初始形态 |

**路径说明**：路径相对于 `scripts/` 目录。`"defs/effect_defs"` 对应 `scripts/defs/effect_defs.lua`。

示例：

```lua
defs = {
    effect = "defs/effect_defs",
    skill = "defs/skill_defs",
    state = {
        file = "defs/state_defs",
        basic = "basic",
        default = "default",
    }
}
```

## apply_to

指定框架组件挂载到哪些实体上。支持按 `prefabs` 精确匹配或按 `tag` 筛选匹配。

**类型**：`table<string, ApplyTarget>`

**层级说明**：

| 层级     | 挂载组件                                                                                       | 适用场景             |
| :------- | :--------------------------------------------------------------------------------------------- | :------------------- |
| `player` | nikki_effect + nikki_skill + nikki_skill_trigger + nikki_state + nikki_skillwheel + 自定义资源 | 玩家角色             |
| `skill`  | nikki_effect + nikki_skill + nikki_skill_trigger + nikki_state + 自定义资源                    | 拥有技能的非玩家角色 |
| `effect` | nikki_effect                                                                                   | 仅接收效果的实体     |

### ApplyTarget 字段

| 字段      | 类型     | 说明                 |
| :-------- | :------- | :------------------- |
| `prefabs` | string[] | 按 prefab 名精确匹配 |
| `tag`     | string   | 按标签匹配           |

`prefabs` 和 `tag` 可同时使用，也可只用其一。

示例：

```lua
apply_to = {
    player = {
        prefabs = { "wilson", "wendy" },
        tag = "player",
    },
    skill = {
        prefabs = { "deerclops" },
    },
    effect = {
        tag = "_combat",
    }
}
```

## custom_resources

注册自定义资源，使框架能够管理该资源的读写、回复/消耗和 UI 显示。

**类型**：`table<string, ResourceConfig>`


ResourceConfig内容

| 字段                     | 类型            | 必填 | 说明                                                         |
| :----------------------- | :-------------- | :--- | :----------------------------------------------------------- |
| `component`              | table           | 是   | 服务端组件配置                                               |
| `component.name`         | string          | 是   | 组件名称，如 `"nikki_mana"`                                  |
| `component.get_current`  | string          | 否   | 获取当前值的方法名，默认 `"GetCurrent"`                      |
| `component.do_delta`     | string          | 否   | 增减值的方法名，默认 `"DoDelta"`                             |
| `component.set_regen`    | string          | 否   | 设置回复的方法名，默认 `"SetRegenMod"`                       |
| `component.remove_regen` | string          | 否   | 移除回复的方法名，默认 `"RemoveRegenMod"`                    |
| `replica`                | table           | 否   | 客户端同步配置                                               |
| `replica.get_percent`    | string          | 否   | 获取百分比的方法名，默认 `"GetPercent"`                      |
| `replica.get_max`        | string          | 否   | 获取最大值的方法名，默认 `"GetMax"`                          |
| `replica.get_rate_scale` | string          | 否   | 获取速率缩放的方法名，默认 `"GetRateScale"`                  |
| `ui`                     | boolean / table | 否   | UI 配置，`true` 表示使用默认，或传入 `{ bank, build, anim }` |

示例：
```lua
custom_resources = {
    -- 极简写法
    ["mana"] = {
        component = { name = "nikki_mana" },
        ui = true
    },
    -- 详细配置
    ["spark"] = {
        component = {
            name = "nikki_spark",
            get_current = "GetCurrent",
            do_delta = "DoDelta",
            set_regen = "SetRegenMod",
            remove_regen = "RemoveRegenMod"
        },
        replica = {
            get_percent = "GetPercent",
            get_max = "GetMax",
            get_rate_scale = "GetRateScale"
        },
        ui = { bank = "sparkbadge", build = "sparkbadge", anim = "anim" }
    }
},
```


## custom_modifiers

注册自定义属性修饰器，使 Effect 能够修改角色属性。

**类型**：`table<string, ModifierStrategy>`

### ModifierStrategy 字段

| 字段     | 类型     | 必填 | 说明                                              |
| :------- | :------- | :--- | :------------------------------------------------ |
| `apply`  | function | 是   | `function(inst, val, effect_id)` 应用修改 |
| `remove` | function | 是   | `function(inst, effect_id)` 移除修改              |

**参数说明**：

| 参数        | 类型   | 说明                                      |
| :---------- | :----- | :---------------------------------------- |
| `inst`      | entity | 目标实体                                  |
| `val`       | number | 配置表中填写的数值                        |
| `effect_id` | string | 效果唯一标识，用于移除时匹配              |

示例：

```lua
custom_modifiers = {
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
        end
    },
},
```


### 内置修饰器

以下修饰器无需注册即可直接使用：

| ID                  | 说明             | 取值示例                |
| :------------------ | :--------------- | :---------------------- |
| `atk`               | 攻击倍率(叠乘)     | `1.2` 表示 伤害x120%         |
| `spd`               | 移速倍率(叠乘)     | `1.2` 表示 移速x120%         |
| `dmg_taken`         | 承受伤害倍率（叠乘） | `1.3` 表示 承伤(扣除护甲吸收后)x130%     |
| `fire_damage_scale` | 火焰伤害缩放（覆盖）     | `2.0` 表示 2 倍火焰伤害 |


## 完整示例

```lua
return {
    -- ========================================================
    -- 数据源
    -- ========================================================
    defs = {
        effect = "defs/test_effect_defs",
        skill = "defs/test_skill_defs",
        state = {
            file = "defs/test_state_defs",
            basic = "basic",
            default = "default",
        }
    },
    -- ========================================================
    -- 装配目标
    -- ========================================================
    apply_to = {
        player = {
            tag = "player",
            prefabs = { "samansha", "wilson" },
        },
        skill = {
            prefabs = { "deerclops" },
        },
        effect = {
            tag = "_combat",
        }
    },
    -- ========================================================
    -- 自定义扩展
    -- ========================================================
    custom_resources = {
        ["mana"] = {
            component = { name = "nikki_mana" },
            ui = true
        },
        ["spark"] = {
            component = {
                name = "nikki_spark",
                get_current = "GetCurrent",
                do_delta = "DoDelta",
                set_regen = "SetRegenMod",
                remove_regen = "RemoveRegenMod"
            },
            replica = {
                get_percent = "GetPercent",
                get_max = "GetMax",
                get_rate_scale = "GetRateScale"
            },
            ui = { bank = "sparkbadge", build = "sparkbadge", anim = "anim" }
        }
    },
    custom_modifiers = {
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
            end
        },
        ["fire_scale"] = {
            apply = function(inst, val, effect_id)
                if inst.components.health ~= nil then
                    inst.components.health.fire_damage_scale = val
                end
            end,
            remove = function(inst, effect_id)
                if inst.components.health ~= nil then
                    inst.components.health.fire_damage_scale = 1
                end
            end
        }
    },
}
```