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

function NikkiSkill:SetMaxRange(range) self._max_range:set(range or 0) end

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

function NikkiSkill:CastKey(key_code, skills_dict)
    local resolvers = ResolverRegistry.Get(self.inst.prefab)
    if not resolvers or not resolvers.skill then return end

    local needs_server = false
    local params = { key = key_code }

    -- 遍历执行客机预测
    for skill_id, _ in pairs(skills_dict) do
        if resolvers.skill:CheckRequiredTags(self.inst, skill_id, "keys", key_code) then
            -- 这里完美接收双返回值
            local should_proceed, err = resolvers.skill:ExecuteClientFn(self.inst, skill_id, params)
            if should_proceed then
                if resolvers.skill:NeedsServer(skill_id) then
                    needs_server = true
                end
            else
                log.debug("[NikkiSkill] Client rejected skill %s. Reason: %s", skill_id, tostring(err))
            end
        end
    end

    -- 由技能系统亲自决定是否发包
    if needs_server then
        SendModRPCToServer(GetModRPC("NikkiFramework", "CastKey"), key_code)
    end
end

-- 接收来自 UI/Trigger 的直接释放事件
function NikkiSkill:CastSkill(skill_id, params)
    local resolvers = ResolverRegistry.Get(self.inst.prefab)
    if not resolvers or not resolvers.skill then return end

    -- 【1. 客户端拦截】：检查 Tag，不足则直接终止
    if not resolvers.skill:CheckRequiredTags(self.inst, skill_id, "cast", "default") then
        return
    end

    -- 【2. 客机预测】：执行 client_fn 并接收状态码与错误信息
    local should_proceed, err = resolvers.skill:ExecuteClientFn(self.inst, skill_id, params)

    -- 【3. 客机决断】：如果 client_fn 判定失败（return false），直接拦截发包
    if not should_proceed then
        log.debug("[NikkiSkill] UI CastSkill rejected by client_fn '%s'. Reason: %s", skill_id, tostring(err))
        return
    end

    -- 【4. 发包引擎】：客机放行后，交由技能系统决定是否需要发送 RPC
    if resolvers.skill:NeedsServer(skill_id) then
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
