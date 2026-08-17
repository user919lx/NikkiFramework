-- scripts/resolvers/trigger_resolver.lua
local BaseResolver = require("resolvers/base_resolver")

-- ============================================================
-- TriggerResolver：存储技能 ID → 该技能绑定的 trigger 列表
-- 格式：defs[skill_id] = { events = {"attacked"}, actions = {"CHOP"} }
-- 查询接口：GetTriggers(skill_id) → { events = {...}, actions = {...} }
-- 数据在编译时通过 AddDefs 一次性注入，运行时只读
-- ============================================================
local TriggerResolver = Class(BaseResolver, function(self, defs)
    self._resolver_type = "trigger"
    BaseResolver._ctor(self, defs)
end)

function TriggerResolver:GetTriggers(skill_id)
    return self.defs[skill_id] or {}
end

return TriggerResolver