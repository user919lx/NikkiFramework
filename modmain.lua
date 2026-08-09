local log = GLOBAL.require("utils/log")
local is_debug_mode = GetModConfigData("debug_mode")
if is_debug_mode then
    log.set_level("debug")
end
PrefabFiles = {
    "nikki_spell_caster",
    "nikki_range_indicator",
}
AddReplicableComponent("nikki_skill_trigger")
AddReplicableComponent("nikki_state")
AddReplicableComponent("nikki_skillwheel")
AddReplicableComponent("nikki_skill")



-- 废除 CastKey RPC，统一使用 CastSkill
AddModRPCHandler("NikkiFramework", "CastSkill", function(player, skill_id, target, has_pos, px, pz)
    -- 统一网关：必须先经过 nikki_skill_trigger 拦截并记录上下文！
    if player and player.components.nikki_skill_trigger then
        local params = {}
        if target then params.target = target end
        if has_pos then params.pos = GLOBAL.Vector3(px, 0, pz) end
        -- 交给 Trigger 缓存目标，再由其转发给 Skill
        player.components.nikki_skill_trigger:CastSkill(skill_id, params)
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
    local BADGE_SPACING = 62 -- 与 Combined Status 三围徽章间距一致
    local function AddExtraStatusWidget(self)
        if self.owner and self.owner:HasTag("nikki_framework") then
            local sx, sy = self.stomach:GetPositionXYZ()
            local dir = sx < 0 and -1 or 1
            local NikkiPanel = require("widgets/nikki_panel")
            self.nikki_panel = self:AddChild(NikkiPanel(self.owner, dir, BADGE_SPACING))
            self.nikki_panel:SetPosition(sx + dir * BADGE_SPACING, sy, 0)
        end
    end
    AddClassPostConstruct("widgets/statusdisplays", AddExtraStatusWidget)
end

if not is_debug_mode then
    return
end