-- widgets/nikki_panel.lua
local Widget = require "widgets/widget"
local NikkiBadge = require "widgets/nikki_badge"
local TEMPLATES = require "widgets/redux/templates"
local NikkiClientSettings = require "nikki_client_settings"


local function PushIndicatorEvent(owner, new_state)
    if not (owner and owner:IsValid()) then
        print("[NikkiPanel] PushIndicatorEvent: owner is invalid, skipping event push")
        return
    end
    owner:PushEvent("skill_range_toggle_changed", { new_state = new_state })
    print(string.format("[NikkiPanel] PushIndicatorEvent: new_state=%s", tostring(new_state)))
end
local NikkiPanel = Class(Widget, function(self, owner, dir, spacing)
    Widget._ctor(self, "NikkiPanel")
    self.owner = owner

    -- 直接在初始化时绑定布局参数
    self.dir = dir or -1
    self.spacing = spacing or 62

    self.badge_pool = {}

    -- 射程切换按钮
    local init_checked = NikkiClientSettings.GetShowRange()

    self.range_btn = self:AddChild(TEMPLATES.StandardCheckbox(
        function()
            local new_state = NikkiClientSettings.ToggleShowRange()
            PushIndicatorEvent(owner, new_state)
            return new_state
        end,
        64,
        init_checked,
        "切换射程指示器"
    ))
    self.range_btn:SetPosition(0, -70)

    if owner and owner:IsValid() then
        self.inst:DoTaskInTime(FRAMES, function()
            -- 初始化排列
            self:UpdateBadges()
            -- 初始化时同步状态
            PushIndicatorEvent(owner, init_checked)
            -- 初始化射程按钮显示状态
            self:UpdateRangeButtonVisibility()
            -- 监听形态改变事件
            self.inst:ListenForEvent("nikki_state_dirty", function()
                self:UpdateBadges()
            end, owner)
            -- 监听射程更新事件
            self.inst:ListenForEvent("skill_max_range_dirty", function()
                self:UpdateRangeButtonVisibility()
            end, owner)
        end)
    end
end)

-- 核心方法：动态更新与排列 Badges
function NikkiPanel:UpdateBadges()
    local owner = self.owner
    if not (owner and owner:IsValid() and owner.replica and owner.replica.nikki_state) then return end
    local raw_res_ids = owner.replica.nikki_state:GetStateBadges()
    local res_ids = {}

    if type(raw_res_ids) == "table" then
        res_ids = raw_res_ids
    elseif type(raw_res_ids) == "string" and raw_res_ids ~= "" then
        res_ids = { raw_res_ids }
    end

    local count = #res_ids

    for i = 1, count do
        local res_id = res_ids[i]
        local badge = self.badge_pool[i]

        if not badge then
            badge = self:AddChild(NikkiBadge(owner))
            self.badge_pool[i] = badge
        end

        local offset_x = (i - 1) * self.dir * self.spacing
        badge:SetPosition(offset_x, 0)
        badge:SetRes(res_id)
        badge:Show()
    end

    for i = count + 1, #self.badge_pool do
        if self.badge_pool[i] then self.badge_pool[i]:Hide() end
    end
end

function NikkiPanel:UpdateRangeButtonVisibility()
    local owner = self.owner
    local range = (owner and owner.replica.nikki_skill and owner.replica.nikki_skill:GetMaxRange() or 0)
    -- 当存在有效射程 (>0) 时显示开关控件，无射程时自动隐藏
    if range > 0 then
        print(string.format("[NikkiPanel] UpdateRangeButtonVisibility: radius=%d, showing range button", range))
        self.range_btn:Show()
    else
        print(string.format("[NikkiPanel] UpdateRangeButtonVisibility: radius=%d, hiding range button", range))
        self.range_btn:Hide()
    end
end

return NikkiPanel
