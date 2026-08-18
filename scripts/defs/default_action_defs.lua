local all_actions = {
    {
        id = "NIKKI_SKILL",
        str = "暖暖技能",
        fn = function(act)
            local doer = act.doer
            if doer == nil or not doer.components.nikki_skill then
                return false, "NO_SKILL_COMPONENT"
            end
            local params = act._raw_params
            params.act = act
            params.target = params.target or act.target
            params.pos = params.pos or act:GetActionPoint()
            params.doer = doer
            params.invobject = act.invobject
            return doer.components.nikki_skill:Execute(act._skill_id, params)
        end,
        state = function(inst, act)
            return act._skill_state or "doshortaction"
        end,
        actiondata = {
            stroverridefn = function(act)
                return act._display_name
            end,
        }
    },
    {
        id = "TARGETING",
        str = "瞄准",
        fn = function(act)
            local params = {
                act = act,
                target = act.target,
                pos = type(act.GetActionPoint) == "function" and act:GetActionPoint() or nil,
                doer = act.doer,
                invobject = act.invobject,
            }
            return act.skill_fn and act.skill_fn(act.doer, params, act.skill_def)
        end,
        state = function(inst, act)
            return act.skill_state or "throw"
        end,
        actiondata = {
            stroverridefn = function(act)
                return act.skill_name or GetActionString(act.action.id)
            end,
            -- rmb = true,
        }
    },
}

local component_actions = {
}
return { actions = all_actions, component_actions = component_actions }
