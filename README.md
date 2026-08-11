# Nikki Framework

Nikki Framework 是一个面向《饥荒联机版》的技能底层框架。它已经把技能系统中常见的公共逻辑抽象好了：状态管理、触发器分发、资源消耗、能力切换与生命周期控制等，都由框架统一处理。这样，Mod 开发者可以直接基于这套现成结构去实现自己的角色、技能与玩法，而不需要再从零搭一套底层能力系统。

它的核心思路是把能力拆成三层：

- Effect：负责持续状态、数值与标签
- Skill：负责事件触发、瞬时结算与动作执行
- State：负责把一组能力按形态、流派或模式组织起来

这样可以让复杂技能体系更清晰，也更容易扩展和复用。

## 你可以用它做什么

- 快速搭建复杂角色的技能体系
- 让多形态、多流派的能力切换更容易管理
- 把“玩法内容”与“底层基础设施”分离开，减少重复代码
- 让后续新增技能、改造机制时更稳、更快

## 适合的项目

- 需要完整、可扩展技能系统的角色 Mod
- 已经有明确玩法设计，但希望直接站在一套成熟框架上开发的团队或开发者
- 希望把技能逻辑做成可配置、可扩展、便于长期维护的项目，甚至让策划也能通过配置表快速管理技能

## 示例 Mod

可以参考这个示范项目：
https://github.com/user919lx/Samansha

> 这不是一个现成技能包，而是一个可供参考、可继续扩展的框架示范。

---

# Nikki Framework (English)

Nikki Framework is a foundational skill framework for Don't Starve Together. It already abstracts the common infrastructure of a skill system, including state management, trigger routing, resource consumption, capability switching, and lifecycle handling. This allows Mod developers to build their own characters, abilities, and gameplay directly on top of a ready-made structure, instead of developing the underlying framework from scratch.

Its core design separates abilities into three layers: Effect handles persistent states, modifiers, and tags; Skill handles event triggers, instant resolution, and action execution; State organizes a set of abilities by form, style, or mode. This makes complex skill systems easier to understand, extend, and reuse.

## What it can help with

- Quickly build complex character skill systems
- Manage multi-form or multi-style ability switching more cleanly
- Separate gameplay content from underlying infrastructure
- Reduce repetitive code and make future expansion easier

## Best fit for

- Character Mods that need a complete and extensible skill system
- Developers who already have clear gameplay ideas and want to build on a mature framework instead of creating the base system themselves
- Projects that aim to turn skill logic into a reusable and maintainable structure

## Example Mod

A good reference project is:
https://github.com/user919lx/Samansha

> This is not a finished skill pack, but a framework example that can be studied and extended.