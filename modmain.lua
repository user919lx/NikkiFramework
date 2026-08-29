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
            if nikki_aoe_state then
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
            if old_deststate ~= nil then
                local old_state = old_deststate(inst, action)
                return old_state
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

-- 实验性功能 未实装
-- AddClassPostConstruct("screens/playerinfopopupscreen", function(self)
--     if self.owner and self.owner:HasTag("nikki_framework") then
--         local Widget = require("widgets/widget")
--         local ImageButton = require("widgets/imagebutton")

--         local function MakeTabBtn(tabs_widget, pos, text, clickfn, flip)
--             local btn = tabs_widget:AddChild(ImageButton("images/skilltree.xml",
--                 "tab_skills_unselected.tex", "tab_skills_unselected.tex", "tab_skills_over.tex",
--                 "tab_skills_unselected.tex", "tab_skills_over.tex"
--             ))
--             local size = { 142, 96 }
--             if flip then size[1] = size[1] * -1 end
--             btn:SetPosition(pos[1], pos[2])
--             btn:ForceImageSize(size[1], size[2])
--             btn:SetText(text)
--             btn:SetTextSize(20)
--             btn:SetFont(GLOBAL.HEADERFONT)
--             btn:SetDisabledFont(GLOBAL.HEADERFONT)
--             btn:SetTextColour(GLOBAL.UICOLOURS.GOLD)
--             btn.scale_on_focus = false
--             btn.clickoffset = GLOBAL.Vector3(0, 5, 0)
--             btn:SetTextFocusColour(GLOBAL.UICOLOURS.GOLD)
--             btn:SetTextSelectedColour(GLOBAL.UICOLOURS.GOLD)
--             btn:SetTextDisabledColour(GLOBAL.UICOLOURS.GOLD)
--             btn.text:SetPosition(flip and 2 or -2, -5)
--             btn:SetOnClick(clickfn)
--             return btn
--         end

--         -- 1. 自定义面板生成方法
--         self.MakeNikkiStatus = function(self)
--             if self.playeravatar then
--                 self.playeravatar:Kill()
--                 self.playeravatar = nil
--             end
--             if self.skilltree then
--                 self.skilltree:Kill()
--                 self.skilltree = nil
--             end

--             if not self.nikkistatus then
--                 local NikkiStatus = require("widgets/nikki_status")

--                 -- ===================================================
--                 -- 【核心改变】由 Screen 负责调用 Manager 获取数据切片
--                 -- ===================================================
--                 local status_data = NikkiManager:GetPlayerStatusSnapshot(self.data.inst)
--                 -- 将数据直接注入 Widget
--                 self.nikkistatus = self.root:AddChild(NikkiStatus(status_data))
--                 self.nikkistatus:SetPosition(0, -50)
--             end

--             if self.root.tabs then
--                 if self.root.tabs.playerAvatarPopup then self.root.tabs.playerAvatarPopup:Enable() end
--                 if self.root.tabs.skillTreePopup then self.root.tabs.skillTreePopup:Enable() end
--                 if self.root.tabs.nikkiStatusPopup then self.root.tabs.nikkiStatusPopup:Disable() end
--             end
--         end

--         -- 2. 构建或重排 Tabs
--         if not self.root.tabs then
--             self.root.tabs = self.root:AddChild(Widget("tabs"))
--             self.root.tabs:SetPosition(0, 0)

--             local avatar_str = GLOBAL.STRINGS.SKILLTREE and GLOBAL.STRINGS.SKILLTREE.INFOPANEL or "玩家信息"
--             self.root.tabs.playerAvatarPopup = MakeTabBtn(self.root.tabs, { -165, 220 }, avatar_str,
--                 function() self:MakePlayerAvatarPopup() end, true)
--             self.root.tabs.nikkiStatusPopup = MakeTabBtn(self.root.tabs, { 165, 220 }, "状态效果",
--                 function() self:MakeNikkiStatus() end, false)

--             self.root.tabs.playerAvatarPopup:Disable()
--         else
--             if self.root.tabs.playerAvatarPopup then self.root.tabs.playerAvatarPopup:SetPosition(-200, 220) end
--             if self.root.tabs.skillTreePopup then self.root.tabs.skillTreePopup:SetPosition(0, 220) end
--             self.root.tabs.nikkiStatusPopup = MakeTabBtn(self.root.tabs, { 200, 220 }, "状态效果",
--                 function() self:MakeNikkiStatus() end, false)

--             if self.MakeSkillTree then
--                 local _MakeSkillTree = self.MakeSkillTree
--                 self.MakeSkillTree = function(self)
--                     if self.nikkistatus then
--                         self.nikkistatus:Kill()
--                         self.nikkistatus = nil
--                     end
--                     _MakeSkillTree(self)
--                     if self.root.tabs and self.root.tabs.nikkiStatusPopup then
--                         self.root.tabs.nikkiStatusPopup:Enable()
--                     end
--                 end
--             end
--         end

--         -- 3. 重新对齐图层渲染层级
--         if self.root.tabs then
--             self.root.tabs:MoveToBack()
--             if self.root.bg then
--                 self.root.bg:MoveToBack()
--             end
--         end

--         -- 4. 拦截玩家头像面板刷新
--         local _MakePlayerAvatarPopup = self.MakePlayerAvatarPopup
--         self.MakePlayerAvatarPopup = function(self)
--             if self.nikkistatus then
--                 self.nikkistatus:Kill()
--                 self.nikkistatus = nil
--             end

--             local temp_tabs = self.root.tabs
--             self.root.tabs = nil
--             _MakePlayerAvatarPopup(self)
--             self.root.tabs = temp_tabs

--             if self.root.tabs then
--                 if self.root.tabs.playerAvatarPopup then self.root.tabs.playerAvatarPopup:Disable() end
--                 if self.root.tabs.skillTreePopup then self.root.tabs.skillTreePopup:Enable() end
--                 if self.root.tabs.nikkiStatusPopup then self.root.tabs.nikkiStatusPopup:Enable() end
--             end
--         end
--     end
-- end)