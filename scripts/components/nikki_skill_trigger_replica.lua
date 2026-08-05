-- scripts/components/nikki_skill_trigger_replica.lua
local log = require("utils/log")

local NikkiSkillTriggerReplica = Class(function(self, inst)
    self.inst = inst
end)

function NikkiSkillTriggerReplica:CastKey(key_code)
    -- 1. 查表：当前形态下，这个按键绑定了什么技能？
    if not self.inst.replica.nikki_state then return false end
    local skills = self.inst.replica.nikki_state:GetSkillsForKey(key_code)
    if not skills then return false end
    log.debug("[NikkiSkillTrigger Replica] Found skills for key_code %s: %s", key_code, tostring(skills))
    -- 2. 路由转发：交管局的任务结束，把技能列表和按键上下文甩给 SkillReplica 去处理客机表现与发包
    if self.inst.replica.nikki_skill then
        self.inst.replica.nikki_skill:CastKey(key_code, skills)
    end
    return true
end

-- 兼容 UI 的主动释放请求 (依然无脑甩锅)
function NikkiSkillTriggerReplica:CastSkill(id, params)
    if self.inst.replica.nikki_skill then
        self.inst.replica.nikki_skill:CastSkill(id, params)
    end
end

return NikkiSkillTriggerReplica