-- scripts/resolvers/skill_resolver.lua
local BaseResolver = require("resolvers/base_resolver")

local SkillResolver = Class(BaseResolver, function(self, defs)
    BaseResolver._ctor(self, defs)
end)

function SkillResolver:GetSkillDef(id)
    return self:GetDef(id)
end

function SkillResolver:GetAllSkillIds()
    return self:GetAllIds()
end

function SkillResolver:IsToggleSkill(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.is_toggle or false
end

function SkillResolver:GetSkillName(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.name or skill_id
end

function SkillResolver:GetSkillRange(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.range or nil
end

return SkillResolver
