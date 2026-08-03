-- scripts/nikki_resolver_registry.lua
local registry = {}

local ResolverRegistry = {}

-- 只能由 Manager 调用的安全注册接口
function ResolverRegistry.Register(prefab_name, resolvers)
    if not prefab_name or not resolvers then return end
    registry[prefab_name] = resolvers
end

-- 供 Replica 调用的安全获取接口
function ResolverRegistry.Get(prefab_name)
    return registry[prefab_name]
end

return ResolverRegistry