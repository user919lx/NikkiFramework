local LEVELS = {
    DEBUG = 1,
    INFO  = 2,
    WARN  = 3,
    ERROR = 4,
    FATAL = 5,
}
local LOG_THRESHOLD = LEVELS.INFO
local log = {}
local function _log_message(level_name, level_value, ...)
    if level_value < LOG_THRESHOLD then
        return
    end

    local n = select("#", ...) -- 获取参数个数（包括 nil）
    local message

    if n == 0 then
        message = ""
    else
        -- 将参数安全地转换为字符串
        local parts = {}
        for i = 1, n do
            local v = select(i, ...)
            parts[i] = v == nil and "nil" or tostring(v)
        end
        -- 检查第一个参数是否是格式字符串
        local first_arg = parts[1]
        if type(first_arg) == "string" and first_arg:find("%%") then
            -- 提取格式字符串和原始参数
            local format_str = table.remove(parts, 1)
            -- 获取原始参数（保持数值类型）
            local raw_args = {}
            for i = 1, n - 1 do
                raw_args[i] = select(i + 1, ...)
            end
            -- 尝试格式化
            local ok, result = pcall(string.format, format_str, unpack(raw_args, 1, n - 1))
            if ok then
                message = result
            else
                -- 格式化失败，回退到简单连接
                table.insert(parts, 1, format_str)
                message = table.concat(parts, " ")
            end
        else
            -- 简单连接
            message = table.concat(parts, " ")
        end
    end
    local timestamp = os.time()
    local formatted_time = os.date("%Y-%m-%d %H:%M:%S", timestamp)
    local output = string.format("[%s] %s [NikkiFramework] %s", formatted_time, level_name, message)
    print(output)
end


for name, value in pairs(LEVELS) do
    log[string.lower(name)] = function(...)
        _log_message(name, value, ...)
    end
end
function log.set_level(level_name)
    local value = LEVELS[string.upper(level_name)]
    if value then
        LOG_THRESHOLD = value
        log.warn("Log level set to: " .. level_name)
    else
        log.error("Invalid log level specified:", level_name)
    end
end

return log
