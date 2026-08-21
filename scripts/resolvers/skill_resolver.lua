local BaseResolver = require("resolvers/base_resolver")
local log = require("utils/log")

local SkillResolver = Class(BaseResolver, function(self, defs)
    self._resolver_type = "skill"
    self.compiled_wheels = {}
    BaseResolver._ctor(self, defs)
end)


--- AOE 搜索函数工厂
--- @param anchor string "point" | "self" | "dir"
--- @param radius number 圆形搜索半径（已由外部完成缺省回退处理）
--- @param selector table|nil 标签筛选器表 { must_have, must_have_one_of, cant_have }
--- @return function|nil search_fn (inst, pos) -> targets
local function CreateAOESearchFn(anchor, radius, selector)
    -- 1. 无 selector 或为 dir 模式时，不生成搜索函数
    if selector == nil or anchor == "dir" then
        return nil
    end
    -- 2. 闭包外预解析好 Tag 数组
    local must_have        = selector.must_have
    local must_have_one_of = selector.must_have_one_of
    local cant_have        = selector.cant_have
    -- 3. 根据 anchor 生成对应的搜索闭包
    if anchor == "point" then
        local search_radius = radius or 1
        return function(inst, pos)
            if not pos then
                return {}
            end
            local x, z = pos.x, pos.z
            return TheSim:FindEntities(x, 0, z, search_radius, must_have, cant_have, must_have_one_of)
        end
    elseif anchor == "self" then
        local search_radius = radius or 1
        return function(inst, pos)
            if not inst or not inst:IsValid() then
                return {}
            end
            local x, y, z = inst.Transform:GetWorldPosition()
            return TheSim:FindEntities(x, 0, z, search_radius, must_have, cant_have, must_have_one_of)
        end
    end
    return nil
end
-- ==========================================================================
-- 占位回调函数（遵循 reticule.lua 的回调签名）
-- ==========================================================================
-- preset == "self"
local function SelfMouseTargetFn(inst, mousepos)
    if mousepos == nil then
        return nil
    end
    local owner = ThePlayer
    if owner then
        local pos = Vector3(owner.Transform:GetWorldPosition())
        return pos
    end
end
local function SelfUpdatePositionFn(inst, pos, reticule, ease, smoothing, dt)
    local owner = ThePlayer
    if owner then
        reticule.Transform:SetPosition(Vector3(owner.Transform:GetWorldPosition()):Get())
        reticule.Transform:SetRotation(0)
    end
end

-- 3. 朝向锁定 (dir) 占位
local function LineMouseTargetFn(inst, mousepos)
    if mousepos ~= nil then
        local x, y, z = inst.Transform:GetWorldPosition()
        local dx = mousepos.x - x
        local dz = mousepos.z - z
        local l = dx * dx + dz * dz
        if l <= 0 then
            return inst.components.reticule.targetpos
        end
        l = 6.5 / math.sqrt(l)
        return Vector3(x + dx * l, 0, z + dz * l)
    end
end

local function LineUpdatePositionFn(inst, pos, reticule, ease, smoothing, dt)
    reticule.Transform:SetPosition(ThePlayer.Transform:GetWorldPosition())
    local rot1 = reticule:GetAngleToPoint(inst.components.reticule.targetpos)
    if ease and dt then
        local rot = reticule.Transform:GetRotation()
        local drot = ReduceAngle(rot1 - rot)
        rot1 = Lerp(rot, rot + drot, dt * smoothing)
    end
    reticule.Transform:SetRotation(rot1)
end

-- ==========================================================================
-- 预编译
-- ==========================================================================
-- 预编译添加信息
-- reticule 的全局基础默认值（参考 aoetargeting 与 reticule 源码）
local DEFAULT_RETICULE = {
    reticuleprefab = "reticule",
    validcolour = { 1, .75, 0, 1 },
    invalidcolour = { .5, 0, 0, 1 },
    ease = true,
    smoothing = 6.66,
    mouseenabled = true,
}
-- 编译生命周期钩子
function SkillResolver:OnDefAdded(skill_id, def)
    def.targeting = def.targeting or {}
    def.excutor = {} -- 执行时的相关函数
    def.priority = def.priority or 0
    def.range = def.range or 0
    def.radius = def.radius or 0

    local aoe_def = def.aoe
    local is_aoe = aoe_def ~= nil
    def.is_aoe = is_aoe

    -- 瞄准器相关配置流程
    local reticule = {}
    for k, v in pairs(DEFAULT_RETICULE) do
        reticule[k] = v
    end
    if is_aoe then
        local anchor = aoe_def.anchor or "point"
        local radius = aoe_def.radius or (anchor ~= "point" and def.range) or 1
        if aoe_def.selector then
            local search_fn = CreateAOESearchFn(anchor, radius, aoe_def.selector)
            def.excutor.search_fn = search_fn
            reticule.search_fn = search_fn
        end
        -- 补全瞄准器配置
        reticule.radius = radius
        reticule.reticuleprefab = "nikki_reticule"
        reticule.pingprefab = "nikki_reticule_ping"
        if anchor == "point" then
            reticule.shape = "CIRCLE"
        elseif anchor == "self" then
            reticule.shape = "CIRCLE"
            reticule.mousetargetfn = SelfMouseTargetFn
            reticule.updatepositionfn = SelfUpdatePositionFn
        elseif anchor == "dir" then
            reticule.shape = "ARROW"
            -- reticule.shape_param = 2
            reticule.mousetargetfn = LineMouseTargetFn
            reticule.updatepositionfn = LineUpdatePositionFn
        end
    end
    local user_reticule = def.targeting.reticule
    if user_reticule then
        for k, v in pairs(user_reticule) do
            reticule[k] = v
        end
    end
    def.targeting.reticule = reticule
end

-- ============================================================
-- 属性查询
-- ============================================================
function SkillResolver:GetPriority(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.priority or 0
end

--- 获取射程范围
function SkillResolver:GetRange(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.range or nil
end

--- 获取基础冷却时间
function SkillResolver:GetCooldown(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.cd or 0
end

--- 获取动作定义
function SkillResolver:GetActionDef(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.action or nil
end

--- 获取瞄准配置定义
function SkillResolver:GetTargetingDef(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.targeting or nil
end

--- 查询指定技能是否已编译轮盘配置
function SkillResolver:IsSpellItem(skill_id)
    local def = self:GetDef(skill_id)
    return def and def.is_aoe == true or false
end

-- ============================================================
-- 3. 施法装配
-- ============================================================
--- 根据活跃技能列表过滤并提取可展示在轮盘/施法书中的技能 ID 列表
---@param skill_ids string[] 当前活跃技能 ID 数组
---@return string[] 适用于轮盘展示的技能 ID 列表
function SkillResolver:FilterSpellIds(skill_ids)
    if not skill_ids or #skill_ids == 0 then
        return {}
    end
    local valid_items = {}
    for _, skill_id in ipairs(skill_ids) do
        if self:IsSpellItem(skill_id) then
            table.insert(valid_items, skill_id)
        end
    end
    table.sort(valid_items, function(a, b)
        local pa = self:GetPriority(a)
        local pb = self:GetPriority(b)
        if pa == pb then
            return a < b
        end
        return pa > pb
    end)
    return valid_items
end

--- 构建供 Spell 使用的数据条目
--- @param skill_id string 技能 ID
--- @return table item 供 spellbook组件 使用的条目
function SkillResolver:_BuildSpellItem(skill_id)
    local def = self:GetDef(skill_id)
    local item = {
        skill_id = skill_id,
        priority = def.priority or 0
    }
    if def then
        local name = self:GetDisplayName(skill_id)
        local targeting_def = def.targeting or {}
        local exutor = def.excutor or {}
        local action_def = def.action or {}
        item.onselect = function(spell_caster)
            if not spell_caster.components.spellbook or not spell_caster.components.aoetargeting then
                log.error("[SkillResolver] Spell caster entity does not have required components for skill '%s'",
                    tostring(skill_id))
                return
            end
            spell_caster.components.spellbook:SetSpellName(name)
            if def.is_aoe then
                spell_caster._nikki_aoe_state = action_def.state
                local should_repeat_cast_fn = nil
                if targeting_def.should_repeat_cast_fn then
                    should_repeat_cast_fn = function(caster, doer)
                        return targeting_def.should_repeat_cast_fn(doer)
                    end
                end
                spell_caster.components.aoetargeting:SetAllowWater(targeting_def.allow_water or false)
                spell_caster.components.aoetargeting:SetDeployRadius(targeting_def.deploy_radius)
                spell_caster.components.aoetargeting:SetShouldRepeatCastFn(should_repeat_cast_fn)
                spell_caster.components.aoetargeting:SetReticule(targeting_def.reticule)
                if TheWorld.ismastersim then
                    spell_caster.components.aoetargeting:SetTargetFX(targeting_def.target_fx)
                    spell_caster.components.spellbook:SetSpellFn(nil)
                    spell_caster.components.aoespell:SetSpellFn(function(caster, doer, pt)
                        local params = {
                            pos = pt
                        }
                        if exutor.search_fn then
                            local targets = exutor.search_fn(doer, pt)
                            params.targets = targets
                        end
                        local caster_comp = doer.components.nikki_skill_caster
                        if caster_comp then
                            return caster_comp:Execute(skill_id, params)
                        end
                        caster._nikki_aoe_state = nil
                        return false, "NO_CASTER_COMP"
                    end)
                end
            end
        end
    end
    return item
end

--- 批量构建供 spellbook组件 使用的 Items 数组（保持原数组顺序）
---@param skill_ids string[] 有序技能 ID 列表
---@return table[] items  用于spellbook组件 SetItems的数组
function SkillResolver:BuildSpellItemsByIds(skill_ids)
    if not skill_ids or #skill_ids == 0 then
        return {}
    end
    local items = {}
    for order, skill_id in ipairs(skill_ids) do
        local item = self:_BuildSpellItem(skill_id)
        if item then
            table.insert(items, item)
        end
    end
    return items
end

return SkillResolver
