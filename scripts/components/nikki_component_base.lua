local NikkiComponentBase = Class(function(self, inst)
    self.inst = inst
    self.resolver = nil
end)

-- 统一的依赖注入入口，由 FrameworkManager 在装配时调用
function NikkiComponentBase:SetResolver(resolver)
    self.resolver = resolver
end

-- 获取 resolver（供内部子类使用，确保安全）
function NikkiComponentBase:GetResolver()
    return self.resolver
end

return NikkiComponentBase