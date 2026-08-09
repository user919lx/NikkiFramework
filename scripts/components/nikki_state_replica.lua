-- scripts/components/nikki_state_replica.lua
local log = require("utils/log")
local ResolverRegistry = require("nikki_resolver_registry")


local DEFAULT_STATE = "default"
local NikkiStateReplica = Class(function(self, inst)
    self.inst = inst
    self._state = net_string(inst.GUID, "nikki_state._state", "nikki_statedirty")
    self._state:set(DEFAULT_STATE)

    if not TheWorld.ismastersim then
        inst:ListenForEvent("nikki_statedirty", function()
            inst:PushEvent("nikki_state_dirty", { state = self:GetState() })
        end)
    end
end)

function NikkiStateReplica:SetState(state)
    self._state:set(state or DEFAULT_STATE)
end

function NikkiStateReplica:GetState()
    return self._state:value() or DEFAULT_STATE
end

function NikkiStateReplica:GetBadges()
    local resolver = ResolverRegistry.Get("state")
    if resolver then
        return resolver:GetBadges(self:GetState())
    end
    return nil
end

-- 【新增接口】：供外部查询当前形态拥有的全部技能 ID 列表
function NikkiStateReplica:GetSkills()
    local resolver = ResolverRegistry.Get("state")
    if resolver then
        return resolver:GetSkills(self:GetState())
    end
    return {}
end

-- 供外部（Trigger）查询当前形态的按键绑定
function NikkiStateReplica:GetSkillsForKey(key_code)
    local resolver = ResolverRegistry.Get("state")
    if resolver then
        return resolver:GetSkillsForKey(self:GetState(), key_code)
    end
    return nil
end

return NikkiStateReplica