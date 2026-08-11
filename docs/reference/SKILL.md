# Skill 参考手册

Skill 定义文件是一个 Lua 文件，返回一个 table，其中每个 key 是一个 Skill ID，value 是该 Skill 的配置。

Skill 代表**瞬间影响的能力**——按键触发、事件响应、资源消耗、冷却管理、服务端执行等。


## 字段概览

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `name` | string | 否 | 技能名称，用于 UI 显示 |
| `fn` | function | 否 | 服务端执行函数，接收 `inst, params, def` |
| `client_fn` | function | 否 | 客户端执行函数，签名同 `fn` |
| `client_only` | boolean | 否 | `true` 时仅在客户端执行，不发送 RPC |
| `on_add` | function | 否 | `function(inst, def)` 技能添加时调用 |
| `on_remove` | function | 否 | `function(inst, def)` 技能移除时调用 |
| `cost` | table | 否 | 释放消耗：`{ res = "资源ID", amount = 数值 }` |
| `cd` | number | 否 | 冷却时间（秒） |
| `range` | number | 否 | 技能射程，用于 UI 显示和范围指示 |
| `required_tags` | string[] | 否 | 释放所需标签，缺少任一则无法释放。同时影响技能轮盘上的可用状态。 |
| `tags` | string[] | 否 | 技能添加时挂载、移除时清除的标签，主要用于动作触发判断 |
| `default_triggers` | table | 否 | 默认触发规则 |
| `wheel` | table | 否 | 技能轮盘 UI 配置，详见 [SkillWheel手册](./SKILLWHEEL.md) |


## 回调函数详解

### on_add / on_remove

技能生命周期回调，分别在技能被添加和移除时触发。

- `on_add` 用于挂载配套组件、初始化缓存引用；
- `on_remove` 用于清理。即使是定义在 basic 中的 Skill，也会在 State 切换时先移除再添加，因此 `on_remove` 中的清理逻辑必须保证安全、可重复执行。尤其注意不要删除对应 `replica` 带网络变量的 `component`，否则会触发网络同步错误。

```lua
on_add = function(inst, def)
    if not inst.components.jumper then
        inst:AddComponent("jumper")
    end
end,
on_remove = function(inst, def)
    -- 注意：不要移除带 net_var 的组件
end,
```

### fn 与 client_fn

`fn` 和 `client_fn` 的签名相同：`function(inst, params, def)`

- `fn`：仅在服务端执行
- `client_fn`：仅在客户端执行

**执行流程**：

1. 技能触发时，客户端先执行 `client_fn`（如存在）
   - 返回 `true`：客户端预测通过，继续执行
   - 返回 `false`：技能执行中断，不发送 RPC
2. `client_fn` 返回 `true` 且 `client_only` 不为 `true` 且技能包含 `fn` 时，向服务端发送 RPC
3. 服务端收到 RPC 后执行 `fn`，完成最终结算

**params 内容因触发方式而异：**

| 触发方式 | params 内容 |
| :--- | :--- |
| `keys` | `{ key = 按键代码 }` |
| `events` | EventCallback 的 `data` 参数（原样透传） |
| `actions` | 见下表 |

**actions 触发方式下的 params 字段：**

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| `act` | table | BufferAction 对象 |
| `origin_result` | any | ACTION.fn 的返回值 |
| `target` | entity | 目标实体 |
| `pos` | Vector3 | 目标位置 |
| `doer` | entity | 动作执行者 |
| `invobject` | entity | 动作携带的物品 |

> `act` 和 `origin_result` 固定存在；`target`、`pos`、`doer`、`invobject` 取决于 ACTION 的执行分类，不一定都有。

**设计意图**：`client_fn` 提供客户端单独执行的能力，如打开 UI、轮盘等纯客户端操作。


```lua
-- ============================================================
-- fn（基础用法）
-- ============================================================
fn = function(inst, params, def)
    local target = params.target
    if target and target:IsValid() then
        target.components.health:DoDelta(-10)
        return true
    end
    return false, "INVALID_TARGET"
end,
-- ============================================================
-- fn（带 params.pos）
-- ============================================================
fn = function(inst, params, def)
    local pos = params and params.pos
    if not pos then return false end
    local spell = SpawnPrefab("shadow_pillar_spell")
    spell.Transform:SetPosition(pos:Get())
    return true
end,
-- ============================================================
-- client_only + client_fn（纯客户端技能）
-- ============================================================
client_only = true,
client_fn = function(inst)
    if inst.replica.nikki_skillwheel then
        inst.replica.nikki_skillwheel:OpenWheel()
    end
end,
-- ============================================================
-- client_fn + fn（双端协作）
-- ============================================================
client_fn = function(inst, params, def)
    -- 客户端预测：检查是否骑乘
    if inst.replica.rider and inst.replica.rider:IsRiding() then
        return false, "IS_RIDING"
    end
    -- 客户端表现
    inst.components.talker:Say("施法！")
    return true
end,
fn = function(inst, params, def)
    -- 服务端执行
    local target = params.target
    if target and target:IsValid() then
        target.components.health:DoDelta(-50)
        return true
    end
    return false
end,
```

## default_triggers

技能自带的默认触发规则。语法与 State 的 `triggers` 一致，支持 `keys`、`events`、`actions`。发生冲突时，以State优先。

当 Skill 被加入 State 时，`default_triggers` 中的规则会自动注入到该 State 的 `compiled_triggers` 中，与 State 自身以及 `basic` 的 `triggers` 合并。

`default_triggers` 中每个触发条目的值有三种写法：

- **`true`**：绑定该触发方式，执行时使用技能顶层配置（`fn`、`cost`、`cd`、`required_tags`）
- **`function`**：作为该触发方式专用的 `fn`。框架自动转换为 `{ fn = function }`
- **`table`**：可包含 `fn`、`cost`、`cd`、`required_tags` 字段，控制该触发方式下的行为

**关于 table 中的配置继承：**
- 写了 `fn`：该触发方式完全独立，`cost`、`cd`、`required_tags` 全部用自己的值，不继承顶层（没写就是没有）
- 没写 `fn`：`fn` 继承顶层，`cost`、`cd`、`required_tags` 优先用自己的值，没有则继承顶层

```lua
-- ============================================================
--  写法一：true
-- ============================================================
default_triggers = {
    events = {
        attacked = true,
    },
    actions = {
        ["CHOP"] = true,
    },
}
-- ============================================================
--  写法二：function（语法糖，自动转为 { fn = function }）
-- ============================================================
default_triggers = {
    events = {
        onhitother = function(inst, params, def)
            local target = params.target
            if target and target:IsValid() then
                SpawnPrefab("explode_small").Transform:SetPosition(target:GetPosition():Get())
            end
        end,
    },
}
-- ============================================================
--  写法三：table（可覆盖 fn / cost / cd / required_tags）
-- ============================================================
default_triggers = {
    events = {
        onhitother = {
            required_tags = { "blast_round" },
            cost = { res = "spark", amount = 1 },
            cd = 2,
            fn = function(inst, params, def)
                local target = params.target
                if target and target:IsValid() then
                    target.components.health:DoDelta(-30)
                end
                return true
            end,
        },
    },
}
```


## 完整示例

```lua
return {
    -- 纯客户端技能：打开轮盘
    open_wheel = {
        name = "打开技能轮盘",
        client_only = true,
        client_fn = function(inst)
            if inst.replica.nikki_skillwheel then
                inst.replica.nikki_skillwheel:OpenWheel()
            end
        end,
    },

    -- 双端协作技能：发射弹幕
    purify = {
        name = "净化",
        range = 15,
        cost = { res = "mana", amount = 10 },
        cd = 3,
        required_tags = { "can_cast_purify" },
        tags = { "is_casting" },
        on_add = function(inst, def)
            inst.ball_caster = SpawnPrefab("ball_caster")
            inst.ball_caster.entity:SetParent(inst.entity)
        end,
        on_remove = function(inst, def)
            if inst.ball_caster then
                inst.ball_caster:Remove()
                inst.ball_caster = nil
            end
        end,
        client_fn = function(inst, params, def)
            if inst.replica.rider and inst.replica.rider:IsRiding() then
                return false, "IS_RIDING"
            end
            return true
        end,
        fn = function(inst, params, def)
            local target = params.target
            if not target or not target:IsValid() then
                return false, "INVALID_TARGET"
            end
            inst.ball_caster.components.weapon:LaunchProjectile(inst, target)
            return true
        end,
    },

    -- 带默认触发器的技能：被攻击时释放
    frog_guard = {
        name = "蛙卫",
        fn = function(inst, params, def)
            local attacker = params.attacker
            if attacker then
                inst.components.combat:ShareTarget(attacker, 30, nil, 30)
            end
            return true
        end,
        default_triggers = {
            events = {
                attacked = true,
            },
        },
    },

    -- 带消耗和冷却的召唤技能
    summon_spider = {
        name = "召唤蜘蛛",
        cost = { res = "spark", amount = 10 },
        cd = 5,
        required_tags = { "can_summon" },
        fn = function(inst, params, def)
            local pos = params and params.pos or inst:GetPosition()
            local minion = SpawnPrefab("spider")
            minion.Transform:SetPosition(pos:Get())
            return true
        end,
    },
}
```