-- scripts/components/nikki_state_replica.lua
local log = require("utils/log")
local ResolverRegistry = require("nikki_resolver_registry")

local NikkiStateReplica = Class(function(self, inst)
    self.inst = inst

    -- 定义网络变量
    self._state = net_string(inst.GUID, "nikki_state._state", "nikki_statedirty")
    self._state:set("default")

    -- 客机端监听网络同步事件，并对外统一抛出 "nikki_state_dirty"
    if not TheWorld.ismastersim then
        inst:ListenForEvent("nikki_statedirty", function()
            inst:PushEvent("nikki_state_dirty", {
                state = self:GetState(),
            })
            log.debug("[NikkiState Replica] Client received state dirty: state:%s", tostring(self:GetState()))
        end)
    end
end)

-- 服务端调用接口：同步数据到网络
function NikkiStateReplica:SetState(state)
    self._state:set(state or "default")
end

-- 客户端/UI 调用接口：获取当前同步的状态
function NikkiStateReplica:GetState()
    return self._state:value()
end

-- 【新增】：从 StateResolver 拉取当前形态绑定的徽章（Badges）列表
function NikkiStateReplica:GetStateBadges()
    local resolvers = ResolverRegistry.Get(self.inst.prefab)
    if resolvers and resolvers.state then
        local current_state = self:GetState() or "default"
        return resolvers.state:GetStateBadges(current_state)
    end
    return nil
end

return NikkiStateReplica