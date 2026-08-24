# Effect 参考手册

Effect 定义文件是一个 Lua 文件，返回一个 table，其中每个 key 是一个 Effect ID，value 是该 Effect 的配置。

Effect 代表**持续影响的能力**——移速加成、属性修改、周期性消耗/回复、标签挂载等。


## 字段概览

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `duration` | number | 否 | 持续时间（秒），不填为永久 |
| `stack` | table | 否 | 叠加规则 |
| `mods` | table | 否 | 属性修饰器 |
| `tags` | string[] | 否 | 生效期间挂载的标签 |
| `drain` | table | 否 | 资源消耗 |
| `regen` | table | 否 | 资源回复 |
| `cost` | table | 否 | 激活时一次性消耗 |
| `bind_to_state` | boolean | 否 | 是否绑定state，默认false，若为true则切换state后移除 |
| `aura` | table | 否 | 范围光环配置，周期性扫描并作用于范围内实体 |
| `on_apply` | function | 否 | 激活时回调 |
| `on_remove` | function | 否 | 移除时回调 |
| `on_layer_update` | function | 否 | 层数变化时回调 |
| `fn` | function | 否 | 每帧回调 |


可在 def 中自定义字段，在回调函数中通过 `context.def` 参数访问。
```lua
my_effect = {
    duration = 5,
    my_custom_field = { radius = 5, colour = {1, 0, 0} },
    fn = function(inst, dt, context)
        local radius = context.def.my_custom_field.radius  -- 取用自定义数据
    end,
}
```


## stack

叠加规则。控制重复施加 Effect 时的行为。移除时按层递减（`duration` 耗尽或手动调用 `Remove(id)` 时减少一层），只有强制移除时（`Remove(id, true)` ），才会一次性清除全部层数。

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `mode` | string | 是 | 见下表 |
| `max` | number | 否 | 最大层数，仅 `add` 模式有效，默认 1 |

**mode 可选值**：

| 值 | 行为 |
| :--- | :--- |
| `"ignore"` | 已存在时忽略新施加 |
| `"refresh"` | 重置持续时间 |
| `"add"` | 叠加层数，达到上限时移除最旧一层 |
| `"toggle"` | 切换：有则移除，无则施加 |

```lua
-- ignore：已有则忽略
stack = { mode = "ignore" }

-- refresh：刷新持续时间
stack = { mode = "refresh" }

-- add：叠加，最多 3 层
stack = { mode = "add", max = 3 }

-- toggle：开关切换
stack = { mode = "toggle" }

```

## mods

属性修饰器。key 为修饰器 ID，value 为数值。

**内置修饰器**（无需注册即可使用）：

| ID | 说明 | 取值示例 |
| :--- | :--- | :--- |
| `atk` | 攻击倍率（叠乘） | `1.2` = x120% |
| `spd` | 移速倍率（叠乘） | `1.2` = x120% |
| `dmg_taken` | 承受伤害倍率（叠乘，护甲后结算） | `1.3` = x130% |
| `fire_damage_scale` | 火焰伤害缩放（覆盖） | `2.0` = 2 倍，效果移除后恢复为1倍 |

自定义修饰器请参考 [Config 配置手册](./CONFIG.md#custom_modifiers)。



## drain / regen

资源消耗或回复。

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `res` | string | 是 | 资源 ID，需在 `custom_resources` 中注册 |
| `rate` | number / function | 是 | 每秒数值。函数写法：`function(inst, context)` 返回数值 |
| `on_deplete` | string | 否 | 仅 `drain` 有效，见下表 |

**on_deplete**：

| 值 | 行为 |
| :--- | :--- |
| `"remove"`（默认） | 资源耗尽时，自动移除 Effect |
| `"keep"` | 资源耗尽后，不会自动移除Effect，在 `fn` 中可通过 `context.is_depleted` 获取变化，动态处理 |

```lua
-- 固定数值消耗
drain = { res = "health", rate = 5 }
-- 函数动态计算：层数 >= 2 时消耗翻倍
drain = {
    res = "spark",
    rate = function(inst, context)
        return context.layers >= 2 and 4 or 2
    end,
}
-- 回复
regen = { res = "sanity", rate = 10 }

-- on_deplete = "keep"：资源耗尽后由 fn 自行处理
drain = {
    res = "health",
    rate = 10,
    on_deplete = "keep",
}
```


## cost

激活时一次性消耗，仅在首次施加时扣除（叠加刷新不重复扣除）。

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `res` | string | 是 | 资源 ID |
| `amount` | number | 是 | 消耗量 |

```lua
cost = { res = "sanity", amount = 10 }
```

## bind_to_state

`true` 时，切换 State 自动移除该 Effect；`false`（默认）则不受 State 切换影响。

## aura（光环）

光环是一种特殊的 Effect：它以“脉冲扫描 + 空间范围判定”的方式周期性处理范围内的实体。
在设计模型上，**光环本质上就是为其影响范围内的合法实体施加一个 Effect**。当实体进入光环范围时自动施加该 Effect，离开光环范围或光环被销毁时自动移除该 Effect。

### aura 字段概览

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :---: | :--- |
| `radius` | number | 是 | 光环的物理作用半径（DST 世界单位） |
| `pulse_interval` | number | 否 | 脉冲扫描频率（秒），默认 `1.0` |
| `exclude_owner` | boolean | 否 | 是否将施法者自身排除在目标之外，默认 `false` |
| `selector` | table | 否 | 目标过滤规则，见下表 |
| `postinit` | function | 否 | 对光环实体执行初始化回调：`function(inst)` |
| `effect` | table | 是 | 光环施加给目标的 Effect 定义表，完全遵循标准 Effect 的字段规范|

### selector

`selector` 采用“与（AND）”逻辑，细化为三类判定：

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :---: | :--- |
| `must_have` | string[] | 否 | 目标必须拥有全部这些标签 |
| `must_have_one_of` | string[] | 否 | 目标必须至少拥有其中一个标签 |
| `cant_have` | string[] | 否 | 目标不能拥有任意一个标签 |

也就是说，目标只有在同时满足：
- `must_have` 中全部存在
- `must_have_one_of` 中至少一个存在（若表非空）
- `cant_have` 中全部不存在

时，才会被判定为光环的有效目标并自动挂载 `effect`。

### 光环 Effect 的上下文说明

在 `effect` 内部的回调函数（`on_apply`、`fn`、`on_remove`）中：
- 第一个参数 `inst`：代表**受光环影响的目标实体**。
- `context.source`：会自动绑定为**光环的施法者（Owner）**。
- 目标离开光环时会自动调用标准 Effect 的 `on_remove` 回调，完成清理。


**示例：圣水光环技能（开关型光环）**
```lua
return {
    holy_water_aura = {
        name = "圣水领域",
        range = 8,
        toggle = {
            cost = { res = "sanity", amount = 10 },
            aura = {
                radius = 8,
                pulse_interval = 1.0,
                exclude_owner = false,
                selector = {
                    must_have = { "_combat" },
                    cant_have = { "playerghost", "dead", "INLIMBO" },
                },
                -- 对光环实体的初始化回调
                postinit = function(inst)
                    -- 特效
                    inst.AnimState:SetDefaultEffectHandle(resolvefilepath("shaders/default_aura.ksh"))
                    -- 添加光亮
                    inst.entity:AddLight()
                    inst.Light:SetRadius(4)
                    inst.Light:SetIntensity(0.6)
                    inst.Light:SetColour(180 / 255, 220 / 255, 255 / 255)
                    inst.Light:Enable(true)
                end,
                -- 作用于光环内目标的标准 Effect
                effect = {
                    mods = {
                        spd = 1.15,         -- 移速增加 15%
                        dmg_taken = -0.1,    -- 减伤 10%
                    },
                    tags = { "holy_blessing" },
                    stack = { mode = "add", max = 3 }, -- 支持多个光环叠加层数
                    -- 每秒回复5生命
                    regen = {
                        res = "health",
                        rate = 5
                    }
                    on_apply = function(inst, context)
                        -- context.source 即为光环拥有者/施法者
                        local caster = context.source
                        if inst.components.talker and inst ~= caster then
                            local caster_str = tostring(caster.prefab)
                            inst.components.talker:Say("感受到了圣水的庇佑！感谢"..caster_str)
                        end
                    end,
                    on_remove = function(inst, context)
                        -- 离开光环范围时自动触发清理
                    end,
                },
            },
        },
    },
}
```


## 回调函数

| 字段 | 签名 | 说明 |
| :--- | :--- | :--- |
| `on_apply` | `function(inst, context)` | 激活时调用 |
| `on_remove` | `function(inst, context)` | 移除时调用 |
| `on_layer_update` | `function(inst, layers, context)` | 层数变化时调用。首次挂载时触发一次（层数=1），add 模式后续叠加/减少时再次触发。 |
| `fn` | `function(inst, dt, context)` | 每帧调用，返回 `false` 时自动移除 |

```lua
-- on_apply：播放特效
on_apply = function(inst, context)
    inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
end,
-- on_remove：清理特效
on_remove = function(inst, context)
    inst.AnimState:ClearBloomEffectHandle()
end,
-- on_layer_update：根据层数切换灯光强度
on_layer_update = function(inst, context)
    local layers = context.layers
    if layers >= 2 then
        inst.Light:SetIntensity(1.0)
    else
        inst.Light:SetIntensity(0.5)
    end
end,
-- fn：每帧检测，生命值归零时自动移除
fn = function(inst, dt, context)
    local hp = inst.components.health and inst.components.health.currenthealth or 0
    if hp <= 0 then
        return false
    end
    -- 每秒恢复 1 点生命（dt 累计）
    context.data.counter = (context.data.counter or 0) + dt
    if context.data.counter >= 1 then
        inst.components.health:DoDelta(1)
        context.data.counter = 0
    end
end,
```

## context 对象

回调中可用的 context 对象：

| 字段/方法 | 说明 |
| :--- | :--- |
| `def` | Effect定义数据 |
| `layers` | 当前层数 |
| `start_time` | 首次激活时间 |
| `end_times` | 各层结束时间队列 |
| `data` | 自定义存储，初始 `{}` |
| `source` | 施法者 |
| `is_depleted` | 仅 `drain` 有效，资源是否耗尽 |
| `:GetTotalRemain()` | 总剩余时间 |
| `:GetNextRemain()` | 最近一层的剩余时间 |


## 完整示例


```lua
return {
    -- 永久加速
    brisk = {
        stack = { mode = "ignore" },
        mods = { spd = 1.2 },
        tags = { "fast" },
    },
    -- 限时加攻，可叠加 3 层
    attack_buff = {
        stack = { mode = "add", max = 3 },
        duration = 5,
        mods = { atk = 1.2 },
        on_apply = function(inst, context)
            inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
        end,
        on_remove = function(inst, context)
            inst.AnimState:ClearBloomEffectHandle()
        end,
    },
    -- 激活消耗 + 持续消耗，耗尽时自动移除
    power_mode = {
        stack = { mode = "toggle" },
        cost = { res = "sanity", amount = 10 },
        drain = { res = "sanity", rate = 2 },
        mods = { atk = 1.5, spd = 1.3 },
        fn = function(inst, dt, context)
            -- 每秒掉血 1 点（用 counter 累计）
            context.data.counter = (context.data.counter or 0) + dt
            if context.data.counter >= 1 then
                inst.components.health:DoDelta(-1)
                context.data.counter = 0
            end
        end,
    },
    -- 绑定 State：切形态自动移除
    state_bound = {
        stack = { mode = "ignore" },
        bind_to_state = true,
        mods = { spd = 1.5 },
    },
}
```