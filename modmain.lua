local log = require("utils/log")
local is_debug_mode = GetModConfigData("debug_mode")
if is_debug_mode then
    log.set_level("debug")
end
require("strings/nikki_framework")

PrefabFiles = {
    "nikki_spell_caster",
    "nikki_range_indicator",
    "nikki_aura_fx",
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
    skill_comp:TryExecute(skill_id, { target = target, pos = pos })
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
