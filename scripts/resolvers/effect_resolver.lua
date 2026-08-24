-- scripts/resolvers/effect_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")

local EffectResolver = Class(BaseResolver, function(self, defs)
    self._resolver_type = "effect"
    BaseResolver._ctor(self, defs)
end)

local function GenerateAuraEffectId(effect_id)
    return "_effect_aura_" .. effect_id
end
-- ============================================================
-- 编译
-- ============================================================
function EffectResolver:OnDefAdded(id, def)
    if def.aura then
        local raw_effect = def.aura.effect
        local aura_effect_id = nil
        if type(raw_effect) == "string" then
            -- 语法糖：字符串直接视为已有的 effect_id，不生成也不注册
            aura_effect_id = raw_effect
        elseif raw_effect ~= nil then
            -- 表格或其他定义：生成新子 ID 并注册
            aura_effect_id = GenerateAuraEffectId(id)
            self:AddDefs({ [aura_effect_id] = raw_effect })
        end
        local aura_cfg = {}
        for k, v in pairs(def.aura) do
            if k ~= "effect" then
                aura_cfg[k] = v
            end
        end
        local old_on_apply = def.on_apply
        def.on_apply = function(inst, context)
            local aura_inst = SpawnPrefab("nikki_aura")
            if aura_inst then
                aura_inst:Attach(inst)
                if aura_cfg.radius and aura_inst.SetRadius then
                    aura_inst:SetRadius(aura_cfg.radius)
                end
                if type(aura_cfg.postinit) == "function" then
                    aura_cfg.postinit(aura_inst)
                end
                if aura_inst.components.nikki_aura then
                    aura_inst.components.nikki_aura:Setup({
                        owner = inst,
                        radius = aura_cfg.radius,
                        pulse_interval = aura_cfg.pulse_interval,
                        exclude_owner = aura_cfg.exclude_owner,
                        selector = aura_cfg.selector,
                        effect_id = aura_effect_id,
                        params = aura_cfg.params,
                        on_enter = aura_cfg.on_enter,
                        on_pulse = aura_cfg.on_pulse,
                        on_exit = aura_cfg.on_exit,
                    })
                end
                -- 将光环实体句柄存入外层 Effect 的生命周期上下文
                context.aura_inst = aura_inst
            end
            if old_on_apply then
                old_on_apply(inst, context)
            end
        end

        local old_on_remove = def.on_remove
        def.on_remove = function(inst, context)
            if context.aura_inst and context.aura_inst:IsValid() then
                context.aura_inst:Remove()
            end
            context.aura_inst = nil
            if old_on_remove then
                old_on_remove(inst, context)
            end
        end

        def.aura = nil
    end
end

-- ============================================================
-- 查询接口
-- ============================================================

function EffectResolver:GetEffectConfig(id)
    local def = self:GetDef(id)
    if not def then
        return nil, 1, "ignore", false
    end
    local max = def.stack and def.stack.max or 1
    local mode = def.stack and def.stack.mode or "ignore"
    return def.duration, max, mode, def.bind_to_state
end

function EffectResolver:HasFn(id)
    local def = self:GetDef(id)
    return def and type(def.fn) == "function"
end

return EffectResolver
