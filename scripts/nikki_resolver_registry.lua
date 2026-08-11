-- scripts/nikki_resolver_registry.lua
local registry = {}

local ResolverRegistry = {}

-- 统一的获取接口 (按类别获取对应的 Resolver)
function ResolverRegistry.Get(key)
    return registry[key]
end

-- 统一的注册/初始化接口 (若不存在则注册，实现先到先得或安全懒加载)
function ResolverRegistry.Register(key, resolver)
    if not key or not resolver then return end
    registry[key] = registry[key] or resolver
end

return ResolverRegistry
