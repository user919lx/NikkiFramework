-- scripts/components/nikki_skill_replica.lua
local NikkiSkillReplica = Class(function(self, inst)
    self.inst = inst
    
    -- 定义网络变量同步最大射程
    -- 考虑到射程可能是小数，使用 net_float。数值改变时抛出 nikki_maxrangedirty 事件
    self._max_range = net_float(inst.GUID, "skill._max_range", "skill_maxrangedirty")
    self._max_range:set(0)
    if not TheWorld.ismastersim then
        inst:ListenForEvent("skill_maxrangedirty", function()
            inst:PushEvent("skill_max_range_dirty", {
                max_range = self:GetMaxRange(),
            })
        end)
    end
end)

-- 服务端调用：写入最大射程
function NikkiSkillReplica:SetMaxRange(range)
    self._max_range:set(range or 0)
end

-- 客户端/UI 调用：获取当前最大射程
function NikkiSkillReplica:GetMaxRange()
    if self.inst.components.nikki_skill ~= nil then
        -- 服务端直接读取组件真实值
        return self.inst.components.nikki_skill.max_range
    else
        -- 客机端读取网络同步值
        return self._max_range:value()
    end
end

return NikkiSkillReplica