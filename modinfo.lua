name = "Nikki Framework (API)"
description = "核心技能与召唤框架，提供基础组件与开放 API。"
author = "YourName"
version = "1.0.0"
forumthread = ""
api_version = 10
dst_compatible = true

all_clients_require_mod = true

configuration_options = {
    {
        name = "debug_mode",
        label = "开发者调试模式",
        hover = "开启后将输出大量底层 Debug 日志，普通玩家请勿开启。",
        options = {
            {description = "开启 (Debug)", data = true},
            {description = "关闭 (Info)", data = false},
        },
        default = false, -- 正式发布时，默认肯定是关闭的
    },
}