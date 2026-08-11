# Nikki Framework 文档

这套文档按 Diátaxis 框架组织，让不同读者在不同场景下都能快速找到需要的内容。

## 文档结构

### 教程（Tutorials）
- [QUICK_START.md](tutorials/QUICK_START.md)：5 分钟上手的最小示例，先跑通整个链路。

### 解释说明（Explanation）
- [DESIGN_PHILOSOPHY.md](explanation/DESIGN_PHILOSOPHY.md)：Effect、Skill、State 为何拆分及各自职责。

### 操作指南（How-to）
- [示例代码](how-to/README.md)：各模块的完整配置示例，可直接复用或参考。

### 技术参考（Reference）
- [CONFIG.md](reference/CONFIG.md)：框架入口配置结构与字段
- [EFFECT.md](reference/EFFECT.md)：Effect 定义字段与执行方式
- [SKILL.md](reference/SKILL.md)：Skill 定义字段与触发方式
- [STATE.md](reference/STATE.md)：State 定义、继承与编排
- [SKILLWHEEL.md](reference/SKILLWHEEL.md)：技能轮盘 UI 配置

## 推荐阅读顺序

1. 新手先读 [QUICK_START](tutorials/QUICK_START.md) 跑通流程，再看 [DESIGN_PHILOSOPHY](explanation/DESIGN_PHILOSOPHY.md) 理解设计意图。
2. 开发时按需查阅 [技术参考](#技术参考reference) 各字段说明，或参考 [示例代码](how-to/README.md) 快速上手。