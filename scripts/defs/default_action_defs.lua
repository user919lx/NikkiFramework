local log = require("utils/log")
local all_actions = {
    {
        id = "NIKKI_SKILL",
        str = "暖暖技能",
        fn = function(act)
            local doer = act.doer
            if doer == nil or not doer.components.nikki_skill_caster then
                return false, "NO_SKILL_CASTER_COMPONENT"
            end
            local params = {
                act = act,
                target = act.target,
                pos = act:GetActionPoint(),
                doer = act.doer,
                invobject = act.invobject,
            }
            return doer.components.nikki_skill_caster:Execute(act._skill_id, params)
        end,
        state = function(inst, act)
            local state = "throw"
            if act._skill_state then
                if type(act._skill_state) == "function" then
                    state = act._skill_state(inst, act)
                else
                    state = act._skill_state
                end
            end
            return state
        end,
        actiondata = {
            stroverridefn = function(act)
                return act._display_name or GetActionString(act.action.id)
            end,
            pre_action_cb = function(act)
                if not TheWorld.ismastersim then
                    local skill_id = act._skill_id
                    local pos = act:GetActionPoint()
                    local x = pos and pos.x or nil
                    local z = pos and pos.z or nil
                    SendModRPCToServer(GetModRPC("NikkiFramework", "TryExecuteSkill"),
                        skill_id,
                        act.target,
                        x,
                        z
                    )
                end
            end,
        }
    },
}

local component_actions = {
}
return { actions = all_actions, component_actions = component_actions }
