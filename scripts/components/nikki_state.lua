local log = require("utils/log")
local NikkiManager = require("nikki_manager")

local function on_state(self, state)
    local old_state = self._last_state
    if self.inst.replica.nikki_state then
        self.inst.replica.nikki_state:SetState(state, old_state)
    end
    self.inst:PushEvent("nikki_state_dirty", { state = state, old_state = old_state })
end

local NikkiState = Class(function(self, inst)
        self.inst = inst
        self.state = nil
        self._active_overlay_skills = {}
        self._active_tags = {}
        self._active_keys = nil
    end,
    nil,
    {
        state = on_state
    })

function NikkiState:ClearState()
    self.state = nil
    self:ApplyStateDef(nil)
end

function NikkiState:SetState(state, force)
    if self.state == state and not force then return end
    self._last_state = self.state
    self.state = state

    log.debug("[NikkiState] %s state changed to %s", tostring(self.inst), tostring(state))
    self:RefreshOverlay()
end

function NikkiState:RefreshOverlay()
    local resolver = NikkiManager.GetInstance():GetResolver("state")
    if not resolver then return end
    local def = resolver:GetDef(self.state)
    self:ApplyStateDef(def)
end

function NikkiState:ApplyStateDef(def)
    local skill_comp = self.inst.components.nikki_skill
    local trigger_comp = self.inst.components.nikki_skill_trigger

    -- 1. 清理上一个状态的技能、标签和按键
    if skill_comp and #self._active_overlay_skills > 0 then
        skill_comp:RemoveSkills(self._active_overlay_skills)
    end

    if #self._active_tags > 0 then
        for _, tag in ipairs(self._active_tags) do
            self.inst:RemoveTag(tag)
        end
    end

    if trigger_comp and self._active_keys then
        for key_code, skill_id in pairs(self._active_keys) do
            trigger_comp:Remove("keys", key_code, skill_id)
        end
    end

    self._active_overlay_skills = {}
    self._active_tags = {}
    self._active_keys = nil

    if not def then return end

    -- 2. 外观应用 (Build / Bank)
    local visuals = def.visuals or {}
    local build = type(visuals.build) == "function" and visuals.build(self.inst) or visuals.build or self.inst.prefab
    self.inst.AnimState:SetBuild(build)
    local bank = type(visuals.bank) == "function" and visuals.bank(self.inst) or visuals.bank
    if bank then
        self.inst.AnimState:SetBank(bank)
    end

    -- 3. 专属技能挂载
    if skill_comp and def.skills and #def.skills > 0 then
        skill_comp:AddSkills(def.skills)
        self._active_overlay_skills = def.skills
    end

    -- 4. 专属标签挂载
    if def.tags and #def.tags > 0 then
        for _, tag in ipairs(def.tags) do
            self.inst:AddTag(tag)
        end
        self._active_tags = def.tags
    end

    -- 5. 专属按键挂载
    if trigger_comp and def.keys then
        for key_code, skill_id in pairs(def.keys) do
            trigger_comp:Add("keys", key_code, skill_id)
        end
        self._active_keys = def.keys
    end
end

function NikkiState:GetState()
    return self.state
end

function NikkiState:OnSave()
    return { state = self.state }
end

function NikkiState:OnLoad(data)
    if data and data.state then
        self.inst:DoTaskInTime(0, function()
            if self.inst:IsValid() then
                self:SetState(data.state, true)
                log.debug("[NikkiState] Loaded state %s for %s", tostring(data.state), tostring(self.inst))
            end
        end)
    end
end

return NikkiState
