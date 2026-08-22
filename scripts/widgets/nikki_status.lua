local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"

local NikkiStatus = Class(Widget, function(self, status_data)
    Widget._ctor(self, "NikkiStatus")

    self.root = self:AddChild(Widget("root"))

    -- 简易背景
    self.bg = self.root:AddChild(Image("images/skilltree2.xml", "background.tex"))
    self.bg:SetPosition(0, 0)
    self.bg:ScaleToSize(600, 460)
    self.bg:SetTint(0, 0, 0, 0.75)

    self.title = self.root:AddChild(Text(HEADERFONT, 35, "当前状态与效果", UICOLOURS.GOLD))
    self.title:SetPosition(0, 180)

    -- 渲染形态名
    local state_name = status_data and status_data.state and status_data.state.name or "未知"
    self.state_text = self.root:AddChild(Text(CHATFONT, 28, "当前形态: " .. state_name, UICOLOURS.WHITE))
    self.state_text:SetPosition(0, 120)

    self.effects_title = self.root:AddChild(Text(HEADERFONT, 25, "生效中的增益/减益：", UICOLOURS.GOLD))
    self.effects_title:SetPosition(0, 60)

    -- 渲染效果列表
    local effects_str = ""
    if status_data and status_data.effects then
        for _, eff in ipairs(status_data.effects) do
            effects_str = effects_str .. "• " .. tostring(eff.name)
            if eff.layers > 1 then
                effects_str = effects_str .. " (层数: " .. tostring(eff.layers) .. ")"
            end
            effects_str = effects_str .. "\n"
        end
    end

    if effects_str == "" then
        effects_str = "暂无状态影响。"
    end

    self.effects_text = self.root:AddChild(Text(CHATFONT, 22, effects_str, UICOLOURS.WHITE))
    self.effects_text:SetPosition(0, -30)
    self.effects_text:SetVAlign(ANCHOR_TOP)
    self.effects_text:SetRegionSize(500, 150)
    self.effects_text:EnableWordWrap(true)
end)

return NikkiStatus
