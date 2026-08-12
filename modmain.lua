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



-- 废除 CastKey RPC，统一使用 CastSkill
AddModRPCHandler("NikkiFramework", "CastSkill", function(player, skill_id, target, has_pos, px, pz)
    -- 统一网关：必须先经过 nikki_skill_trigger 拦截并记录上下文！
    if player and player.components.nikki_skill_trigger then
        local params = {}
        if target then params.target = target end
        if has_pos then params.pos = GLOBAL.Vector3(px, 0, pz) end
        -- 交给 Trigger 缓存目标，再由其转发给 Skill
        player.components.nikki_skill_trigger:CastSkill(skill_id, params)
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
    AddClassPostConstruct("widgets/statusdisplays", function(self)
        if not self.owner:HasTag("nikki_framework") then return end
        -- 可调参数
        local DEFAULT_BADGE_SPACING = 62 -- 默认徽章间距
        local VERTICAL_MARGIN = 13        -- 徽章底部到按钮的边距（逻辑像素）

        -- 私有成员
        self._nikki_badges = {}
        self._nikki_range_btn = nil

        -- ============================================================
        -- 私有方法：计算布局参数（基于 brain/stomach/heart 三个核心徽章）
        -- ============================================================
        function self:_Nikki_CalcLayoutParams()
            local core_badges = {
                "brain",
                "stomach",
                "heart",
            }

            -- 按 Y 分组
            local groups = {}
            for _, badge in ipairs(core_badges) do
                local badge_widget = self[badge]
                if badge_widget and badge_widget:IsVisible() then
                    local x, y, _ = badge_widget:GetPositionXYZ()
                    if not groups[y] then
                        groups[y] = {}
                    end
                    log.debug("_Nikki_CalcLayoutParams: badge %s at (%.2f, %.2f)", badge, x, y)
                    table.insert(groups[y], x)
                end
            end

            -- 没有任何徽章 → 返回默认值
            if GLOBAL.next(groups) == nil then
                return DEFAULT_BADGE_SPACING, 0, 0
            end

            -- 找到数量最多的那一行（主行）
            local main_y = 0
            local max_count = 0
            for y, xs in pairs(groups) do
                if #xs > max_count then
                    max_count = #xs
                    main_y = y
                end
            end

            local main_xs = groups[main_y]
            table.sort(main_xs)
            local leftmost_x = main_xs[1]

            local spacing
            if #main_xs >= 2 then
                spacing = math.abs(main_xs[2] - main_xs[1])
                log.debug(
                    "_Nikki_CalcLayoutParams: main_xs[2]=%.2f, #main_xs=%d, spacing=%.2f, leftmost_x=%.2f, main_y=%.2f",
                    main_xs[2], #main_xs, spacing, leftmost_x, main_y)
            else
                spacing = DEFAULT_BADGE_SPACING
            end

            local start_x = leftmost_x - spacing

            return spacing, start_x, main_y
        end

        -- ============================================================
        -- 私有方法：确保范围按钮已创建
        -- ============================================================
        function self:_Nikki_EnsureRangeButton()
            if self._nikki_range_btn then
                return
            end
            local TEMPLATES = require("widgets/redux/templates")
            local NikkiClientSettings = require("nikki_client_settings")
            local init_checked = NikkiClientSettings.Get("show_range")
            self._nikki_range_btn = self:AddChild(TEMPLATES.StandardCheckbox(
                function()
                    local new_state = NikkiClientSettings.Toggle("show_range")
                    local owner = self.owner
                    if owner and owner:IsValid() then
                        owner:PushEvent("skill_range_toggle_changed", { new_state = new_state })
                    end
                    return new_state
                end,
                64,
                init_checked,
                "切换射程指示器"
            ))
        end

        -- ============================================================
        -- 私有方法：更新范围按钮
        -- ============================================================
        function self:_Nikki_UpdateRangeButton()
            local owner = self.owner
            if not (owner and owner:IsValid()) then
                return
            end
            local range = owner.replica.nikki_skill and owner.replica.nikki_skill:GetMaxRange() or 0
            if range <= 0 then
                if self._nikki_range_btn then
                    self._nikki_range_btn:Hide()
                end
                return
            end
            -- 需要显示 → 确保按钮已创建
            self:_Nikki_EnsureRangeButton()
            local _, start_x, y = self:_Nikki_CalcLayoutParams()

            -- 获取原生徽章的高度（优先使用 brain，因为它在所有模式下都存在）
            local badge_height = 80
            local native_badge = self.brain
            if native_badge then
                local anim_widget = native_badge.anim or native_badge.circular_meter
                if anim_widget and anim_widget.GetBoundingBoxSize then
                    local w, h = anim_widget:GetBoundingBoxSize()
                    if h and h > 0 then
                        badge_height = h
                    end
                end
            end
            local hud_scale = TheFrontEnd:GetHUDScale() or 1
            -- 垂直偏移 = 半高 + 边距 * hud_scale
            local offset = badge_height / 2 + VERTICAL_MARGIN * hud_scale

            self._nikki_range_btn:SetPosition(start_x, y - offset, 0)
            self._nikki_range_btn:Show()
        end

        -- ============================================================
        -- 私有方法：完整刷新徽章
        -- ============================================================
        function self:_Nikki_RefreshBadges()
            local owner = self.owner
            if not (owner and owner:IsValid() and owner.replica and owner.replica.nikki_state) then
                return
            end

            -- 1. 计算布局参数
            local spacing, start_x, y = self:_Nikki_CalcLayoutParams()

            -- 2. 获取徽章 ID 列表
            local raw_ids = owner.replica.nikki_state:GetBadges()
            local res_ids = {}
            if type(raw_ids) == "table" then
                res_ids = raw_ids
            elseif type(raw_ids) == "string" and raw_ids ~= "" then
                res_ids = { raw_ids }
            end

            local count = #res_ids
            local NikkiBadge = require("widgets/nikki_badge")
            -- 3. 更新徽章（使用 Open/Close）
            for i = 1, count do
                local badge = self._nikki_badges[i]
                if not badge then
                    badge = self:AddChild(NikkiBadge(owner))
                    self._nikki_badges[i] = badge
                end
                local pos_x = start_x - spacing * (i - 1)
                badge:SetPosition(pos_x, y, 0)
                badge:SetRes(res_ids[i])
            end
            for i = count + 1, #self._nikki_badges do
                if self._nikki_badges[i] then
                    self._nikki_badges[i]:Close()
                end
            end
        end

        -- ============================================================
        -- 初始化：延迟一帧执行
        -- ============================================================
        self.inst:DoTaskInTime(1, function()
            self:_Nikki_RefreshBadges()
            self:_Nikki_UpdateRangeButton()
        end)
        -- ============================================================
        -- 事件监听
        -- ============================================================
        if self.owner and self.owner:IsValid() then
            -- 徽章列表变化 → 完整刷新（徽章 + 按钮位置）
            self.inst:ListenForEvent("nikki_state_dirty", function()
                self:_Nikki_RefreshBadges()
            end, self.owner)
            -- 射程范围变化 → 只刷按钮显隐（不改变位置）
            self.inst:ListenForEvent("skill_max_range_dirty", function()
                self:_Nikki_UpdateRangeButton()
            end, self.owner)
        end
    end)
end

if not is_debug_mode then
    return
end
