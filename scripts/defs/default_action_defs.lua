local all_actions = {
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
