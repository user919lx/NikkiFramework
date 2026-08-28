-- scripts/utils/upvalue_helper.lua
local UpvalueHelper = {}

-- 根据变量名获取函数的 Upvalue 值与索引
function UpvalueHelper.GetUpvalue(fn, name)
    local i = 1
    while true do
        local var_name, var_value = debug.getupvalue(fn, i)
        if not var_name then break end
        if var_name == name then
            return var_value, i
        end
        i = i + 1
    end
    return nil, nil
end

-- 根据变量名替换函数的 Upvalue
function UpvalueHelper.SetUpvalue(fn, name, new_value)
    local _, i = UpvalueHelper.GetUpvalue(fn, name)
    if i then
        debug.setupvalue(fn, i, new_value)
        return true
    end
    return false
end

return UpvalueHelper
