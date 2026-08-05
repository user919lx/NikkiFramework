-- scripts/components/nikki_state_replica.lua
local log = require("utils/log")
local ResolverRegistry = require("nikki_resolver_registry")

local NikkiStateReplica = Class(function(self, inst)
    self.inst = inst
    self._state = net_string(inst.GUID, "nikki_state._state", "nikki_statedirty")
    self._state:set("default")

    if not TheWorld.ismastersim then
        inst:ListenForEvent("nikki_statedirty", function()
            inst:PushEvent("nikki_state_dirty", { state = self:GetState() })
        end)
    end
end)

function NikkiStateReplica:SetState(state)
    self._state:set(state or "default")
end

function NikkiStateReplica:GetState()
    return self._state:value()
end

function NikkiStateReplica:GetStateBadges()
    local resolvers = ResolverRegistry.Get(self.inst.prefab)
    if resolvers and resolvers.state then
        local current_state = self:GetState() or "default"
        return resolvers.state:GetStateBadges(current_state)
    end
    return nil
end

-- 【新增接口】：供外部（Trigger）查询当前形态的按键绑定
function NikkiStateReplica:GetSkillsForKey(key_code)
    local resolvers = ResolverRegistry.Get(self.inst.prefab)
    if resolvers and resolvers.state then
        local current_state = self:GetState() or "default"
        return resolvers.state:GetSkillsForKey(current_state, key_code)
    end
    return nil
end

return NikkiStateReplica