local BaseResolver = Class(function(self, defs)
    -- defs 是由 Manager 在初始化时传递进来的、经过彻底编译合并的纯净数据表
    self.defs = defs or {}
end)


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