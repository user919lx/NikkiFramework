# State 参考手册

State 定义文件是一个 Lua 文件，返回一个 table，其中每个 key 是一个 State ID，value 是该 State 的配置。

State 代表**一组能力的集合**——它把 Effect、Skill、触发器、外观、标签打包成一个可切换的形态。


## 字段概览

| 字段       | 类型     | 必填 | 说明                                                |
| :--------- | :------- | :--- | :-------------------------------------------------- |
| `visuals`  | table    | 否   | 外观配置，详见下方说明                              |
| `effects`  | string[] | 否   | 进入 State 时自动施加的 Effect 列表，退出时自动移除 |
| `skills`   | string[] | 否   | 当前 State 可用的 Skill 列表                        |
| `tags`     | string[] | 否   | 进入 State 时挂载的标签，退出时自动移除             |
| `badges`   | string[] | 否   | 在 UI 上显示的资源徽章，填写的是自定义资源id        |
| `triggers` | table    | 否   | 触发规则，将按键/事件/动作与 Skill 绑定             |

## visuals

外观配置，切换 State 时自动切换角色的贴图和动画。

| 字段    | 类型              | 必填 | 说明                                                                      |
| :------ | :---------------- | :--- | :------------------------------------------------------------------------ |
| `build` | string / function | 否   | 贴图 build 名称。不填则使用实体 prefab 名。可传 `function(inst)` 动态计算 |
| `bank`  | string            | 否   | 动画 bank 名称。不填则保持不变                                            |


```lua
-- 基本用法：指定 build 名称
visuals = { build = "willow" }

-- 动态计算 build
visuals = {
    build = function(inst)
        return inst.prefab == "wilson" and "willow" or "default"
    end,
}

-- 同时指定 build 和 bank
visuals = { build = "nikki_attack", bank = "wilson" }
```


## triggers

将按键、事件、动作与 Skill 绑定。当触发条件满足时，执行对应的 Skill。

**类型**：`table`

| 字段      | 类型  | 说明     |
| :-------- | :---- | :------- |
| `keys`    | table | 按键绑定 |
| `events`  | table | 事件绑定 |
| `actions` | table | 动作绑定 |

### keys

`keys` 支持两种写法：

**直接映射**：将按键直接映射到单个 Skill ID。
```lua
keys = {
    ["KEY_X"] = "jump",      -- 按 X 触发 jump
    ["KEY_Z"] = "purify",    -- 按 Z 触发 purify
}
```
**table**：将按键映射到多个 Skill，同时触发。

```lua
keys = {
    ["KEY_X"] = { jump = true, dash = true },   -- 按 X 同时触发 jump 和 dash
    ["KEY_Z"] = { purify = true },
}
```
### events / actions

`events` 和 `actions` 必须使用 table 形式，不支持直接字符串映射。每个事件或动作可以绑定多个 Skill，同时触发。

```lua
events = {
    ["onhitother"] = {        -- 攻击命中时
        life_steal = true,    -- 触发 life_steal
        shadow_burst = true,  -- 同时触发 shadow_burst
    },
}
actions = {
    ["CHOP"] = {              -- 砍树时
        wood_boom = true,     -- 触发 wood_boom
    },
}
```
### 屏蔽继承的触发器

当子 State 需要屏蔽从 `basic` 或 Skill 的 `default_triggers` 继承来的某个绑定时，将值设为 `false`。
`false` 在 `keys`、`events`、`actions` 中均可使用，用于精确剔除继承自 `basic` 或 Skill 自带的 `default_triggers`。

```lua
-- basic 中定义了 KEY_X = "jump"
basic = {
    triggers = {
        keys = { ["KEY_X"] = "jump" }
    }
}
-- 子 State 屏蔽 KEY_X 的 jump 绑定，KEY_X 不再触发任何技能
default = {
    triggers = {
        keys = { ["KEY_X"] = false }
    }
}
```


### 合并与覆盖

`triggers` 的最终结果由三层合并而成（优先级从低到高）：

1. **Skill 的 `default_triggers`**：最低优先级，Skill 自带的默认触发规则
2. **`basic` 的 `triggers`**：中间优先级，所有 State 共享的基础规则
3. **子 State 的 `triggers`**：最高优先级，覆盖前两层

**合并规则**：

- 同一个 key 下，子 State 完全覆盖 `basic` 中的配置
- 子 State 中将值设为 `false`，会将该 key 从最终结果中移除（包括 Skill 自带的 `default_triggers` 也会被剔除）
- 不同 key 之间互不影响，合并保留


示例：

```lua
-- Skill 自带 default_triggers
-- 假设 jump Skill 定义了 default_triggers = { keys = { ["KEY_X"] = true } }
-- basic
basic = {
    triggers = {
        keys = {
            ["KEY_X"] = "jump",    -- 来自 Skill 的 default_triggers 已经被注入，此处是显式声明
            ["KEY_Z"] = "open_wheel",
        }
    }
}
-- 子 State
default = {
    triggers = {
        keys = {
            ["KEY_X"] = false,     -- 屏蔽 jump
            ["KEY_C"] = "dash",    -- 新增 dash
        }
    }
}
-- 最终 keys 结果：
-- KEY_X: 被屏蔽，无任何技能
-- KEY_Z: open_wheel（继承自 basic）
-- KEY_C: dash（子 State 新增）
```

## 继承机制

`basic` 是一个特殊的 State，作为**所有其他 State 的基础模板**。

所有 State（包括 `default`）都会自动继承 `basic` 中定义的 `effects`、`skills`、`tags`、`triggers`。`basic` 本身也是一个普通的 State，可以被手动切换。

**合并规则**：

| 字段       | 合并方式                                                       |
| :--------- | :------------------------------------------------------------- |
| `effects`  | 合并，去重                                                     |
| `skills`   | 合并，去重                                                     |
| `tags`     | 合并，去重                                                     |
| `triggers` | 逐层合并，子 State 覆盖 `basic` 的同名绑定，`false` 可精确剔除 |
| `visuals`  | **不继承**，每个 State 独立配置                                |

**典型用途**：
- 所有形态都需要的通用技能（如切换形态、打开技能轮盘）
- 所有形态都需要的通用按键绑定
- 所有形态都需要的通用标签

### default

`default` 是实体生成时的**初始形态**。当框架挂载到实体上时，会自动切换到 `default` State，实体复活后也会恢复。`default` 同样继承自 `basic`。

## 移除行为

切换 State 时，框架自动处理以下清理：

1. 移除旧 State 通过 `effects` 施加的所有 Effect
2. 注销旧 State 的 `skills` 中的 Skill（basic 继承的也会被清理）
3. 移除旧 State 的 `tags`
4. 清空旧 State 的 `triggers`
5. 应用新 State 的外观

**注意**：Effect 自身的 `bind_to_state` 字段不受此规则影响，它控制的是 Effect 是否跟随 State 切换而移除，独立于 State 层面的 `effects` 列表管理。


## 死亡处理

实体死亡时，框架会强制清理当前 State 的所有能力，包括清空 State、移除所有 Effect、注销所有 Skill、移除所有标签、清空所有触发器。

同时，死亡状态下对 `SetState` 的调用会被**直接拒绝**（实体带 `playerghost` 标签或处于死亡状态时，`SetState` 直接返回）。

**目的**：死亡状态下实体的大部分组件已不可用，强制执行 State 切换或 Effect 回调会触发大量报错。框架主动屏蔽所有技能系统行为，避免 Bug，保证稳定性。

实体复活时，框架会自动恢复到 `default` State。


## 完整示例

```lua
return {
    -- basic：所有 State 的模板
    basic = {
        skills = {
            "open_wheel",
            "state_switch",
        },
        triggers = {
            keys = {
                ["KEY_X"] = "open_wheel",
                ["KEY_Z"] = "state_switch",
            },
        },
    },

    -- default：初始形态
    default = {
        visuals = { build = "wilson" },
    },

    -- 跳跃形态
    jump = {
        visuals = { build = "wilson_jump" },
        effects = { "brisk" },
        skills = { "jump" },
        tags = { "can_jump" },
        triggers = {
            keys = {
                ["KEY_C"] = "jump",
            },
        },
    },

    -- 攻击形态
    attack = {
        visuals = { build = "wilson_attack" },
        badges = { "mana" },
        effects = { "wind_edge" },
        skills = { "purify", "life_steal" },
        triggers = {
            keys = {
                ["KEY_V"] = "purify",
            },
            events = {
                ["onhitother"] = {
                    ["life_steal"] = true,
                },
            },
        },
    },
}
```