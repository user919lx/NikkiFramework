-- ============================================================================
--  Nikki Framework (API)
--  核心数值修改、效果管理、召唤物系统  —— 为 Mod 开发者打造的轻量级框架
-- ============================================================================

name = "暖暖框架 (Nikki Framework)"
version = "1.0.0"
local mod_desc = [[为《饥荒：联机版》Mod 开发者提供方便的技能高效的系统
通过本框架可用配置表的形式，快速添加持续效果，触发技能和状态组合
框架自身可帮助管理资源和属性变化，让你不再需要自己手动管理效果、技能、状态的生命周期和现场清理
让 Mod 开发更高效。适合有一定 Lua 基础的 Mod 制作者。
作者的Mod《永恒暖暖Nikki》正是基于本框架开发的，欢迎参考学习。
也可参考Mod《Samansha-暖暖框架示范》了解框架的全面用法。

本框架本身不包含任何游戏内容，仅供其他 Mod 调用。
在设置中打开调试模式，可输出更多底层运行信息
]]

description = "Version " .. version .. "\n\n" .. mod_desc
author = "LongFei_gamer" 
forumthread = ""

-- 基础兼容性
api_version = 10
dst_compatible = true
all_clients_require_mod = true

configuration_options = {
    {
        name = "debug_mode",
        label = "开发者调试模式",
        hover = "开启后将输出大量底层 Debug 日志，普通玩家请勿开启。",
        options = {
            {description = "开启", data = true},
            {description = "关闭", data = false},
        },
        default = false,
    },
}