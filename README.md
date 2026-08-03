# Nikki Framework

Nikki Framework 是一个专为《饥荒联机版》(DST) 设计的底层技能框架。它接管了技能系统中繁琐的公共逻辑（如状态管理、触发器路由、生命周期），让 Mod 开发者能完全聚焦于具体的技能表现与玩法设计。

## 核心能力

*   **技能生命周期管理**：提供标准化接口处理技能的装配、激活、持续耗材计算与移除。
*   **统一触发器路由**：将按键输入、游戏动作（Actions）与底层事件（Events）统一映射到技能施放。
*   **动态状态切换**：支持基于形态或流派的“技能+触发器”套组（State）无缝切换。
*   **数据驱动架构**：通过独立的定义文件装配技能，实现配置与主体逻辑的彻底解耦。

## 框架边界（不做什么）

Nikki Framework 仅提供**基础设施**（底盘与控制系统）。它**不包含**任何具体的技能特效或战斗逻辑。具体的技能会产生什么效果、有怎样的视觉表现，完全由你的上层 Mod 定义。

## 适用场景

*   拥有独立、复杂技能体系的角色 Mod。
*   包含多形态、多流派切换的机制类 Mod。
*   希望在多个独立 Mod 之间复用同一套底层代码的系列项目。

## 项目结构概览

*   **`modmain.lua`**: 框架运行环境对接与基础能力注册。
*   **`nikki_framework_manager.lua`**: 实体总装配入口。
*   **`scripts/components/`**: 核心逻辑层，包含技能、触发器、状态与网络同步组件。
*   **`scripts/resolvers/`**: 数据解析层，负责将外部配置转化为框架可识别的参数。
*   **`scripts/prefabs/` & `scripts/utils/`**: 框架配套资源与通用辅助函数。

---

# Nikki Framework (English)

Nikki Framework is a foundational skill framework for Don't Starve Together (DST) modding. It handles the tedious plumbing of a skill system (state management, trigger routing, lifecycles) so modders can focus entirely on designing gameplay and visual effects.

## Core Features

*   **Lifecycle Management**: Standardized interfaces for mounting, activating, sustaining (resource draining), and removing skills.
*   **Unified Trigger Routing**: Seamlessly maps key inputs, in-game actions, and underlying events to skill execution.
*   **Dynamic State Switching**: Supports flawless transitions between different "skill + trigger" loadouts for multi-form or multi-stance characters.
*   **Data-Driven Architecture**: Separates configuration from core logic using external definition files.

## Framework Boundaries (What it DOES NOT do)

Nikki Framework provides **infrastructure only**. It does **not** include specific skill effects or combat logic. The actual abilities, visual effects, and gameplay consequences are entirely defined by your upper-layer mod.

## Best Fit For

*   Character mods with dedicated, complex skill trees.
*   Mechanic-heavy mods featuring multiple forms, stances, or loadouts.
*   Mod series that require a shared, reusable underlying codebase.

## Project Structure

*   **`modmain.lua`**: Game environment integration.
*   **`nikki_framework_manager.lua`**: Central assembly and mounting point for entities.
*   **`scripts/components/`**: Core controllers (skill, trigger, state, replication).
*   **`scripts/resolvers/`**: Definition parsers translating external data into framework logic.
*   **`scripts/prefabs/` & `scripts/utils/`**: Supporting prefabs and shared utility scripts.