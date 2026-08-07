-- scripts/components/nikki_skill.lua
local NikkiComponentBase = require("components/nikki_component_base")
local log = require("utils/log")
local function on_max_range(self, max_range)
    if self.inst.replica.nikki_skill then self.inst.replica.nikki_skill:SetMaxRange(max_range) end
    self.inst:PushEvent("skill_max_range_dirty", { max_range = max_range })
end

local NikkiSkill = Class(NikkiComponentBase, function(self, inst)
    NikkiComponentBase._ctor(self, inst)
    self.max_range = 0
    self._active_skills = {}

    -- 存储技能冷却的到期时间戳 [skill_id] = expire_time
    self._cooldowns = {}
end, { max_range = on_max_range })

function NikkiSkill:IsAdded(skill_id)
    for _, id in ipairs(self._active_skills) do if id == skill_id then return true end end
    return false
end

function NikkiSkill:_UpdateRangeRadius()
    if not self.resolver then return end
    local max_range = 0
    for _, skill_id in ipairs(self._active_skills) do
        local range = self.resolver:GetSkillRange(skill_id)
        if range and type(range) == "number" and range > max_range then max_range = range end
    end
    if max_range ~= self.max_range then self.max_range = max_range end
end

function NikkiSkill:AddSkills(ids)
    if not ids or not self.resolver then return end
    for _, id in ipairs(ids) do
        if not self:IsAdded(id) then
            self.resolver:OnSkillAdd(self.inst, id)
            table.insert(self._active_skills, id)
        end
    end
    self:_UpdateRangeRadius()
end

function NikkiSkill:RemoveSkills(ids)
    if not ids or not self.resolver then return end
    for _, id in ipairs(ids) do
        if self:IsAdded(id) then
            self.resolver:OnSkillRemove(self.inst, id)
            for i, existing_id in ipairs(self._active_skills) do
                if existing_id == id then
                    table.remove(self._active_skills, i)
                    break
                end
            end
            -- 移除技能时清理冗余的 CD 数据
            self._cooldowns[id] = nil
        end
    end
    self:_UpdateRangeRadius()
end

function NikkiSkill:GetCooldown(skill_id)
    local expire_time = self._cooldowns[skill_id]
    if not expire_time then return 0 end

    local remain = expire_time - GetTime()
    log.debug("[NikkiSkill] GetCooldown for skill '%s': remain=%.2f (expire_time=%.2f, current_time=%.2f)", skill_id, remain, expire_time, GetTime())
    if remain <= 0 then
        self._cooldowns[skill_id] = nil
        return 0
    end
    return remain
end

function NikkiSkill:IsOnCooldown(skill_id)
    return self:GetCooldown(skill_id) > 0
end

function NikkiSkill:StartCooldown(skill_id, cd_time)
    if cd_time and cd_time > 0 then
        self._cooldowns[skill_id] = GetTime() + cd_time
    end
end

-- ========================================================
-- 核心修正：拦截防线与结算都由 Component 自己控制，保持单向调用
-- ========================================================
function NikkiSkill:ExecuteTrigger(skill_id, trigger_type, trigger_key, params)
    if not self.resolver or not self:IsAdded(skill_id) then return false, "NOT_ADDED" end

    -- 1. Component 自己负责拦截处于冷却中的技能
    if self:IsOnCooldown(skill_id) then
        return false, "ON_COOLDOWN"
    end

    -- 2. 委托 Resolver 执行无状态的验资与业务逻辑
    local success, err = self.resolver:ExecuteServerTrigger(self.inst, skill_id, trigger_type, trigger_key, params)

    -- 3. 业务执行成功后，Component 自己查 CD 数值并开启计时
    if success then
        local cd = self.resolver:GetSkillCooldown(skill_id, trigger_type, trigger_key)
        if cd and cd > 0 then
            self:StartCooldown(skill_id, cd)
        end
    end

    return success, err
end

function NikkiSkill:CastSkill(id, params)
    return self:ExecuteTrigger(id, "cast", "default", params)
end

return NikkiSkill
