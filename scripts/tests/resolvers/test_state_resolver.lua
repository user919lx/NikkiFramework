-- scripts/tests/resolvers/test_state_resolver.lua
local TestUtils = require("tests/test_utils")
local StateResolver = require("resolvers/state_resolver")

return function()
    local suite = TestUtils.CreateSuite("StateResolver (Deep)")

    -- A. 直接使用饥荒原生环境里已经存在的常量，绝不凭空污染 _G
    local real_key_z = KEY_Z
    local real_key_x = KEY_X

    -- B. 初始化 Resolver，触发构造函数的 key 转换逻辑
    local resolver = StateResolver({
        ["state_battle"] = {
            badges = { "atk_up" },
            wheel = { "skill_1", "skill_2" },
            compiled_triggers = {
                keys = {
                    ["KEY_Z"] = { skill_3 = true },      -- 字符串按键
                    [real_key_x] = { skill_4 = true },   -- 原生数字按键
                    ["UNKNOWN_KEY"] = { skill_5 = true } -- 不存在的按键
                }
            }
        }
    })

    -- C. 测试构造转换结果
    local keys_dict = resolver:GetStateDef("state_battle").compiled_triggers.keys
    suite:assert(keys_dict[real_key_z] ~= nil, "构造器成功将字符串 'KEY_Z' 转换为全局数字常量")
    suite:assert(keys_dict[real_key_x] ~= nil, "原有的数字按键保持不变")
    suite:assert(keys_dict["UNKNOWN_KEY"] ~= nil, "无法找到匹配宏的字符串，原样保留作为防呆设计")

    -- D. 测试便捷提取 API
    local badges = resolver:GetBadges("state_battle")
    suite:assert(badges[1] == "atk_up", "GetBadges 提取正常")


    local z_skills = resolver:GetSkillsForKey("state_battle", real_key_z)
    suite:assert(z_skills.skill_3 == true, "GetSkillsForKey 提取数字按键正常")

    suite:assert(resolver:GetSkillsForKey("non_exist_state", real_key_z) == nil, "获取不存在的形态安全拦截")

    suite:Cleanup()
end