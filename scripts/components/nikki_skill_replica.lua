local log = require("utils/log")
local NikkiSkill = Class(function(self, inst)
    self.inst = inst

    -- 网络同步：最大射程
    self._max_range = net_float(inst.GUID, "skill._max_range", "skill_maxrangedirty")
    self._max_range:set(0)

    -- 网络同步：已添加技能列表（全量同步，逗号分隔）
    self._active_skills_str = net_string(inst.GUID, "skill._active_skills_str", "skill_activeskillsdirty")
    self._active_skills_cache = {}

    self._resolver = nil

    if not TheWorld.ismastersim then
        -- 客户端监听最大射程变化
        inst:ListenForEvent("skill_maxrangedirty", function()
            inst:PushEvent("skill_max_range_dirty", { max_range = self:GetMaxRange() })
        end)

        -- 客户端监听技能列表变化，更新缓存
        inst:ListenForEvent("skill_activeskillsdirty", function()
            local str = self._active_skills_str:value()
            self._active_skills_cache = {}
            for id in string.gmatch(str or "", "[^,]+") do
                self._active_skills_cache[id] = true
            end
            log.debug("[NikkiSkill Replica] Updated active skills cache: %s", str)
        end)
    end
end)

-- ============================================================
-- 网络同步接口（服务端调用）
-- ============================================================
function NikkiSkill:SetMaxRange(range)
    self._max_range:set(range or 0)
end

function NikkiSkill:GetMaxRange()
    if self.inst.components.nikki_skill ~= nil then
        return self.inst.components.nikki_skill.max_range
    else
        return self._max_range:value()
    end
end

-- 服务端在技能列表变化时调用此方法，推送全量列表
function NikkiSkill:SyncActiveSkills()
    local comp = self.inst.components.nikki_skill
    if not comp then return end
    local str = table.concat(comp._active_skills, ",")
    self._active_skills_str:set(str)
    log.debug("[NikkiSkill Replica] Synced active skills: %s", str)
end

-- ============================================================
-- 查询接口
-- ============================================================
function NikkiSkill:GetSkillDef(id)
    if self._resolver then
        return self._resolver:GetDef(id)
    end
end

function NikkiSkill:GetSkillRange(id)
    if self._resolver then
        return self._resolver:GetSkillRange(id)
    end
end

function NikkiSkill:GetSkillName(id)
    if self._resolver then
        return self._resolver:GetDisplayName(id)
    end
end

-- 返回当前已添加的技能 ID 缓存表（客户端可用）
function NikkiSkill:GetActiveSkills()
    return self._active_skills_cache
end

-- 检查某个技能是否已添加
function NikkiSkill:IsActive(skill_id)
    return self._active_skills_cache[skill_id] == true
end

-- ============================================================
-- 构造 BufferedAction
-- ============================================================
function NikkiSkill:BuildBufferedAction(target, pos, skill_id, with_cb)
    local def = self:GetSkillDef(skill_id)
    if not def then
        return nil
    end
    local action_def = def.action
    if not action_def then
        return nil
    end
    local act = BufferedAction(
        self.inst,
        target,
        ACTIONS.NIKKI_SKILL,
        nil,
        pos,
        nil,
        def.range or 0
    )
    act._skill_id = skill_id
    act._skill_state = action_def.state or "doshortaction"
    act._display_name = self:GetSkillName(skill_id) or skill_id
    -- 若需要回调，则附加预览/非预览回调
    if with_cb then
        pos = pos or {}
        local x = pos.x or nil
        local z = pos.z or nil
        local callback = function()
            SendModRPCToServer(GetModRPC("NikkiFramework", "TryExecuteSkill"),
                skill_id,
                target,
                x,
                z
            )
        end
        if self.inst.components.locomotor ~= nil then
            act.preview_cb = callback
        else
            act.non_preview_cb = callback
        end
    end
    return act
end

-- ============================================================
-- 公共接口：根据鼠标上下文获取最合适的技能动作
-- ============================================================
function NikkiSkill:GetAvailableSkillAction(target, pos, right)
    if not self.inst or not self.inst:IsValid() then
        return nil
    end

    local active_skills = self:GetActiveSkills()
    if not active_skills or next(active_skills) == nil then
        return nil
    end
    local candidates = {}
    for skill_id, _ in pairs(active_skills) do
        local def = self:GetSkillDef(skill_id)
        if def and def.action then
            local action_def = def.action
            local invoke = action_def.invoke or "instant"
            if invoke ~= "instant" and action_def.testfn then
                local ok = false
                if invoke == "target" then
                    ok = action_def.testfn(self.inst, target, right)
                elseif invoke == "pos" then
                    ok = action_def.testfn(self.inst, pos, right)
                end
                if ok == true then
                    table.insert(candidates, {
                        skill_id = skill_id,
                        priority = action_def.priority or 0,
                    })
                end
            end
        end
    end
    if #candidates == 0 then
        return nil
    end
    -- 按优先级降序排序（参考 SortActionList）
    table.sort(candidates, function(a, b)
        return a.priority > b.priority
    end)
    -- 取第一个
    local best = candidates[1]
    return self:BuildBufferedAction(target, pos, best.skill_id)
end

-- ============================================================
-- 原有方法：TryExecute（按键触发）
-- ============================================================
function NikkiSkill:TryExecute(skill_id, params)
    if self.inst.components.nikki_skill then
        return self.inst.components.nikki_skill:TryExecute(skill_id, params)
    end

    local def = self:GetSkillDef(skill_id)
    if not def then
        return false, "SKILL_DEF_NOT_FOUND"
    end

    local action_def = def.action
    if not action_def then
        SendModRPCToServer(GetModRPC("NikkiFramework", "TryExecuteSkill"), skill_id)
        return true
    end

    local invoke = action_def.invoke or "instant"
    local target = params.target
    local pos = nil

    -- 补全参数（fallback）
    if invoke == "target" then
        if not target and action_def.fallback and action_def.fallback.target then
            target = action_def.fallback.target(self.inst, params, def)
        end
        if not target or not target:IsValid() then
            return false, "MISSING_OR_INVALID_TARGET"
        end
    elseif invoke == "pos" then
        if not pos and action_def.fallback and action_def.fallback.pos then
            pos = action_def.fallback.pos(self.inst, params, def)
        end
        if not (pos and pos.is_a and pos:is_a(Vector3)) then
            return false, "MISSING_POS"
        end
    end

    -- 调用封装函数构造 BufferedAction
    local act = self:BuildBufferedAction(target, pos, skill_id, true)
    if not act then
        return false, "BUILD_ACTION_FAILED"
    end
    -- 执行动作（客户端预览或主控直接执行）
    local pc = self.inst.components.playercontroller
    if not pc then
        return false, "NO_PLAYERCONTROLLER"
    end
    pc:DoAction(act)
    return true
end

return NikkiSkill
