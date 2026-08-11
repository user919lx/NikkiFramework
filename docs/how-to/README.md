# How-To 示例代码

本目录包含框架各模块的完整配置示例，可直接复制使用或作为参考模板。

## 文件说明

| 文件 | 说明 |
| :--- | :--- |
| `my_config.lua` | 框架顶层配置，含自定义资源、修饰器注册、数据源路径、装配目标 |
| `my_effect_defs.lua` | Effect 定义：永久/限时效果、消耗/回复、生命周期回调 |
| `my_skill_defs.lua` | Skill 定义：消耗/冷却、双端执行、默认触发器、轮盘配置 |
| `my_state_defs.lua` | State 定义：形态切换、Effect/Skill 组合、触发器绑定 |
| `my_skillwheel_defs.lua` | 技能轮盘 UI 配置（独立拆分，与 Skill 定义解耦） |


## 使用方式

### 1. 复制文件到你的 Mod 目录

将 `*.lua` 文件放入 `scripts/defs/` 目录下，或按需修改文件名和路径。

### 2. 在 `modmain.lua` 中加载

引用 `nikki_framework_manager` 并传入 config 配置表与 `env` 环境变量完成初始化。
```lua
local NikkiFrameworkManager = require("nikki_framework_manager")
local my_config = require("defs/my_config")
NikkiFrameworkManager.Init(my_config, env)
```

### 3. 根据你的 Mod 调整以下内容

- `apply_to.prefabs`：替换为你的角色 prefab 名称
- `custom_resources`：按需注册自定义资源
- `custom_modifiers`：按需注册自定义属性修饰器


## 注意事项

- 所有 `defs` 中的 ID（Effect ID、Skill ID、State ID）必须全局唯一
- `wheel` 配置建议拆分到单独文件，便于维护
- `my_skill_defs.lua` 末尾通过 `pcall` 加载 `my_skillwheel_defs.lua`，缺少该文件不会报错
- 示例中的贴图路径（`atlas`、`normal`）和特效 prefab（`explosivehit`、`shadow_pillar_spell` 等）需替换为你自己的资源
