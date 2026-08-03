-- scripts/components/nikki_state.lua
local NikkiComponentBase = require("components/nikki_component_base")
local log = require("utils/log")
log.set_level("debug")


local function on_state(self, state)
    log.debug("[NikkiState] on_state: State changed to '%s'", tostring(state))
    if self.inst.replica.nikki_state then
        self.inst.replica.nikki_state:SetState(state)
    end
    self.inst:PushEvent("nikki_state_dirty", { state = state})
end

-- 继承基类
local NikkiState = Class(NikkiComponentBase, function(self, inst)
        NikkiComponentBase._ctor(self, inst)

        self.default_state = "default"
        self.state = nil

        self._active_overlay_skills = {}
        self._active_tags = {}
    end,
    {
        state = on_state
    })

-- ====================================================
-- 初始化入口：由 FrameworkManager 在装配时统一调用
-- ====================================================
function NikkiState:Init(resolver, default_state)
    if default_state then
        self.default_state = default_state
    end

    self:SetResolver(resolver)

    local target_state = self.state or self.default_state
    self.state = nil
    self:SetState(target_state)

    log.debug("[NikkiState] Initialized with default_state = '%s', active_state = '%s'",
        tostring(self.default_state), tostring(self.state))
end

-- ====================================================
-- 外部控制接口
-- ====================================================
function NikkiState:SetState(state, force)
    if self.state == state and not force then
        return
    end
    self.state = state
    self:RefreshOverlay()
end

-- ====================================================
-- 核心逻辑：刷新与装配覆盖层
-- ====================================================
function NikkiState:RefreshOverlay()
    if not self.resolver then return end
    local def = self.resolver:GetStateDef(self.state)
    self:ApplyStateDef(def)
    log.debug("[NikkiState] Refreshed overlay. State: '%s', Total Skills: %d, Total Tags: %d.",
        tostring(self.state),
        #(def and def.skills or {}),
        #(def and def.tags or {}))
end

function NikkiState:ApplyStateDef(def)
    local skill_comp = self.inst.components.nikki_skill
    local trigger_comp = self.inst.components.nikki_skill_trigger
    if not skill_comp or not trigger_comp then return end

    -- 清理旧状态
    if #self._active_overlay_skills > 0 then
        skill_comp:RemoveSkills(self._active_overlay_skills)
        self._active_overlay_skills = {}
    end

    if #self._active_tags > 0 then
        for _, tag in ipairs(self._active_tags) do
            self.inst:RemoveTag(tag)
        end
        self._active_tags = {}
    end

    trigger_comp:Clear()

    if not def then return end

    -- 装配新状态
    if def.skills and #def.skills > 0 then
        skill_comp:AddSkills(def.skills)
        self._active_overlay_skills = def.skills
    end

    -- 装配触发器
    if def.triggers then
        trigger_comp:SetTriggers(def.triggers)
    end

    if def.tags and #def.tags > 0 then
        for _, tag in ipairs(def.tags) do
            self.inst:AddTag(tag)
        end
        self._active_tags = def.tags
    end

    if def.visuals then
        local visuals = def.visuals
        if visuals.build and self.inst.AnimState then
            self.inst.AnimState:SetBuild(visuals.build)
        end
        if visuals.bank and self.inst.AnimState then
            self.inst.AnimState:SetBank(visuals.bank)
        end
        if visuals.symbol_overrides and self.inst.AnimState then
            for _, override in ipairs(visuals.symbol_overrides) do
                self.inst.AnimState:OverrideSymbol(override.symbol, override.build, override.folder)
            end
        end
    end
end

function NikkiState:OnSave()
    return { state = self.state }
end

function NikkiState:OnLoad(data)
    if data and data.state then
        self:SetState(data.state)
    end
end

return NikkiState
