-- scripts/components/nikki_skill_trigger_replica.lua
local log = require("utils/log")
local ResolverRegistry = require("nikki_resolver_registry")

local NikkiSkillTriggerReplica = Class(function(self, inst)
    self.inst = inst
    self._range_target = net_entity(inst.GUID, "nikki_range_target", "nikki_range_target_dirty")
end)

-- 【核心】客户端统一按键转发入口
function NikkiSkillTriggerReplica:CastKey(key_code)
    -- 1. 通过注册表安全拉取当前 prefab 的解析器（完美解决时差与注入问题）
    local resolvers = ResolverRegistry.Get(self.inst.prefab)
    if not resolvers or not resolvers.state or not resolvers.skill then
        return false
    end

    -- 2. 获取当前形态 (从 nikki_state_replica 读取)
    local current_state = "default"
    if self.inst.replica.nikki_state then
        current_state = self.inst.replica.nikki_state:GetState() or "default"
    end

    -- 3. 直接向 StateResolver 查询按键映射
    local skill_id = resolvers.state:GetSkillForKey(current_state, key_code)
    if not skill_id then
        return false
    end

    -- 4. 向 SkillResolver 查询技能定义，执行客机预测
    local skill_def = resolvers.skill:GetSkillDef(skill_id)
    if skill_def and skill_def.on_client_cast then
        if not skill_def.on_client_cast(self.inst, nil, skill_def) then
            return false
        end
    end

    -- 5. 校验通过，向服务端发送名为 "CastKey" 的统一按键 RPC
    SendModRPCToServer(GetModRPC("NikkiFramework", "CastKey"), key_code)
    return true
end

function NikkiSkillTriggerReplica:CastSkill(id, params)
    if self.inst.components.nikki_skill then
        self.inst.components.nikki_skill:CastSkill(id, params)
    else
        local target = nil
        local has_pos = false
        local px, pz = 0, 0
        if params and type(params) == "table" then
            target = params.target
            if params.pos then
                has_pos = true
                px = params.pos.x
                pz = params.pos.z
            end
        end
        SendModRPCToServer(GetModRPC("NikkiFramework", "CastSkill"), id, target, has_pos, px, pz)
    end
end

function NikkiSkillTriggerReplica:SetRangeTarget(target)
    self._range_target:set(target)
end

function NikkiSkillTriggerReplica:GetRangeTarget()
    return self._range_target:value()
end

return NikkiSkillTriggerReplica