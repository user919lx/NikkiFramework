local log = require("utils/log")
local is_debug_mode = GetModConfigData("debug_mode")
if is_debug_mode then
    log.set_level("debug")
end
require("strings/nikki_framework")

PrefabFiles = {
    "nikki_spell_caster",
    "nikki_range_indicator",
    "nikki_aura",
    "nikki_reticule"
}
AddReplicableComponent("nikki_skill_trigger")
AddReplicableComponent("nikki_state")
AddReplicableComponent("nikki_skillwheel")
AddReplicableComponent("nikki_skill")

local NikkiManager = require("nikki_manager").GetInstance()
NikkiManager:Init(env)
GLOBAL.NikkiManager = NikkiManager


AddModRPCHandler("NikkiFramework", "TryExecuteSkill", function(player, skill_id, target, x, z)
    local skill_comp = player.components.nikki_skill_caster
    if not skill_comp then
        log.debug("[RPCHandler TryExecuteSkill] Player does not have NikkiSkillCaster component")
        return
    end
    local pos = nil
    if x and z then
        pos = GLOBAL.Vector3(x, 0, z)
    end
    skill_comp:TryExecute(skill_id, { target = target, pos = pos, is_rpc = true })
end)

-- 实现 瞄准Mode=pos的任意action state转换
local function HookCastAOEHandler(sg)
    -- 获取当前的 CASTAOE actionhandler[cite: 5, 6, 7]
    local old_handler = sg.actionhandlers[GLOBAL.ACTIONS.CASTAOE]
    if old_handler ~= nil then
        local old_deststate = old_handler.deststate
        -- 重写 deststate 函数
        old_handler.deststate = function(inst, action)
            local invobject = action.invobject
            local nikki_aoe_state = invobject and invobject.prefab == "nikki_spell_caster" and invobject._nikki_aoe_state
            if nikki_aoe_state ~= nil then
                -- 如果是函数则执行，如果是字符串则直接返回
                if type(nikki_aoe_state) == "function" then
                    local custom_state = nikki_aoe_state(inst, action)
                    if custom_state ~= nil then
                        return custom_state
                    end
                else
                    return nikki_aoe_state
                end
            end
            -- 如果没有设置自定义状态，维持原版/其他模组的逻辑[cite: 5, 6, 7]
            if old_deststate ~= nil then
                return old_deststate(inst, action)
            end
        end
    end
end
-- 同时为主机（wilson）和客机预测端（wilson_client）注册 Hook[cite: 5, 6]
AddStategraphPostInit("wilson", HookCastAOEHandler)
AddStategraphPostInit("wilson_client", HookCastAOEHandler)

AddComponentPostInit("aoetargeting", function(self)
    function self:SetReticule(reticule)
        self.reticule = reticule or {}
        if self.inst.components.reticule ~= nil then
            self.inst.components.reticule:SetConfig(self.reticule)
        end
    end
end)
AddComponentPostInit("reticule", function(self)
    function self:_ApplyParamsToEntity(inst)
        if inst ~= nil then
            inst.AnimState:ClearBloomEffectHandle()
            if inst.SetShape ~= nil then
                inst:SetShape(self.shape or "CIRCLE", self.radius, self.shape_param)
            elseif inst.SetRadius ~= nil and self.radius ~= nil then
                inst:SetRadius(self.radius)
            end
            if inst.SetSearchFn ~= nil then
                inst:SetSearchFn(self.search_fn)
            end
        end
    end

    function self:SetConfig(config)
        self.targetfn = nil
        self.mousetargetfn = nil
        self.updatepositionfn = nil
        self.shape = nil
        self.shape_param = nil
        self.radius = nil
        self.search_fn = nil

        config = config or {}
        for k, v in pairs(config) do
            self[k] = v
        end

        self:_ApplyParamsToEntity(self.reticule)
        if self.reticule ~= nil and self.UpdateColour ~= nil then
            self:UpdateColour()
        end
    end

    local _CreateReticule = self.CreateReticule
    function self:CreateReticule(...)
        _CreateReticule(self, ...)
        self:_ApplyParamsToEntity(self.reticule)
    end

    local _PingReticuleAt = self.PingReticuleAt
    function self:PingReticuleAt(pos)
        local old_SpawnPrefab = GLOBAL.SpawnPrefab
        GLOBAL.SpawnPrefab = function(prefab, ...)
            local inst = old_SpawnPrefab(prefab, ...)
            self:_ApplyParamsToEntity(inst)
            return inst
        end
        local ok, err = GLOBAL.pcall(_PingReticuleAt, self, pos)
        GLOBAL.SpawnPrefab = old_SpawnPrefab
        if not ok then
            GLOBAL.error(err)
        end
    end

    local _UpdatePosition = self.UpdatePosition
    function self:UpdatePosition(dt)
        _UpdatePosition(self, dt)
        if self.reticule ~= nil and self.reticule.prefab == "nikki_reticule" then
            self.reticule.AnimState:ClearBloomEffectHandle()
        end
    end
end)

if not GLOBAL.TheNet:IsDedicated() then
    GLOBAL.TheInput:AddKeyHandler(function(key, down)
        if not down then return end
        local player = GLOBAL.ThePlayer
        if not player or not player:IsValid() then return end
        if GLOBAL.TheFrontEnd:GetActiveScreen() ~= player.HUD then return end
        if player.replica.nikki_skill_trigger then
            player.replica.nikki_skill_trigger:CastKey(key)
        end
    end)

    AddClassPostConstruct("widgets/statusdisplays", function(self)
        if not self.owner:HasTag("nikki_framework") then return end

        local DEFAULT_BADGE_SPACING = 62
        local VERTICAL_MARGIN = 70

        self._nikki_badges = {}
        self._nikki_range_btn = nil

        -- ============================================================
        -- 辅助函数：生成切换回调（DRY）
        -- ============================================================
        local function make_toggle_callback()
            return function()
                local new_state = NikkiManager:ToggleSetting("show_range")
                local owner = self.owner
                if owner and owner:IsValid() then
                    owner:PushEvent("skill_range_toggle_changed", { new_state = new_state })
                end
                return new_state
            end
        end

        local function refresh_ui()
            local initial_checked = NikkiManager:GetSetting("show_range")
            local toggle_callback = make_toggle_callback()
            self:_Nikki_RefreshBadges()
            self:_Nikki_UpdateRangeButton(initial_checked, toggle_callback)
        end

        -- ============================================================
        -- 初始化：延迟一秒执行
        -- ============================================================
        self.inst:DoTaskInTime(1, refresh_ui)

        -- ============================================================
        -- 事件监听
        -- ============================================================
        if self.owner and self.owner:IsValid() then
            self.inst:ListenForEvent("nikki_state_dirty", function()
                self:_Nikki_RefreshBadges()
            end, self.owner)
            self.inst:ListenForEvent("skill_max_range_dirty", refresh_ui, self.owner)
        end

        -- ============================================================
        -- 私有方法
        -- ============================================================
        function self:_Nikki_CalcLayoutParams()
            local core_badges = { "brain", "stomach", "heart" }
            local groups = {}
            for _, badge in ipairs(core_badges) do
                local badge_widget = self[badge]
                if badge_widget and badge_widget:IsVisible() then
                    local x, y, _ = badge_widget:GetPositionXYZ()
                    if not groups[y] then
                        groups[y] = {}
                    end
                    table.insert(groups[y], x)
                end
            end

            if GLOBAL.next(groups) == nil then
                return DEFAULT_BADGE_SPACING, 0, 0
            end

            local main_y = 0
            local max_count = 0
            for y, xs in pairs(groups) do
                if #xs > max_count then
                    max_count = #xs
                    main_y = y
                end
            end

            local main_xs = groups[main_y]
            table.sort(main_xs)
            local leftmost_x = main_xs[1]

            local spacing = (#main_xs >= 2) and math.abs(main_xs[2] - main_xs[1]) or DEFAULT_BADGE_SPACING
            return spacing, leftmost_x - spacing, main_y
        end

        function self:_Nikki_UpdateRangeButton(initial_checked, toggle_callback)
            local owner = self.owner
            if not (owner and owner:IsValid()) then return end

            local range = owner.replica.nikki_skill and owner.replica.nikki_skill:GetMaxRange() or 0
            if range <= 0 then
                if self._nikki_range_btn then
                    self._nikki_range_btn:Hide()
                end
                return
            end

            -- 直接在这里创建按钮
            if not self._nikki_range_btn then
                local TEMPLATES = require("widgets/redux/templates")
                self._nikki_range_btn = self:AddChild(TEMPLATES.StandardCheckbox(
                    toggle_callback,
                    64,
                    initial_checked,
                    "切换射程指示器"
                ))
            end

            local _, start_x, y = self:_Nikki_CalcLayoutParams()
            self._nikki_range_btn:SetPosition(start_x, y - VERTICAL_MARGIN, 0)
            self._nikki_range_btn:Show()
        end

        function self:_Nikki_RefreshBadges()
            local owner = self.owner
            if not (owner and owner:IsValid() and owner.replica and owner.replica.nikki_state) then
                return
            end

            local spacing, start_x, y = self:_Nikki_CalcLayoutParams()

            local raw_ids = owner.replica.nikki_state:GetBadges()
            local res_ids = {}
            if type(raw_ids) == "table" then
                res_ids = raw_ids
            elseif type(raw_ids) == "string" and raw_ids ~= "" then
                res_ids = { raw_ids }
            end

            local count = #res_ids
            local NikkiBadge = require("widgets/nikki_badge")
            for i = 1, count do
                local badge = self._nikki_badges[i]
                if not badge then
                    badge = self:AddChild(NikkiBadge(owner))
                    self._nikki_badges[i] = badge
                end
                badge:SetPosition(start_x - spacing * (i - 1), y, 0)
                badge:SetRes(res_ids[i])
            end
            for i = count + 1, #self._nikki_badges do
                if self._nikki_badges[i] then
                    self._nikki_badges[i]:Close()
                end
            end
        end
    end)
end

local default_config = require("defs/default_config")
NikkiManager:RegisterMod(default_config, env)

if not is_debug_mode then
    return
end
