-- scripts/components/nikki_state.lua
local ResolverRegistry = require("nikki_resolver_registry")
local log = require("utils/log")

-- 私有懒加载：首次调用时向注册表查一次并缓存到 self._resolver，后续直接读缓存
local function GetResolver(self)
    if not self._resolver then
        self._resolver = ResolverRegistry.Get("state")
    end
    return self._resolver
end

local function on_state(self, state)
    if self.inst.replica.nikki_state then self.inst.replica.nikki_state:SetState(state) end
    self.inst:PushEvent("nikki_state_dirty", { state = state })
end

local NikkiState = Class(function(self, inst)
    self.inst = inst
    self.state = nil
    self._resolver = nil -- 私有缓存
    self._active_overlay_skills = {}
    self._active_overlay_effects = {}
    self._active_tags = {}
end,
nil,
{
    state = on_state
})

function NikkiState:SetState(state, force)
    if self.state == state and not force then return end
    self.state = state
    self:RefreshOverlay()
    log.debug("[NikkiState] %s state changed to %s", tostring(self.inst), state)
end

function NikkiState:RefreshOverlay()
    local resolver = GetResolver(self)
    if not resolver then return end
    local def = resolver:GetStateDef(self.state)
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

-- =========================================================
--                      查询接口
-- =========================================================

function NikkiState:GetState()
    return self.state
end

-- =========================================================
--                      持久化存储
-- =========================================================
function NikkiState:OnSave()
    return {
        state = self.state,
    }
end

function NikkiState:OnLoad(data)
    if data and data.state then
        -- 延迟 0 帧执行：防止 AnimState:SetBuild 被官方换肤系统(skinner)或实体初始化的原生逻辑覆盖
        self.inst:DoTaskInTime(0, function()
            -- 传入 true 进行 force 强制刷新，确保视觉和数据组件被完全重置并覆盖
            self:SetState(data.state, true)
            log.debug("[NikkiState] Loaded state %s for %s", tostring(data.state), tostring(self.inst))
        end)
    end
end

return NikkiState
