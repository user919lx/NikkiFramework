-- scripts/components/nikki_state.lua
local NikkiComponentBase = require("components/nikki_component_base")
local log = require("utils/log")
local function on_state(self, state)
    if self.inst.replica.nikki_state then self.inst.replica.nikki_state:SetState(state) end
    self.inst:PushEvent("nikki_state_dirty", { state = state })
end

local NikkiState = Class(NikkiComponentBase, function(self, inst)
    NikkiComponentBase._ctor(self, inst)
    self.default_state = "default"
    self.state = nil
    self._active_overlay_skills = {}
    self._active_overlay_effects = {}
    self._active_tags = {}
end, { state = on_state })

function NikkiState:Init(resolver, default_state)
    if default_state then self.default_state = default_state end
    self:SetResolver(resolver)
    self:SetState(self.state or self.default_state)
end

function NikkiState:SetState(state, force)
    if self.state == state and not force then return end
    self.state = state
    self:RefreshOverlay()
    log.debug("[NikkiState] %s state changed to %s", tostring(self.inst), state)
end

function NikkiState:RefreshOverlay()
    if not self.resolver then return end
    local def = self.resolver:GetStateDef(self.state)
    self:ApplyStateDef(def)
end

function NikkiState:ApplyStateDef(def)
    local skill_comp = self.inst.components.nikki_skill
    local effect_comp = self.inst.components.nikki_effect
    local trigger_comp = self.inst.components.nikki_skill_trigger
    if not skill_comp or not trigger_comp then return end

    -- 清理旧的状态覆盖
    if #self._active_overlay_skills > 0 then skill_comp:RemoveSkills(self._active_overlay_skills) end
    if #self._active_overlay_effects > 0 and effect_comp then
        for _, eff in ipairs(self._active_overlay_effects) do effect_comp:Remove(eff, true) end
    end
    if #self._active_tags > 0 then
        for _, tag in ipairs(self._active_tags) do self.inst:RemoveTag(tag) end
    end
    trigger_comp:Clear()

    self._active_overlay_skills = {}
    self._active_overlay_effects = {}
    self._active_tags = {}

    if not def then return end

    -- 处理外观
    local visuals = def and def.visuals or {}
    local build = type(visuals.build) == "function" and visuals.build(self.inst) or visuals.build or self.inst.prefab
    log.debug("[NikkiState] Applying build %s to %s", tostring(build), tostring(self.inst))
    self.inst.AnimState:SetBuild(build)
    local bank = type(visuals.bank) == "function" and visuals.bank(self.inst) or visuals.bank
    if bank then
        self.inst.AnimState:SetBank(bank)
    end

    -- 处理技能、效果和标签
    if def.skills and #def.skills > 0 then
        skill_comp:AddSkills(def.skills)
        self._active_overlay_skills = def.skills
    end

    if def.effects and #def.effects > 0 and effect_comp then
        for _, eff in ipairs(def.effects) do effect_comp:Apply(eff) end
        self._active_overlay_effects = def.effects
    end

    if def.tags and #def.tags > 0 then
        for _, tag in ipairs(def.tags) do self.inst:AddTag(tag) end
        self._active_tags = def.tags
    end

    -- 添加触发器
    if def.compiled_triggers then
        trigger_comp:SetTriggers(def.compiled_triggers)
    end
end

-- 提供给轮盘等 UI 组件查询用
function NikkiState:GetWheelSkills()
    if not self.resolver or not self.state then return {} end
    local def = self.resolver:GetStateDef(self.state)
    return def and def.wheel or {}
end

-- =========================================================
--                      查询接口
-- =========================================================

-- 查询当前状态
function NikkiState:GetState()
    return self.state
end

return NikkiState
