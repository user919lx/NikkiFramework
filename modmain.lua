PrefabFiles = {
    "nikki_spell_caster",
    "nikki_range_indicator",
}
AddReplicableComponent("nikki_skill_trigger")
AddReplicableComponent("nikki_state")
AddReplicableComponent("nikki_skillwheel")
AddReplicableComponent("nikki_skill")



-- ========================================================
-- 1. 注册服务端 RPC 接收器 (Master Server)
-- ========================================================

-- A. 接收按键触发 (由 Replica 的 CastKey 发送)
AddModRPCHandler("NikkiFramework", "CastKey", function(player, key_code)
    -- 服务端收到客机的按键请求，找到玩家身上的 trigger 组件进行路由分发
    if player and player.components.nikki_skill_trigger then
        player.components.nikki_skill_trigger:CastKey(key_code)
    end
end)

-- B. 接收直接技能触发 (由 Replica 的 CastSkill 发送，附带鼠标坐标/目标等参数)
AddModRPCHandler("NikkiFramework", "CastSkill", function(player, skill_id, target, has_pos, px, pz)
    if player and player.components.nikki_skill then
        local params = {}
        if target then params.target = target end
        if has_pos then params.pos = GLOBAL.Vector3(px, 0, pz) end

        -- 跳过路由，直接让底层执行技能
        player.components.nikki_skill:CastSkill(skill_id, params)
    end
end)

-- ========================================================
-- 2. 注册客户端硬件按键监听 (Client Input)
-- ========================================================

-- 确保只有带客户端的机器（客机、或非专用主机的本地主机）才注册按键
if GLOBAL.TheNet:GetIsClient() or (GLOBAL.TheNet:GetIsServer() and not GLOBAL.TheNet:IsDedicated()) then
    GLOBAL.TheInput:AddKeyHandler(function(key, down)
        -- 只响应按下瞬间
        if not down then return end

        local player = GLOBAL.ThePlayer
        if not player or not player:IsValid() then return end

        -- 屏蔽干扰：如果玩家正在打字聊天、打开控制台或处于 UI 界面，不响应按键
        if GLOBAL.TheFrontEnd:GetActiveScreen() ~= player.HUD then return end

        -- 【核心】：无脑甩锅给 Replica 的 CastKey 去处理查表和客机预测
        if player.replica.nikki_skill_trigger then
            player.replica.nikki_skill_trigger:CastKey(key)
        end
    end)
end


-- 使用 rawget 绕过 strict.lua 检查变量是否存在
if GLOBAL.rawget(GLOBAL, "TheNikkiFramework") == nil then
    -- 使用 rawset 绕过 strict.lua 强制写入全局变量
    local module = GLOBAL.require("nikki_framework_manager")
    GLOBAL.rawset(GLOBAL, "TheNikkiFramework", module)
end
