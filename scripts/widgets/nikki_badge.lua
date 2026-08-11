local Badge = require "widgets/badge"
local UIAnim = require "widgets/uianim"
local ResourceAdapter = require("utils/resource_adapter")

local NikkiBadge = Class(Badge, function(self, owner)
    -- 参数：(anim, owner, [1]tint, [2]iconbuild, [3]circular_meter, [4]use_clear_bg, [5]dont_update_while_paused, [6]bonustint)
    -- "manabadge" 仅用于占位初始化创建 selfanim 同官方做法，防止图层顺序错误
    Badge._ctor(self, "manabadge", owner, nil, nil, nil, true, true)
    self.owner = owner
    self.current_attr = nil -- 直接记录属性名：mana 或 spark

    self.rate_scale_arrow = self.underNumber:AddChild(UIAnim())
    self.rate_scale_arrow:GetAnimState():SetBank("sanity_arrow")
    self.rate_scale_arrow:GetAnimState():SetBuild("sanity_arrow")
    self.rate_scale_arrow:GetAnimState():PlayAnimation("neutral")
    self.rate_scale_arrow:GetAnimState():AnimateWhilePaused(false)
    self.rate_scale_arrow:SetClickable(false)
    self.arrow_anim = "neutral"
end)

function NikkiBadge:SetRes(res_id)
    self.current_res_id = res_id

    if res_id then
        local ui_config = ResourceAdapter.GetUIConfig(res_id)

        -- 优先使用 Config 里配的 UI，没配就兜底用 res_id 拼接
        local bank = ui_config and ui_config.bank or (res_id .. "badge")
        local build = ui_config and ui_config.build or (res_id .. "badge")
        local anim = ui_config and ui_config.anim or "anim"

        self.anim:GetAnimState():SetBank(bank)
        self.anim:GetAnimState():SetBuild(build)
        self.anim:GetAnimState():PlayAnimation(anim)
        self:Open()
    else
        self:Close()
    end
end

function NikkiBadge:Open()
    self:Show()
    self:StartUpdating()
end

function NikkiBadge:Close()
    self:Hide()
    self:StopUpdating()
end

local REGEN_RATE_SCALE_ANIM =
{
    [RATE_SCALE.INCREASE_HIGH] = "arrow_loop_increase_most",
    [RATE_SCALE.INCREASE_MED]  = "arrow_loop_increase_more",
    [RATE_SCALE.INCREASE_LOW]  = "arrow_loop_increase",
}

local DECREASE_RATE_SCALE_ANIM =
{
    [RATE_SCALE.DECREASE_HIGH] = "arrow_loop_decrease_most",
    [RATE_SCALE.DECREASE_MED]  = "arrow_loop_decrease_more",
    [RATE_SCALE.DECREASE_LOW]  = "arrow_loop_decrease",
}

function NikkiBadge:OnUpdate(dt)
    if not self.current_res_id or not self.owner then return end

    local anim = "neutral"

    -- 【核心修改】：通过统一接口向 Adapter 获取数据，UI 完全不知道 Replica 的存在
    local percent = ResourceAdapter.GetUIValue(self.owner, self.current_res_id, "percent") or 0
    local rate_scale = ResourceAdapter.GetUIValue(self.owner, self.current_res_id, "rate_scale") or RATE_SCALE.NEUTRAL
    local max_for_text = ResourceAdapter.GetUIValue(self.owner, self.current_res_id, "max") or 100

    if REGEN_RATE_SCALE_ANIM[rate_scale] then
        if percent < 1 then
            anim = REGEN_RATE_SCALE_ANIM[rate_scale]
        end
    elseif DECREASE_RATE_SCALE_ANIM[rate_scale] then
        if percent > 0 then
            anim = DECREASE_RATE_SCALE_ANIM[rate_scale]
        end
    end

    if self.arrow_anim ~= anim then
        self.arrow_anim = anim
        self.rate_scale_arrow:GetAnimState():PlayAnimation(anim, true)
    end

    self:SetPercent(percent, max_for_text)
end

return NikkiBadge
