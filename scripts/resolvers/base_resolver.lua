-- scripts/resolvers/base_resolver.lua
local log = require("utils/log")

local BaseResolver = Class(function(self, defs)
    self.defs = {}
    self:AddDefs(defs)
end)

-- 增量合并接口：多 Mod 调用此接口将自己的定义汇入全局池
function BaseResolver:AddDefs(new_defs)
    if not new_defs or type(new_defs) ~= "table" then return end
    local def_copy = deepcopy(new_defs)
    for id, def in pairs(def_copy) do
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

function BaseResolver:GetDefCopy(id)
    local def = self.defs[id]
    if not def then
        return nil
    else
        return deepcopy(def)
    end
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

-- ============================================================
-- 文本显示接口
-- ============================================================

--- 获取本地化显示名称
--- 优先级：STRINGS > def.name > 默认值
--- @param id string 资源 ID
--- @return string 显示名称
function BaseResolver:GetDisplayName(id)
    local def = self:GetDef(id)
    if not def then
        return self:_GetDefaultName(id)
    end

    local resolver_type = self._resolver_type or "unknown"
    local str_table = STRINGS and STRINGS.NIKKI_FRAMEWORK
    local type_key = resolver_type:upper() .. "S"
    if str_table then
        local type_str_table = str_table[type_key]
        if type_str_table and type_str_table[id] and type_str_table[id].name then
            return type_str_table[id].name
        end
    end

    if def.name and def.name ~= "" then
        return def.name
    end

    return self:_GetDefaultName(id)
end

--- 获取默认名称（子类可重写）
--- @param id string 资源 ID
--- @return string 默认名称
function BaseResolver:_GetDefaultName(id)
    return string.format("Unnamed %s", id)
end


return BaseResolver