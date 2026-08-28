-- scripts/utils/nikki_util.lua
local log = require("utils/log")

-- =============================================
-- 效果施加
-- =============================================

--- 给目标施加一个效果（确保目标有 nikki_effect 组件）
-- local function ApplyEffect(target, effect_id, source)
--     if not target or not target:IsValid() then
--         log.warn("[NikkiUtil] ApplyEffect: invalid target")
--         return false
--     end

--     -- 只在服务端执行逻辑
--     if not TheWorld.ismastersim then
--         return false
--     end

--     local effect_comp = target.components.nikki_effect
--     if not effect_comp then
--         target:AddComponent("nikki_effect")
--         effect_comp = target.components.nikki_effect
--         log.debug("[NikkiUtil] Auto-added nikki_effect component to %s", tostring(target))
--     end

--     return effect_comp:Apply(effect_id, source)
-- end


-- local function ToggleEffectLayered(inst, effect_id, remove_all, source)
--     local effect_comp = inst.components.nikki_effect
--     if not effect_comp then return false end

--     -- 从 EffectResolver 获取 max
--     local resolver = ResolverRegistry.Get("effect")
--     if not resolver then return false end
--     local _, max, _, _ = resolver:GetEffectConfig(effect_id)
--     if not max or max <= 1 then
--         -- 退化为普通 toggle
--         if effect_comp:HasEffect(effect_id) then
--             effect_comp:Remove(effect_id, true)
--             return true
--         else
--             return effect_comp:Apply(effect_id, source or inst)
--         end
--     end
--     local layers = effect_comp:GetLayers(effect_id)
--     if layers >= max then
--         effect_comp:Remove(effect_id, remove_all ~= false)
--         return true
--     else
--         return effect_comp:Apply(effect_id, source or inst)
--     end
-- end



-- =============================================
-- 玩家动作执行（模拟鼠标点击）
-- =============================================

--- 执行一次鼠标点击动作（会走向目标，发送RPC）
local function PerformClickAction(inst, action, target, is_right)
    local pc = inst.components.playercontroller
    if not pc or not target or not target:IsValid() then
        return false
    end

    local is_right = (is_right == nil and true) or is_right -- 默认右键

    local target_pos = target:GetPosition()
    local platform, pos_x, pos_z = pc:GetPlatformRelativePosition(target_pos.x, target_pos.z)

    -- 服务端直接执行
    if TheWorld.ismastersim then
        pc:DoAction(BufferedAction(inst, target, action))
        return true
    end

    -- 客户端：有 locomotor 则预览，无则直接发 RPC
    if pc.locomotor ~= nil then
        local act = BufferedAction(inst, target, action)
        act.preview_cb = function()
            if is_right then
                SendRPCToServer(RPC.RightClick,
                    action.code, pos_x, pos_z, target,
                    nil,  -- rotation
                    true, -- isreleased
                    nil,  -- controlmods
                    nil,  -- noforce
                    action.mod_name,
                    platform, platform ~= nil
                )
            else
                SendRPCToServer(RPC.LeftClick,
                    action.code, pos_x, pos_z, target,
                    true, -- isreleased
                    nil,  -- controlmods
                    nil,  -- noforce
                    action.mod_name,
                    platform, platform ~= nil,
                    nil, -- spellbook
                    nil  -- spell_id
                )
            end
        end
        pc:DoAction(act)
    else
        if is_right then
            SendRPCToServer(RPC.RightClick,
                action.code, pos_x, pos_z, target,
                nil, true, nil, nil, action.mod_name,
                platform, platform ~= nil
            )
        else
            SendRPCToServer(RPC.LeftClick,
                action.code, pos_x, pos_z, target,
                true, nil, nil, action.mod_name,
                platform, platform ~= nil,
                nil, nil
            )
        end
    end
    return true
end

-- 便捷函数：执行右键点击
local function PerformRightClickAction(inst, action, target)
    return PerformClickAction(inst, action, target, true)
end

-- 便捷函数：执行左键点击
local function PerformLeftClickAction(inst, action, target)
    return PerformClickAction(inst, action, target, false)
end

-- =============================================
-- 导出
-- =============================================
return {
    -- ApplyEffect = ApplyEffect,
    PerformClickAction = PerformClickAction,
    PerformRightClickAction = PerformRightClickAction,
    PerformLeftClickAction = PerformLeftClickAction,
    -- ToggleEffectLayered = ToggleEffectLayered
}
