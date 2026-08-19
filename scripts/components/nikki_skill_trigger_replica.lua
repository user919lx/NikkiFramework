-- scripts/components/nikki_skill_trigger_replica.lua
local log = require("utils/log")

local NikkiSkillTrigger = Class(function(self, inst)
    self.inst = inst
    self._keys = {}

    self.inst:ListenForEvent("nikki_state_dirty", function(inst, data)
        local state = data and data.state
        local old_state = data and data.old_state
        self:_RefreshKeys(state, old_state)
        if self.inst.components.nikki_skill_caster then
            self.inst.components.nikki_skill_caster:ExitAiming()
        end
    end)
end)

function NikkiSkillTrigger:Init(resolver)
    if not resolver then
        log.warn("[NikkiSkillTrigger Replica] No resolver provided during Init.")
        return
    end
    self._resolver = resolver
    self:_RefreshKeys(self._resolver:GetBasicState(), nil)
    self:_RefreshKeys()
    if self.inst.components.nikki_skill_caster then
        self.inst.components.nikki_skill_caster:ExitAiming()
    end
end

function NikkiSkillTrigger:AddKey(key_code, skill_id)
    self._keys[key_code] = skill_id
end

function NikkiSkillTrigger:RemoveKey(key_code)
    self._keys[key_code] = nil
end

function NikkiSkillTrigger:_RefreshKeys(current_state, old_state)
    local resolver = self._resolver
    if not resolver then return end

    if not current_state then
        local state_comp = self.inst.replica.nikki_state
        if state_comp then
            current_state = state_comp:GetState()
        end
        if not current_state then return end
    end

    if old_state then
        local old_def = resolver:GetStateDef(old_state)
        if old_def and old_def.keys then
            for key_code, _ in pairs(old_def.keys) do
                self:RemoveKey(key_code)
            end
        end
    end

    local state_def = resolver:GetStateDef(current_state)
    if not state_def then return end

    if state_def.keys and next(state_def.keys) then
        for key_code, skill_id in pairs(state_def.keys) do
            self:AddKey(key_code, skill_id)
        end
    end
end

function NikkiSkillTrigger:GetSkillsForKey(key_code)
    return self._keys[key_code]
end

-- ============================================================
-- 按键触发（客户端路由到通用 Caster）
-- ============================================================
function NikkiSkillTrigger:CastKey(key)
    if self.inst.components.nikki_skill_trigger then
        return self.inst.components.nikki_skill_trigger:Trigger("keys", key)
    end

    local skill_id = self:GetSkillsForKey(key)
    if not skill_id then
        return false
    end

    local caster = self.inst.components.nikki_skill_caster
    if caster then
        return caster:TryExecute(skill_id, {})
    end
    return false
end

return NikkiSkillTrigger
