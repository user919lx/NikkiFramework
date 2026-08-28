# Skill 参考手册

Skill 定义文件是一个 Lua 文件，返回一个 table，其中每个 key 是一个 Skill ID，value 是该 Skill 的配置。

Skill 代表瞬间影响的能力——按键触发、事件响应、资源消耗、冷却管理、动作交互及服务端执行等。

## 字段概览

| 字段             | 类型         | 必填 | 说明                                                          |
| :--------------- | :----------- | :--- | :------------------------------------------------------------ |
| name             | string       | 否   | 技能名称，用于 UI 显示                                        |
| priority         | string       | 否   | 优先级，多用途，决定各种排序                                  |
| client_only      | boolean      | 否   | true 时仅在客户端尝试执行，不通过 RPC 路由服务端              |
| fn               | function     | 否   | 核心执行函数，接收 inst, params, def，返回执行结果（boolean） |
| on_add           | function     | 否   | 技能挂载至实体时调用                                          |
| on_remove        | function     | 否   | 技能从实体卸载时调用                                          |
| range            | number       | 否   | 技能射程，用于 BufferedAction 的范围限制及 UI 范围指示        |
| cost             | table        | 否   | 释放消耗：{ res = "资源ID", amount = 数值 }                   |
| cd               | number       | 否   | 冷却时间（秒）                                                |
| required_tags    | string[]     | 否   | 释放所需标签，缺少任一则无法执行，也影响轮盘可用状态          |
| tags             | string[]     | 否   | 技能挂载时添加、卸载时清除的标签                              |
| effects          | string[]     | 否   | 技能挂载时连带施加的 Effect 列表，卸载时连带移除              |
| action           | table        | 否   | 动作交互配置                                                  |
| wheel            | table        | 否   | 技能轮盘 UI 配置|
| aoe              | table        | 否   | AOE技能相关配置|
| targeting        | table        | 否   | 瞄准器配置                                                    |
| toggle           | string/table | 否   | 开关型技能的语法糖，自动生成与该技能绑定的 Toggle Effect      |
| default_triggers | table        | 否   | 默认被动触发规则，支持 events 和 actions                      |

## 回调函数详解

### on_add / on_remove

技能生命周期回调，分别在技能被实体挂载和卸载时触发。

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

### fn (执行逻辑)

签名为：function(inst, params, def)

执行与路由流程：
技能通过主动施法或被动触发时，系统会进行鉴权（标签、冷却、消耗）。鉴权通过后：

1. 若 client_only 为 true 且处于客户端，直接执行 fn。
2. 若附带了 action 定义，系统会生成 BufferedAction，转交游戏原生动作队列执行。让技能在对应State中触发动作并执行fn
3. 如果是普通服务端技能，客户端会发送 RPC 到服务端，由服务端调用 fn 并最终扣除消耗与进入冷却。

**params 内容因触发方式而异：**

| 触发方式  | params 内容                              |
| :-------- | :--------------------------------------- |
| `keys`    | 无参数                                   |
| `events`  | EventCallback 的 `data` 参数（原样透传） |
| `actions` | 见下表                                   |

**actions 触发方式下的 params 字段：**

| 字段            | 类型    | 说明               |
| :-------------- | :------ | :----------------- |
| `act`           | table   | BufferAction 对象  |
| `origin_result` | any     | ACTION.fn 的返回值 |
| `target`        | entity  | 目标实体           |
| `pos`           | Vector3 | 目标位置           |
| `doer`          | entity  | 动作执行者         |
| `invobject`     | entity  | 动作携带的物品     |

> `act` 和 `origin_result` 固定存在；`target`、`pos`、`doer`、`invobject` 取决于 ACTION 的执行分类，不一定都有。

此外，当技能定义了 `aoe.selector` 时，`params` 会额外包含`targets`字段，表示所有被选中的目标实体列表。

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
```

## action (动作交互)

`action` 字段用于将技能包装为饥荒原生的动作（BufferedAction），以便角色在施法时能够进入特定的行为流（Stategraph）并播放对应的动画。

### 字段说明

| 字段       | 类型     | 必填 | 说明                                                                                                                       |
| :--------- | :------- | :--- | :------------------------------------------------------------------------------------------------------------------------- |
| `invoke`   | string   | 否   | 触发模式，可选值为 `"instant"`（瞬间触发，默认）、`"target"`（需要指向目标）、`"pos"`（需要指向地面位置）。                |
| `state`    | string   | 否   | 执行该动作时角色进入的 SG State（如 `"throw"`, `"castspell"`）。对于法术书 AOE 技能，施法确认时也会使用此 state 播放动画。 |
| `testfn`   | function | 否   | 动作合法性校验：`function(inst, target/pos, is_right_click)`。返回 `true` 时准许交互。                                     |
| `fallback` | table    | 否   | 备用目标获取逻辑：`{ target = function, pos = function }`。当未明确提供目标或位置时调用。                                  |

```lua
-- ============================================================
-- action 配置示例
-- ============================================================
return {
    heavy_strike = {
        name = "重击",
        range = 3,
        action = {
            invoke = "target",
            state = "attack", -- 借用原生的攻击动作态
            testfn = function(inst, target, is_right_click)
                -- 只有能够被攻击的目标才会显示交互提示
                return inst.replica.combat and inst.replica.combat:CanTarget(target)
            end,
            fallback = {
                target = function(inst, params, def)
                    -- 如果没有点中目标，尝试自动获取范围内的敌人
                    return FindEntity(inst, def.range, function(ent)
                        return inst.replica.combat:CanTarget(ent)
                    end)
                end
            }
        },
        fn = function(inst, params, def)
            -- 实际的伤害逻辑
            return true
        end
    }
}
```

## wheel (技能轮盘)

`wheel` 用于配置技能在轮盘 UI 上的表现。框架在解析时，会将 `image` 或 `anim` 子表中的参数展平，连同公共参数一起直接**透传给饥荒官方的轮盘 Widget**。

> **注意：** 框架通过判断 `wheel` 表中是否存在 `image` 还是 `anim` 子表来决定渲染模式。不需要配置 `type` 字段。

### 公共参数

这些参数写在 `wheel` 表的最外层。

| 字段           | 类型     | 必填 | 说明                                                                                |
| :------------- | :------- | :--- | :---------------------------------------------------------------------------------- |
| `label`        | string   | 否   | 轮盘显示的标题文本（不填则回退使用技能顶层的 `name`）                               |
| `helptext`     | string   | 否   | 底部或悬停时的描述文本                                                              |
| `widget_scale` | number   | 否   | 整体控件缩放比例，默认 `0.6`                                                        |
| `checkenabled` | function | 否   | 自定义可用性校验：`function(owner)`，返回布尔值。框架会自动结合内置 CD 进行综合判定 |
| `onfocus`      | function | 否   | 悬停聚焦时的回调函数：`function(owner)`                                             |

### 静态图片模式 (image 子表)

通过配置 `wheel.image` 表开启此模式。内部参数将透传给官方 Image 控件。

| 字段         | 类型          | 必填   | 说明                                                            |
| :----------- | :------------ | :----- | :-------------------------------------------------------------- |
| `atlas`      | string        | **是** | 纹理图集 XML 路径                                               |
| `normal`     | string        | **是** | 默认状态贴图名称                                                |
| `hit_radius` | number        | 否     | 鼠标命中碰撞半径                                                |
| `focus`      | string        | 否     | 悬停高亮状态贴图名称                                            |
| `disabled`   | string        | 否     | 禁用置灰状态贴图名称                                            |
| `down`       | string        | 否     | 鼠标按下状态贴图名称                                            |
| `selected`   | string        | 否     | 选中状态贴图名称                                                |
| `scale`      | table/Vector3 | 否     | 传给内部 Image 控件的缩放比例（支持传入数组如 `{1.2, 1.2, 1}`） |
| `offset`     | table/Vector3 | 否     | 纹理渲染偏移量                                                  |

### 动态动画模式 (anim 子表)

通过配置 `wheel.anim` 表开启此模式。内部参数将透传给官方 UIAnim 控件。

| 字段            | 类型     | 必填   | 说明                                                                                                                 |
| :-------------- | :------- | :----- | :------------------------------------------------------------------------------------------------------------------- |
| `bank`          | string   | **是** | 动画 Bank 名称                                                                                                       |
| `build`         | string   | **是** | 动画 Build 名称                                                                                                      |
| `anims`         | table    | **是** | 各状态动画映射表，包含 `idle`, `focus`, `down`, `disabled`, `cooldown` 等键，值为 `{ anim = "动画名", loop = bool }` |
| `checkcooldown` | function | 否     | 冷却进度回调：`function(owner)`，需返回 `0~1` 之间的进度百分比                                                       |
| `cooldowncolor` | table    | 否     | CD 遮罩层颜色，传入 RGBA 数组（如 `{0.1, 0.1, 0.1, 0.75}`）                                                          |
| `clicksound`    | string   | 否     | 点击覆盖音效路径（如 `"dontstarve/HUD/click_spell"`）                                                                |

### 配置示例

```lua
-- ============================================================
-- wheel 配置示例 (利用官方参数透传)
-- ============================================================

return {
    -- 1. 静态图片模式示例
    fireball = {
        name = "火球术",
        cd = 5,
        wheel = {
            -- 公共透传参数
            label = "火球术 (消耗20点法力)",
            helptext = "发射一枚直线爆炸火球",
            widget_scale = 1.1,
            checkenabled = function(owner)
                return owner.components.combat:HasTarget()
            end,
            onfocus = function(owner)
                -- 悬停时的额外交互逻辑
            end,

            -- 静态图片专属透传参数
            image = {
                atlas = "images/hud/nikki_skills.xml",
                normal = "fireball.tex",
                focus = "fireball_focus.tex",
                disabled = "fireball_disabled.tex",
                down = "fireball_down.tex",
                hit_radius = 45,
                scale = { 1.2, 1.2, 1 },
                offset = { 0, 5, 0 }
            }
        }
    },

    -- 2. 动态动画模式示例
    ultimate_meteor = {
        name = "天陨狂岚",
        cd = 60,
        wheel = {
            -- 公共透传参数
            widget_scale = 1.25,

            -- 动态动画专属透传参数
            anim = {
                bank = "nikki_skill_icons",
                build = "nikki_skill_icons",
                clicksound = "dontstarve/HUD/click_spell",
                cooldowncolor = { 0.1, 0.1, 0.1, 0.75 },

                -- 各状态动画映射
                anims = {
                    idle     = { anim = "meteor_idle", loop = true },
                    focus    = { anim = "meteor_focus", loop = false },
                    down     = { anim = "meteor_pressed", loop = false },
                    disabled = { anim = "meteor_disabled", loop = false },
                    cooldown = { anim = "meteor_cooldown", loop = false },
                },

                -- 自定义轮盘 UI 的冷却遮罩计算
                checkcooldown = function(owner)
                    local skill_comp = owner.replica.nikki_skill or owner.components.nikki_skill
                    if skill_comp then
                        local remain = skill_comp:GetCooldown("ultimate_meteor")
                        if remain > 0 then
                            return remain / 60 -- 返回 0~1 的 CD 剩余百分比
                        end
                    end
                    return nil
                end,
            }
        }
    }
}
```

## aoe 与 targeting (范围与瞄准系统)

当技能需要像进入瞄准状态并选择位置施放时，使用这两个字段。
`aoe` 是高层的几何与逻辑声明，它会自动预编译出底层的空间搜索函数（`search_fn`）和基础指示器表现。而 `targeting` 是低层的覆写接口，用于深度定制原生 `aoetargeting` 组件。

### aoe (空间几何与预筛选)

| 字段       | 类型   | 说明                                                                              |
| :--------- | :----- | :-------------------------------------------------------------------------------- |
| `anchor`   | string | 交互锚定方式：`"point"`（点选）、`"self"`（以自身为中心）、`"dir"`（朝向/线形）。 |
| `radius`   | number | 圆形作用半径。若不填且锚点非 `dir`，则回退使用技能顶层的 `range`。                |
| `selector` | table  | 目标预筛选器，包含三个可选数组：`must_have`、`must_have_one_of`、`cant_have`。    |

> **机制说明**：只要配置了 `aoe` 字段，且 `selector` 有效（非 `dir` 模式），框架会在施法结算时自动通过 `search_fn` 采集空间范围内的合法实体，并注入到 `fn` 的 `params.targets` 中。

### targeting (底层瞄准器定制)

当 `aoe` 自动生成的指示器无法满足视觉需求时，使用 `targeting` 覆盖默认配置。
| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| `allow_water` | boolean | 是否允许在水面上施法定位。 |
| `deploy_radius` | number | 部署检测的防碰撞半径。 |
| `should_repeat_cast_fn` | function | 布尔函数，判断是否允许玩家按住鼠标连续施法。 |
| `target_fx` | string | 施法确认瞬间，在目标地点生成的特效 Prefab。 |
| `reticule` | table | 核心指示器结构覆盖。支持字段包含：`reticuleprefab`, `pingprefab`, `validcolour` (RGBA表), `invalidcolour`, `ease`, `smoothing`, `mousetargetfn`, `updatepositionfn` 等。 |

## toggle

开关型技能的语法糖字段。用于快速定义“施放一次开启，再施放一次关闭”的技能。
写法一：字符串。引用一个已注册的 Effect ID，其叠加模式必须为 toggle。
写法二：内联表。直接在 Skill 中编写完整的 Effect 配置。框架会自动覆盖其 stack.mode = "toggle"，并生成内部 Effect ID.

## default_triggers

定义技能的默认被动触发规则。支持绑定 `events` 和 `actions`。

触发条目的值支持三种写法：

- **`true`**：绑定该触发方式，执行时使用技能顶层配置（`fn`、`cost`、`cd`、`required_tags`）
- **`function`**： 作为该触发方式专用的 `fn`。框架自动转换为 `{ fn = function }`
- **`table`**：可包含 `fn`、`cost`、`cd`、`required_tags` 字段，控制该触发方式下的行为

**关于 table 中的配置继承：**

- 写了 `fn`：该触发方式完全独立，`cost`、`cd`、`required_tags` 全部用自己的值，不继承顶层（没写就是没有）
- 没写 `fn`：则`fn` 继承顶层，`cost`、`cd`、`required_tags` 优先用自己的值，没有则继承顶层

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
-- ============================================================
-- SKILL 配置示例代码
-- ============================================================
return {
    -- 1. 生命周期回调示例
    jump = {
        on_add = function(inst, def)
            if not inst.components.jumper then
                inst:AddComponent("jumper")
            end
        end,
        on_remove = function(inst, def)
            -- 清理逻辑
        end,
    },

    -- 2. fn 基础用法
    damage_skill = {
        fn = function(inst, params, def)
            local target = params.target
            if target and target:IsValid() then
                target.components.health:DoDelta(-10)
                return true
            end
            return false, "INVALID_TARGET"
        end,
    },

    -- 3. 带动作流转 (Action) 的技能
    throw_skill = {
        range = 15,
        action = {
            invoke = "target",
            state = "throw",
            testfn = function(inst, target, is_right_click) return true end
        },
        fn = function(inst, params, def)
            local target = params.target
            if not target then return false end
            inst.components.weapon:LaunchProjectile(inst, target)
            return true
        end,
    },

    -- 4. default_triggers 用法
    trigger_skill = {
        default_triggers = {
            events = {
                -- 写法一：直接触发
                attacked = true,

                -- 写法二：专用函数
                onhitother = function(inst, params, def)
                    -- 命中时执行额外逻辑
                end,

                -- 写法三：局部覆盖消耗与冷却的子定义
                killed = {
                    cost = { res = "spark", amount = 1 },
                    cd = 2,
                    fn = function(inst, params, def)
                        return true
                    end,
                }
            },
            actions = {
                ["CHOP"] = true,
            },
        }
    }
}
```
