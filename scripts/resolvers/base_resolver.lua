-- scripts/resolvers/base_resolver.lua
local log = require("utils/log")

local BaseResolver = Class(function(self, defs)
    self.defs = {}
    if defs then 
        self:AddDefs(defs) 
    end
end)

-- 增量合并接口：多 Mod 调用此接口将自己的定义汇入全局池
function BaseResolver:AddDefs(new_defs)
    if not new_defs or type(new_defs) ~= "table" then return end
    for id, def in pairs(new_defs) do
        if self.defs[id] ~= nil then
            log.warn("[NikkiFramework] Conflict: ID '%s' already registered! Skipping later definition.", tostring(id))
        else
            self.defs[id] = def
            self:OnDefAdded(id, def) -- 触发子类的钩子进行局部预编译
        end
    end
end

-- 子类重写此钩子，在局部挂载时执行各自的解析逻辑
function BaseResolver:OnDefAdded(id, def)
end

-- 基础查表接口 O(1)
function BaseResolver:GetDef(id)
    return self.defs[id]
end

-- 获取所有数据字典
function BaseResolver:GetAllDefs()
    return self.defs
end

-- 获取所有 ID 列表
function BaseResolver:GetAllIds()
    local ids = {}
    for id, _ in pairs(self.defs) do
        table.insert(ids, id)
    end
    return ids
end

return BaseResolver