-- scripts/components/nikki_skill.lua
local ResolverRegistry = require("nikki_resolver_registry")
local log = require("utils/log")

-- 私有懒加载：首次调用时向注册表查一次并缓存到 self._resolver，后续直接读缓存
local function GetResolver(self)
    if not self._resolver then
        self._resolver = ResolverRegistry.Get("skill")
    end
    return self._resolver
end

local function on_max_range(self, max_range)
    if self.inst.replica.nikki_skill then self.inst.replica.nikki_skill:SetMaxRange(max_range) end
    self.inst:PushEvent("skill_max_range_dirty", { max_range = max_range })
end

local NikkiSkill = Class(function(self, inst)
    self.inst = inst
    self.max_range = 0
    self._active_skills = {}
    self._resolver = nil -- 私有缓存

    -- 存储技能冷却的到期时间戳 [skill_id] = expire_time
    self._cooldowns = {}
end,
nil,
{
    max_range = on_max_range
})

function NikkiSkill:IsAdded(skill_id)
    for _, id in ipairs(self._active_skills) do if id == skill_id then return true end end
    return false
end

function NikkiSkill:_UpdateRangeRadius()
    local resolver = GetResolver(self)
    if not resolver then return end

    local max_range = 0
    for _, skill_id in ipairs(self._active_skills) do
        local range = resolver:GetSkillRange(skill_id)
        if range and type(range) == "number" and range > max_range then max_range = range end
    end
    if max_range ~= self.max_range then self.max_range = max_range end
end

function NikkiSkill:AddSkills(ids)
    local resolver = GetResolver(self)
    if not ids or not resolver then return end

    for _, id in ipairs(ids) do
        if not self:IsAdded(id) then
            resolver:OnSkillAdd(self.inst, id)
            table.insert(self._active_skills, id)
            log.debug("[NikkiSkill] Added skill '%s' to %s. Current skills: %s", tostring(id), tostring(self.inst),
                table.concat(self._active_skills, ", "))
        end
    end
    self:_UpdateRangeRadius()
end

function NikkiSkill:RemoveSkills(ids)
    local resolver = GetResolver(self)
    if not ids or not resolver then return end

    for _, id in ipairs(ids) do
        if self:IsAdded(id) then
            resolver:OnSkillRemove(self.inst, id)
            for i, existing_id in ipairs(self._active_skills) do
                if existing_id == id then
                    table.remove(self._active_skills, i)
                    log.debug("[NikkiSkill] Removed skill '%s' from %s. Current skills: %s", tostring(id), tostring(self.inst),
                        table.concat(self._active_skills, ", "))
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
    log.debug("[NikkiSkill] GetCooldown for skill '%s': remain=%.2f (expire_time=%.2f, current_time=%.2f)", skill_id,
        remain, expire_time, GetTime())
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

        -- 巧妙借用官方组件：下发隐形实体同步 UI
        if self.inst.components.spellbookcooldowns then
            self.inst.components.spellbookcooldowns:RestartSpellCooldown(skill_id, cd_time)
        end
    end
end

-- ========================================================
-- 核心修正：拦截防线与结算都由 Component 自己控制，保持单向调用
-- ========================================================
function NikkiSkill:ExecuteTrigger(skill_id, trigger_type, trigger_key, params)
    local resolver = GetResolver(self)
    if not resolver or not self:IsAdded(skill_id) then return false, "NOT_ADDED" end

    -- 1. Component 自己负责拦截处于冷却中的技能
    if self:IsOnCooldown(skill_id) then
        return false, "ON_COOLDOWN"
    end

    -- 2. 委托 Resolver 执行无状态的验资与业务逻辑
    local success, err = resolver:ExecuteServerTrigger(self.inst, skill_id, trigger_type, trigger_key, params)

    -- 3. 业务执行成功后，Component 自己查 CD 数值并开启计时
    if success then
        local cd = resolver:GetSkillCooldown(skill_id, trigger_type, trigger_key)
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
