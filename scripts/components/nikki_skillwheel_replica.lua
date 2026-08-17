-- scripts/components/nikki_skill_replica.lua
local log = require("utils/log")
local ResolverRegistry = require("nikki_resolver_registry")

local NikkiSkill = Class(function(self, inst)
    self.inst = inst
    self._max_range = net_float(inst.GUID, "skill._max_range", "skill_maxrangedirty")
    self._max_range:set(0)
    if not TheWorld.ismastersim then
        inst:ListenForEvent("skill_maxrangedirty", function()
            inst:PushEvent("skill_max_range_dirty", { max_range = self:GetMaxRange() })
        end)
    end
end)

function NikkiSkill:SetMaxRange(range)
    self._max_range:set(range or 0)
end

function NikkiSkill:GetMaxRange()
    if self.inst.components.nikki_skill ~= nil then
        return self.inst.components.nikki_skill.max_range
    else
        return self._max_range:value()
    end
end

-- ========================================================
-- 客机执行与 RPC 发送引擎
-- ========================================================

function NikkiSkill:CastKey(key_code, skills_dict, params)
    local resolver = ResolverRegistry.Get("skill")
    if not resolver then return end

    params = params or { key = key_code }
    local skills_to_send = {}

    for skill_id, _ in pairs(skills_dict) do
        if resolver:CheckRequiredTags(self.inst, skill_id, "keys", key_code) then
            local should_proceed, err = self.inst.components.nikki_skill:ExecuteClientFn(skill_id, params)
            if should_proceed then
                if resolver:NeedsServer(skill_id) then
                    table.insert(skills_to_send, skill_id)
                end
            else
                log.debug("[NikkiSkill] Client rejected skill %s. Reason: %s", skill_id, tostring(err))
            end
        end
    end

    for _, skill_id in ipairs(skills_to_send) do
        local target = params.target
        local has_pos = false
        local px, pz = 0, 0
        if params.pos then
            has_pos = true
            px = params.pos.x
            pz = params.pos.z
        end
        SendModRPCToServer(GetModRPC("NikkiFramework", "CastSkill"), skill_id, target, has_pos, px, pz)
    end
end

function NikkiSkill:CastSkill(skill_id, params)
    local resolver = ResolverRegistry.Get("skill")
    if not resolver then return end

    if not resolver:CheckRequiredTags(self.inst, skill_id, "cast", "default") then
        return
    end

    local should_proceed, err = self.inst.components.nikki_skill:ExecuteClientFn(skill_id, params)

    if should_proceed == false then
        log.debug("[NikkiSkill] UI CastSkill rejected by client_fn '%s'. Reason: %s", skill_id, tostring(err))
        return
    end

    if resolver:NeedsServer(skill_id) then
        local target = nil
        local has_pos = false
        local px, pz = 0, 0
        if params and type(params) == "table" then
            target = params.target
            if params.pos then
                has_pos = true
                px = params.pos.x
                pz = params.pos.z
            end
        end
        SendModRPCToServer(GetModRPC("NikkiFramework", "CastSkill"), skill_id, target, has_pos, px, pz)
    end
end

return NikkiSkill
