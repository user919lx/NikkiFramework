-- scripts/components/nikki_state.lua
local ResolverRegistry = require("nikki_resolver_registry")
local log = require("utils/log")

-- 私有懒加载
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
        -- 新增：缓存默认状态，供复活时使用
        self.default_state = "default"

        self._resolver = nil
        self._active_overlay_skills = {}
        self._active_overlay_effects = {}
        self._active_tags = {}

        -- 【生命周期：死亡】剥离所有形态带来的技能、效果、触发器和外观
        self.inst:ListenForEvent("death", function()
            log.debug("[NikkiState] %s died. Clearing all state overlays.", tostring(self.inst))
            self:ClearState()
        end)

        -- 【生命周期：复活】恢复到默认形态
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

-- 注入默认状态名
function NikkiState:SetDefaultState(state)
    self.default_state = state
end

-- 净身出户：将状态设空，并清空所有覆盖物
function NikkiState:ClearState()
    self.state = nil
    self:ApplyStateDef(nil)
end

function NikkiState:SetState(state, force)
    -- 【死亡防污染】：如果实体处于死亡或鬼魂状态，拒绝强行写入状态
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

    -- 传入 nil 时，上述清理工作完成，直接 return 退出，完美实现“净身出户”
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
        self.inst:DoTaskInTime(0, function()
            -- 【读档校验】：如果存档载入后发现是个死人，清空一切状态，拒绝恢复外观
            if self.inst:HasTag("playerghost") or (self.inst.components.health and self.inst.components.health:IsDead()) then
                self:ClearState()
                return
            end
            -- 活人正常恢复状态
            self:SetState(data.state, true)
            log.debug("[NikkiState] Loaded state %s for %s", tostring(data.state), tostring(self.inst))
        end)
    end
end

return NikkiState
