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
        local aura_effect_id = GenerateAuraEffectId(id)
        self:AddDefs({ [aura_effect_id] = def.aura.effect })
        local aura_cfg = {}
        for k, v in pairs(def.aura) do
            if k ~= "effect" then
                aura_cfg[k] = v
            end
        end
        local old_on_apply = def.on_apply
        def.on_apply = function(inst, effect_def, context)
            local aura_inst = SpawnPrefab("nikki_aura")
            if aura_inst then
                aura_inst:Attach(inst)
                aura_inst:SetRange(aura_cfg.radius)
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
                    })
                end
                -- 将光环实体句柄存入外层 Effect 的生命周期上下文
                context.aura_inst = aura_inst
            end
            if old_on_apply then
                old_on_apply(inst, effect_def, context)
            end
        end
        local old_on_remove = def.on_remove
        def.on_remove = function(inst, effect_def, context)
            if context.aura_inst and context.aura_inst:IsValid() then
                context.aura_inst:Remove()
            end
            context.aura_inst = nil
            if old_on_remove then
                old_on_remove(inst, effect_def, context)
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
    if not def then return nil, 1, "refresh", false end
    local max = def.stack and def.stack.max or 1
    local mode = def.stack and def.stack.mode or "refresh"
    return def.duration, max, mode, def.bind_to_state
end

function EffectResolver:HasFn(id)
    local def = self:GetDef(id)
    return def and type(def.fn) == "function"
end

return EffectResolver
