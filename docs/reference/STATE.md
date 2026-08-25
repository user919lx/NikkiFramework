# State 参考手册

State 定义文件是一个 Lua 文件，返回一个 table，其中每个 key 是一个 State ID，value 是该 State 的配置。

State 代表一组能力的集合——它负责统一打包该形态下的外观（Visuals）、资源徽章（Badges）、技能池（Skills）、标签（Tags）以及按键映射（Keys）。

## 字段概览

| 字段    | 类型     | 必填 | 说明                                              |
| :------ | :------- | :--- | :------------------------------------------------ |
| visuals | table    | 否   | 外观配置，用于切换贴图（Build）与骨骼动画（Bank） |
| badges  | string[] | 否   | 在 UI 上显示的资源徽章（填写自定义资源 ID）       |
| tags    | string[] | 否   | 进入该 State 时挂载的标签，退出时自动移除         |
| skills  | string[] | 否   | 当前 State 解锁可用的 Skill ID 列表               |
| keys    | table    | 否   | 当前形态的专属按键映射规则                        |

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

## keys (按键映射)

将控制台指令或物理按键与具体的 Skill ID 形成一对一绑定。
配置规则：
* 键名（Key）可以是官方的按键常量值（如 KEY_Z ）或字符串表示（如 "KEY_Z"）。
* 键值（Value）必须是单一的 Skill ID 字符串。

## 切换与移除行为

实体同一时刻只能处于一个 State 下。当调用 SetState 切换时，框架将严格执行“先卸载，后装配”的流程：

1. 卸载旧状态：
   * 将上一个 State 挂载的 skills 完整剔除。
   * 清除上一个 State 所附加的所有 tags。
   * 注销上一个 State 定义的所有 keys 按键绑定。
2. 装配新状态：
   * 刷新 visuals 指定的贴图与动画。
   * 批量注册当前 State 的 skills。
   * 添加当前 State 的 tags。
   * 写入新的 keys 绑定至实体的触发器组件。


## 完整示例

```lua
-- ============================================================
-- STATE 配置示例代码
-- ============================================================
return {
    -- 1. 默认形态 (动态计算 build)
    default = {
        visuals = { 
            build = function(inst)
                return inst.prefab == "wilson" and "willow" or "default"
            end,
            bank = "wilson" 
        },
    },

    -- 2. 跳跃形态 (绑定了按键)
    jump = {
        visuals = { build = "wilson_jump" },
        tags = { "can_jump" },
        skills = { "bubbly_voyage", "jump" },
        keys = {
            -- 使用字符串键名绑定
            ["KEY_C"] = "jump",
        },
    },

    -- 3. 攻击形态 (绑定全局常量按键)
    attack = {
        visuals = { build = "wilson_attack" },
        badges = { "mana" },
        tags = { "is_attacker" },
        skills = { "wind_of_purity", "purify" },
        keys = {
            -- 使用常量绑定
            [KEY_C] = "purify",
        },
    },
}
```