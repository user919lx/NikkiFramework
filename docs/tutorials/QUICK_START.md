# 快速入门

入门教程旨在让你快速掌握配置信息的写法，你可以直接贴给AI让它帮你生成内容。

> 适用读者：已有饥荒 Mod 开发基础，并希望快速接入本框架的 Modder。

---

## 1. 声明依赖

---

在你的`modinfo.lua` 中添加以下内容。

```lua
mod_dependencies = {
    {
        workshop = "workshop-3781535039",
    },
}
```

注意：**如果Mod设置了优先级，不要超过9999**,否则本Mod会在框架Mod之前加载，导致报错。

## 2. 加载配置

在 `modmain.lua` 中，添加以下代码：

```lua
-- 加载框架管理器
local NikkiFrameworkManager = require("nikki_framework_manager")
-- 加载你自己的配置文件（接下来会创建）
local my_config = require("defs/test_config")
-- 初始化框架
NikkiFrameworkManager.Init(my_config, env)
```

> 这里的 `env` 是 `modmain` 的内置环境变量，直接传入就行，不需要额外设置

---

## 3. 创建配置文件

在 `scripts/defs/` 目录下新建 `test_config.lua`

```lua
return {
    -- ============================================================
    -- 1. 自定义资源与属性（本例用不到，留空）
    -- ============================================================
    custom_resources = {},
    custom_modifiers = {},

    -- ============================================================
    -- 2. 定义文件路径（告诉框架去哪里找技能、效果、形态的定义）
    -- ============================================================
    defs = {
        effect = "defs/test_effect_defs",   -- 效果定义文件
        skill  = "defs/test_skill_defs",    -- 技能定义文件
        state = {
            file   = "defs/test_state_defs", -- 形态定义文件
            basic  = "basic",               -- 基础形态名（所有形态都会继承的模板形态）
            default = "default",            -- 默认形态名（实体生成时的初始形态）
        },
    },
    -- ============================================================
    -- 3. 装配目标（告诉框架把组件挂到哪些实体上）
    -- ============================================================
    apply_to = {
        -- 玩家级别：挂载全套组件（技能、效果、形态、轮盘）
        player = {
            prefabs = { "wilson" }, -- 此处换成你自己的角色 prefab 名
            -- 也可以使用 tag 方式：tag = "player"，表示所有玩家
        },
        -- 技能级别：只挂载技能组件（没有轮盘），一般用于非玩家角色
        -- skill = { prefabs = { "deerclops" } },
        -- 效果级别：只挂载效果组件，用于任何需要接收 buff/debuff 的实体
        effect = {
            tag = "_combat", -- 所有具有战斗标签的实体
        },
    },
}
```

---

## 4. 定义效果（Effect）

---

效果指的是持续存在的状态，比如修改人物属性，持续掉血或回复精神等

创建 `scripts/defs/test_effect_defs.lua`

```lua
return {
    -- 永久效果，仅能通过代码移除
    brisk = {
        stack = { mode = "ignore" }, -- 重复施加时忽略（不叠加）
        mods = {
            spd = 1.2,               -- 移动速度 x 1.2
        },
        tags = { "fast" },
    },
    -- 限时效果，持续时间结束后自动移除
    brisk_buff = {
        stack = { mode = "ignore" },
        mods = {
            spd = 2,
        },
        drain = {     -- 持续消耗资源
            res = "hunger",
            rate = 1, -- 消耗速率:  /秒
        },
        duration = 5, -- 持续 5 秒
        -- 施加效果时的额外处理，这里加了一个泛光效果
        on_apply = function(inst, def, context)
            inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
        end,
        -- 移除效果时的额外处理，这里清除了泛光效果
        on_remove = function(inst, def, context)
            inst.AnimState:ClearBloomEffectHandle()
        end,
    },
}
```
`brisk`在被施加到目标身上后，目标移速x120%，添加`fast` 标签。这个效果会永久生效，除非手动移除。
`brisk_buff`在被施加到目标身上后，目标移速x200%，同时，每秒消耗1饱食度。持续5秒之后，效果会自动移除。

各项参数说明
- `mods` 属性修改。内置有`atk`（攻击倍率）、`spd`(速度倍率)等，也支持自定义属性拓展。
- `drain`/`regen` 消耗/回复资源，`res`表示资源id，内置有`hunger`,`sanity`,`health`，同样支持自定义。`rate`表示每秒消耗速率
- `duration` 持续时间（秒），不填则永久生效
- `stack` 重复施加效果时的处理, `ignore`=忽略，其他取值效果参数见参考手册

---

## 5. 定义技能（Skill）

技能指瞬间触发的功能，比如给自身施加一个效果，或者在砍树时多砍几下，或者让目标扣血等等，和效果的区别在于是触发瞬间执行的。


创建 `scripts/defs/test_skill_defs.lua`

```lua
local NEW_STATE_MAP = {
    ["default"] = "state_willow",
    ["state_willow"] = "state_wes",
    ["state_wes"] = "default",
}
-- 涉及的组件都是框架内的组件，请放心使用
return {
    fast_run = {
        cost = { res = "sanity", amount = 5 }, -- 执行技能时的消耗
        cd = 10, -- 冷却时间（秒）
        fn = function(inst, params, def)
            -- 调用nikki_effect组件，给自己施加 "brisk" 效果
            if inst.components.nikki_effect then
                inst.components.nikki_effect:Apply("brisk_buff")
            end
        end,
    },
    -- 切换形态
    state_switch = {
        fn = function(inst, params, def)
            local current_state = inst.components.nikki_state:GetState()
            local new_state = NEW_STATE_MAP[current_state] or "default"
            inst.components.nikki_state:SetState(new_state)
            return true
        end,
    },
}
```

这样就定义了技能
-  `fast_run` 触发时，给自己施加`brisk_buff`效果
-  `state_switch` 触发时，切换到下一个形态

属性说明
- `cost` 资源消耗，和`effect`的`drain` 类似，但是这里是一次性消耗
- `cd` 冷却时间，技能冷却之前无法释放，不设置这个值的话就允许连续执行
- `fn` 技能执行效果，传入参数说明
  - `inst`=技能执行者自身
  - `params` 执行时的相关参数，与触发器有关，详情见参考手册
  - `def` 技能定义table自身，比如你可以在def中写一个`params` table，然后在`fn`中使用 `def.params`调用，从而方便地调整技能参数


---

## 6. 定义形态（State）

---

形态是Effect和Skill的集合，你可以用这个来定义一组不同的玩法

创建 `scripts/defs/test_state_defs.lua`

```lua
return {
    -- 基础形态
    -- 所有形态都会继承这里的effects、skills和triggers
    -- 继承是与子state的对应table是合并，而不是覆盖
    basic = {
        skills = { "state_switch" },
        triggers = {
            keys = {
                ["KEY_Z"] = "state_switch", --  按 Z 触发形态转换
            },
        },
    },
    -- 默认形态 角色出生时的形态
    default = {
        skills = { "fast_run" }, -- 可用技能集
        triggers = { -- 触发技能方法
            keys = {
                ["KEY_X"] = "fast_run", -- 按 X 触发加速
            },
            events = {
                -- 攻击命中时触发
                ["onhitother"] = {
                    ["fast_run"] = true,
                },
            },
            actions = {
                -- 砍树时触发
                ["CHOP"] = {
                    ["fast_run"] = true,
                },
            },
        },
    },
    state_willow = {
        -- 改变外观
        visuals = { build = "willow" },
        effects = { "brisk" }, -- 永久效果集
    },
    state_wes = {
        visuals = { build = "wes" },
    },
}
```

-  `default` 形态下，人物外表是原本的样子，可以通过按下X，攻击敌人或者看树来获得一个大幅度加速效果
-  `state_willow` 形态下，人物外表是薇洛的样子，获得一个永久的小幅度加速效果
-  `state_wes` 形态下，人物外表是维斯的样子，没有任何加成


参数说明
- `visuals` 外观表现，可以设置`build`和`bank`，不设置时，自动取prefab同名build
- `effects` 进入state时自动添加的effect集，会在退出state时清除
- `skills` 当前state可用的skill集，如果一个skill在basic和当前state的skills中都没有设置的话，就无法使用
- `triggers` 决定如何触发技能，支持`keys`(按键)，`events`(事件)和`actions`(动作)三种形式


---

## 7. 运行测试


1. 订阅框架Mod 3781535039
2. 启用你的Mod进入游戏（依赖Mod会自动同步启用）
3. 进入游戏，选**威尔逊**（或你在 apply_to.prefabs 中配置的角色）。
4. 验证效果：
   - 按 Z 键 → 威尔逊瞬间变成薇洛的外表，且移速永久小幅提升（这是 state_willow 形态生效了）。
   - 再按 Z 键 → 外表切换为维斯，移速加成消失。
   - 再按 Z 键 → 回到默认形态。
   - 按 X 键 → 威尔逊身上亮起泛光，移速明显加快并且饱食快速下降。5 秒后效果消失，移速恢复。
   - 随便找一个生物进行攻击，触发同X按键相同的效果
   - 砍树 → 触发同样的效果

如果以上都正常，你就已经掌握了框架的基本配置流程。
接下来，你就可以学习参考手册，配置自己真正的Mod设计内容了。

**如果在后续Mod开发中，想了解技能系统底部运转的详细信息，可以在框架Mod的设置中打开调试模式**

---

## 8. 进阶参考

- 理解框架
  - [设计哲学](../explanation/DESIGN_PHILOSOPHY.md)
- 学习实践
  - [案例介绍](../how-to/CASE_COLLECTION.md)
- 参考手册
  - [Effect 手册](../reference/EFFECT.md)
  - [Skill 手册](../reference/SKILL.md)
  - [State 手册](../reference/STATE.md)
  - [SkillWheel 手册](../reference/SKILLWHEEL.md)
