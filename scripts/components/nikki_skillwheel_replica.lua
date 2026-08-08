-- scripts/components/nikki_skillwheel_replica.lua
local ResolverRegistry = require("nikki_resolver_registry")
local log = require("utils/log")

local NikkiSkillWheel = Class(function(self, inst)
    self.inst = inst
end)

-- ==========================================================
-- 纯粹的提取口：委托 Resolver 的工厂方法生成 Items 列表
-- ==========================================================
function NikkiSkillWheel:GetWheelItems()
    local user = self.inst
    local resolvers = ResolverRegistry.Get(user.prefab)
    if not resolvers or not resolvers.skill then return {} end

    local items = {}
    local order = 1

    local target_skill_ids = {}
    if user.replica and user.replica.nikki_state then
        target_skill_ids = user.replica.nikki_state:GetSkills()
    end

    for _, skill_id in ipairs(target_skill_ids) do
        -- 1. 快速短路：优先确认是否为轮盘技能，避免非轮盘技能触发多余的 Tag 校验和 Debug 日志
        if resolvers.skill:IsWheelSkill(skill_id) then
            -- 2. 确认是轮盘技能后，再进行 Tag 条件判定
            if resolvers.skill:CheckRequiredTags(user, skill_id, nil, nil) then
                -- 3. 调用工厂生产 Item
                local item = resolvers.skill:BuildWheelItem(skill_id, user, order)
                if item then
                    table.insert(items, item)
                    order = order + 1
                end
            end
        end
    end
    return items
end

function NikkiSkillWheel:OpenWheel()
    local inst = self.inst
    if inst.components.nikki_skillwheel then
        inst.components.nikki_skillwheel:OpenWheel()
    else
        local caster = inst.spell_caster
        if caster and caster.components.spellbook then
            caster.components.spellbook:OpenSpellBook(inst)
        end
    end
    return false
end

return NikkiSkillWheel
