-- scripts/components/nikki_state.lua
local log = require("utils/log")

local function GetResolver(self)
    if not self._resolver and NikkiManager then
        self._resolver = NikkiManager:GetStateResolver()
    end
    return self._resolver
end

local function on_state(self, state)
    if self.inst.replica.nikki_state then
        self.inst.replica.nikki_state:SetState(state)
    end
    self.inst:PushEvent("nikki_state_dirty", { state = state })
end

local NikkiState = Class(function(self, inst)
        self.inst = inst
        self.state = nil
        self.default_state = "default"

        self._resolver = nil
        self._active_overlay_skills = {}
        self._active_tags = {}
        self._active_key_bindings = {}

        self.inst:ListenForEvent("death", function()
            log.debug("[NikkiState] %s died. Clearing all state overlays.", tostring(self.inst))
            self:ClearState()
        end)

        self.inst:ListenForEvent("ms_respawnedfromghost", function()
            log.debug("[NikkiState] %s respawned. Restoring default state: %s", tostring(self.inst),
                tostring(self.default_state))
            if self.default_state then
                self:SetState(self.default_state, true)
            end
        end)
    end,
    nil,
    {
        state = on_state
    })

function NikkiState:SetDefaultState(state)
    self.default_state = state
end

function NikkiState:ClearState()
    self.state = nil
    self:ApplyStateDef(nil)
end

function NikkiState:SetState(state, force)
    if self.inst:HasTag("playerghost") or (self.inst.components.health and self.inst.components.health:IsDead()) then
        log.debug("[NikkiState] Refusing to set state '%s', entity %s is dead.", tostring(state), tostring(self.inst))
        return
    end

    if self.state == state and not force then return end
    self.state = state
    log.debug("[NikkiState] %s state changed to %s", tostring(self.inst), state)
    self:RefreshOverlay()
end

function NikkiState:RefreshOverlay()
    local resolver = GetResolver(self)
    if not resolver then return end
    local def = resolver:GetStateDef(self.state)
    self:ApplyStateDef(def)
end

function NikkiState:ApplyStateDef(def)
    local skill_comp = self.inst.components.nikki_skill
    local trigger_comp = self.inst.components.nikki_skill_trigger
    if not skill_comp then return end

    -- 清理旧的 state 覆盖（只清理当前 state 添加的东西）
    if #self._active_overlay_skills > 0 then
        skill_comp:RemoveSkills(self._active_overlay_skills)
    end

    if #self._active_tags > 0 then
        for _, tag in ipairs(self._active_tags) do
            self.inst:RemoveTag(tag)
        end
    end

    if next(self._active_key_bindings) then
        for key_code, skill_id in pairs(self._active_key_bindings) do
            if trigger_comp then
                trigger_comp:Remove("keys", key_code, skill_id)
            end
        end
    end

    self._active_overlay_skills = {}
    self._active_tags = {}
    self._active_key_bindings = {}

    if not def then return end

    -- 外观
    local visuals = def.visuals or {}
    local build = type(visuals.build) == "function" and visuals.build(self.inst) or visuals.build or self.inst.prefab
    log.debug("[NikkiState] Applying build %s to %s", tostring(build), tostring(self.inst))
    self.inst.AnimState:SetBuild(build)
    local bank = type(visuals.bank) == "function" and visuals.bank(self.inst) or visuals.bank
    if bank then
        self.inst.AnimState:SetBank(bank)
    end

    -- 技能
    if def.skills and #def.skills > 0 then
        skill_comp:AddSkills(def.skills)
        self._active_overlay_skills = def.skills
    end

    -- 标签
    if def.tags and #def.tags > 0 then
        for _, tag in ipairs(def.tags) do
            self.inst:AddTag(tag)
        end
        self._active_tags = def.tags
    end

    -- 按键绑定（key_bindings）
    if def.key_bindings and next(def.key_bindings) then
        for key_code, skill_id in pairs(def.key_bindings) do
            if trigger_comp then
                trigger_comp:Add("keys", key_code, skill_id)
                self._active_key_bindings[key_code] = skill_id
            end
        end
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
            if self.inst:HasTag("playerghost") or (self.inst.components.health and self.inst.components.health:IsDead()) then
                self:ClearState()
                return
            end
            self:SetState(data.state, true)
            log.debug("[NikkiState] Loaded state %s for %s", tostring(data.state), tostring(self.inst))
        end)
    end
end

function NikkiState:ApplyBasic(basic_state_name)
    if self.basic_applied then return end
    if not basic_state_name then return end

    local resolver = GetResolver(self)
    if not resolver then return end

    local basic_def = resolver:GetStateDef(basic_state_name)
    if not basic_def or not next(basic_def) then return end

    local skill_comp = self.inst.components.nikki_skill
    local trigger_comp = self.inst.components.nikki_skill_trigger

    if skill_comp then
        if basic_def.skills and #basic_def.skills > 0 then
            skill_comp:AddSkills(basic_def.skills)
        end
    end

    if basic_def.tags and #basic_def.tags > 0 then
        for _, tag in ipairs(basic_def.tags) do
            self.inst:AddTag(tag)
        end
    end

    if basic_def.key_bindings and next(basic_def.key_bindings) and trigger_comp then
        for key_code, skill_id in pairs(basic_def.key_bindings) do
            trigger_comp:Add("keys", key_code, skill_id)
        end
    end

    self.basic_applied = true
    log.debug("[NikkiState] Applied basic state '%s' to %s", basic_state_name, tostring(self.inst))
end

return NikkiState
