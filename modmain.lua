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



-- ========================================================
-- 1. 注册服务端 RPC (Master Server)
-- ========================================================
AddModRPCHandler("NikkiFramework", "CastKey", function(player, key_code)
    if player and player.components.nikki_skill_trigger then
        player.components.nikki_skill_trigger:CastKey(key_code)
    end
end)

AddModRPCHandler("NikkiFramework", "CastSkill", function(player, skill_id, target, has_pos, px, pz)
    if player and player.components.nikki_skill then
        local params = {}
        if target then params.target = target end
        if has_pos then params.pos = GLOBAL.Vector3(px, 0, pz) end
        player.components.nikki_skill:CastSkill(skill_id, params)
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
end

if not is_debug_mode then
    return
end
-- 加载测试框架
local require = GLOBAL.require
-- 动态加载 tests/components 下所有 .lua 文件
GLOBAL.c_nikki_run_tests = function()
    print("\n[NikkiFramework] Initiating In-Engine Tests...")
    require("tests/components/test_nikki_state")()
    print("[NikkiFramework] All In-Engine Tests Executed.\n")
end