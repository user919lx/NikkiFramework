# Nikki Framework

> 使用前需要在创意工坊订阅本框架：
> https://steamcommunity.com/sharedfiles/filedetails/?id=3781535033

Nikki Framework 是一个面向《饥荒联机版》的技能底层框架。它已经把技能系统中常见的公共逻辑抽象好了：状态管理、触发器分发、资源消耗、能力切换与生命周期控制等，都由框架统一处理。这样，Mod 开发者可以直接基于这套现成结构去实现自己的角色、技能与玩法，而不需要再从零搭一套底层能力系统。

它的核心思路是把能力拆成三层：

- Effect：负责持续状态、数值与标签
- Skill：负责事件触发、瞬时结算与动作执行
- State：负责把一组能力按形态、流派或模式组织起来

这样可以让复杂技能体系更清晰，也更容易扩展和复用。

## 快速感受（1 分钟上手）

用框架注册一个新技能，只需要继承 `Nikki.Skill`，填写核心回调，其余状态管理、冷却、消耗检测都由框架自动处理：

```lua
fireball = {
    name = "火球术",
    -- 会动态显示技能的射程范围 玩家可自由开关
    range = 10,
    -- 技能的资源消耗
    cost = {
        res = "mana",
        amount = 10
    },
    -- 技能冷却
    cd = 10,
    -- 技能自定义参数
    custom = {
        damage = 68,
    },
    -- 用于控制动作触发的标签
    tags = { "can_cast_purify" },
    -- 添加技能时的处理，比如对火球发射器的初始化设置
    on_add = function(inst, def)
        inst.ball_caster = SpawnPrefab("ball_caster")
        inst.ball_caster:SetDamage(def.custom.damage)
    end,
    -- 技能移除时的处理，比如移除火球发射器
    on_remove = function(inst, def)
        inst.ball_caster:Remove()
    end,
    fn = function(inst, params, def)
        local target = params and params.target
        inst.ball_caster.components.weapon:LaunchProjectile(inst, target)
        return true
    end,
},
```

你只需关心技能释放时的"玩法行为"，框架帮你搞定所有底层杂务。

更完整的入门教程请查看：[tutorials/QUICK_START.md](docs/tutorials/QUICK_START.md)

## 你可以用它做什么

- 快速搭建复杂角色的技能体系
- 让多形态、多流派的能力切换更容易管理
- 把"玩法内容"与"底层基础设施"分离开，减少重复代码
- 让后续新增技能、改造机制时更稳、更快

## 适合的项目

- 需要完整、可扩展技能系统的角色 Mod
- 已经有明确玩法设计，但希望直接站在一套成熟框架上开发的团队或开发者
- 希望把技能逻辑做成可配置、可扩展、便于长期维护的项目，甚至让策划也能通过配置表快速管理技能

## 文档

- **教程 (tutorials/)**：从零开始的入门指南
- **操作指南 (how-to/)**：具体配置示例与操作步骤
- **参考手册 (reference/)**：各模块的 API 与配置详解
- **设计说明 (explanation/)**：框架的设计思路与哲学

## 示例 Mod

完整的可运行示例项目，参见 Samansha（[GitHub](https://github.com/user919lx/Samansha)）：


---

# Nikki Framework (English)

> Subscribe to this framework on the Steam Workshop before use:
> https://steamcommunity.com/sharedfiles/filedetails/?id=3781535033

Nikki Framework is a foundational skill framework for Don't Starve Together. It already abstracts the common infrastructure of a skill system, including state management, trigger routing, resource consumption, capability switching, and lifecycle handling. This allows Mod developers to build their own characters, abilities, and gameplay directly on top of a ready-made structure, instead of developing the underlying framework from scratch.

Its core design separates abilities into three layers: Effect handles persistent states, modifiers, and tags; Skill handles event triggers, instant resolution, and action execution; State organizes a set of abilities by form, style, or mode. This makes complex skill systems easier to understand, extend, and reuse.

## Quick Feel (1-Minute Preview)

To create a new skill with the framework, just inherit from `Nikki.Skill` and fill in the core callback. The framework handles the rest – state management, cooldown, resource checking – automatically:


```lua
fireball = {
    name = "火球术",
    range = 10,
    cost = {
        res = "mana",
        amount = 10
    },
    cd = 10,
    custom = {
        damage = 68,
    },
    tags = { "can_cast_purify" },
    on_add = function(inst, def)
        inst.ball_caster = SpawnPrefab("ball_caster")
        inst.ball_caster:SetDamage(def.custom.damage)
    end,
    on_remove = function(inst, def)
        inst.ball_caster:Remove()
    end,
    fn = function(inst, params, def)
        local target = params and params.target
        inst.ball_caster.components.weapon:LaunchProjectile(inst, target)
        return true
    end,
},
```

You only care about the gameplay logic; the framework takes care of all the boring infrastructure.

For a complete step-by-step guide, see: [tutorials/QUICK_START.md](tutorials/QUICK_START.md)

## What it can help with

- Quickly build complex character skill systems
- Manage multi-form or multi-style ability switching more cleanly
- Separate gameplay content from underlying infrastructure
- Reduce repetitive code and make future expansion easier

## Best fit for

- Character Mods that need a complete and extensible skill system
- Developers who already have clear gameplay ideas and want to build on a mature framework instead of creating the base system themselves
- Projects that aim to turn skill logic into a reusable and maintainable structure

## Documentation

- **Tutorials (tutorials/)**：Step-by-step guides from scratch
- **How-to (how-to/)**：Specific configuration examples and operations
- **Reference (reference/)**：Detailed API and configuration reference
- **Explanation (explanation/)**：Design philosophy and rationale

## Example Mod

A complete runnable example project, see Samansha ([GitHub](https://github.com/user919lx/Samansha)):
