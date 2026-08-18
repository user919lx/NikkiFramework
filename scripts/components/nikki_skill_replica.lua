local NikkiSkill = Class(function(self, inst)
    self.inst = inst
    self._max_range = net_float(inst.GUID, "skill._max_range", "skill_maxrangedirty")
    self._max_range:set(0)
    self._resolver = nil
    if not TheWorld.ismastersim then
        inst:ListenForEvent("skill_maxrangedirty", function()
            inst:PushEvent("skill_max_range_dirty", { max_range = self:GetMaxRange() })
        end)
    end
end)

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

-- ============================================================
-- 客户端执行入口：补全参数 → 构造 BufferedAction → 发送 RPC
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

    -- 构造 BufferedAction
    local act = BufferedAction(
        self.inst,
        target,
        ACTIONS.NIKKI_SKILL,
        nil,
        pos,
        nil,
        def.range or 0
    )

    -- 挂载元数据
    act._skill_state = action_def.state or "doshortaction"
    -- 客户端发送 RPC（只发 skill_id, target, x, z）
    local pc = self.inst.components.playercontroller
    if not pc then
        return false, "NO_PLAYERCONTROLLER"
    end
    local x = pos and pos.x or nil
    local z = pos and pos.z or nil
    local preview_cb = function()
        SendModRPCToServer(GetModRPC("NikkiFramework", "TryExecuteSkill"),
            skill_id,
            target,
            x,
            z
        )
    end
    if pc.locomotor ~= nil then
        act.preview_cb = preview_cb
    else
        act.non_preview_cb = preview_cb
    end
    pc:DoAction(act)
    return true
end


return NikkiSkill
