local TIMEOUT = 2

local function OnRemoveCleanupTargetFX(inst)
    if inst.sg.statemem.targetfx ~= nil then
        if inst.sg.statemem.targetfx.KillFX ~= nil then
            inst.sg.statemem.targetfx:RemoveEventCallback("onremove", OnRemoveCleanupTargetFX, inst)
            inst.sg.statemem.targetfx:KillFX()
        else
            inst.sg.statemem.targetfx:Remove()
        end
    end
end

local states = {
    State {
        name = "nikki_castspell",
        tags = { "doing", "busy", "canrotate" },

        onenter = function(inst)
            if inst.components.playercontroller ~= nil then
                inst.components.playercontroller:Enable(false)
            end
            inst.AnimState:PlayAnimation("staff_pre")
            inst.AnimState:PushAnimation("staff", false)
            inst.components.locomotor:Stop()

            local buffaction = inst:GetBufferedAction()
            local caster = buffaction ~= nil and buffaction.invobject or nil
            log.debug("nikki_castspell caster: %s", tostring(caster))
            local colour = (caster ~= nil and caster.fxcolour) or { 1, 1, 1 }

            local is_riding = inst.components.rider ~= nil and inst.components.rider:IsRiding()
            inst.sg.statemem.stafffx = SpawnPrefab(is_riding and "staffcastfx_mount" or "staffcastfx")
            if inst.sg.statemem.stafffx ~= nil then
                inst.sg.statemem.stafffx.entity:SetParent(inst.entity)
                inst.sg.statemem.stafffx:SetUp(colour)
            end

            inst.sg.statemem.stafflight = SpawnPrefab("staff_castinglight")
            if inst.sg.statemem.stafflight ~= nil then
                inst.sg.statemem.stafflight.Transform:SetPosition(inst.Transform:GetWorldPosition())
                inst.sg.statemem.stafflight:SetUp(colour, 1.9, .33)
            end

            if caster ~= nil and caster.components.aoetargeting ~= nil and buffaction ~= nil then
                inst.sg.statemem.targetfx = caster.components.aoetargeting:SpawnTargetFXAt(buffaction:GetDynamicActionPoint())
                if inst.sg.statemem.targetfx ~= nil then
                    inst.sg.statemem.targetfx:ListenForEvent("onremove", OnRemoveCleanupTargetFX, inst)
                end
            end

            if caster ~= nil then
                inst.sg.statemem.castsound = caster.skin_castsound or caster.castsound or "dontstarve/wilson/use_gemstaff"
                inst.sg.statemem.castsoundparams = caster.castsoundparams or nil
            else
                inst.sg.statemem.castsound = "dontstarve/wilson/use_gemstaff"
                inst.sg.statemem.castsoundparams = nil
            end
        end,

        timeline =
        {
            FrameEvent(13, function(inst)
                if inst.sg.statemem.castsoundparams ~= nil then
                    inst.SoundEmitter:PlaySoundWithParams(inst.sg.statemem.castsound, inst.sg.statemem.castsoundparams)
                else
                    inst.SoundEmitter:PlaySound(inst.sg.statemem.castsound)
                end
            end),
            FrameEvent(53, function(inst)
                if inst.sg.statemem.targetfx ~= nil then
                    if inst.sg.statemem.targetfx:IsValid() then
                        OnRemoveCleanupTargetFX(inst)
                    end
                    inst.sg.statemem.targetfx = nil
                end
                inst.sg.statemem.stafffx = nil    -- Can't be cancelled anymore
                inst.sg.statemem.stafflight = nil -- Can't be cancelled anymore
                inst:PerformBufferedAction()
            end),
            FrameEvent(69, function(inst)
                inst.sg:RemoveStateTag("busy")
                if inst.components.playercontroller ~= nil then
                    inst.components.playercontroller:Enable(true)
                end
            end),
        },

        events =
        {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        onexit = function(inst)
            if inst.components.playercontroller ~= nil then
                inst.components.playercontroller:Enable(true)
            end
            if inst.sg.statemem.stafffx ~= nil and inst.sg.statemem.stafffx:IsValid() then
                inst.sg.statemem.stafffx:Remove()
            end
            if inst.sg.statemem.stafflight ~= nil and inst.sg.statemem.stafflight:IsValid() then
                inst.sg.statemem.stafflight:Remove()
            end
            if inst.sg.statemem.targetfx ~= nil and inst.sg.statemem.targetfx:IsValid() then
                OnRemoveCleanupTargetFX(inst)
            end
        end,
    },
}

local client_states = {
    State {
        name = "nikki_castspell",
        tags = { "doing", "busy", "canrotate" },
        server_states = { "nikki_castspell" },

        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("staff_pre")
            inst.AnimState:PushAnimation("staff_lag", false)

            inst:PerformPreviewBufferedAction()
            inst.sg:SetTimeout(TIMEOUT)
        end,

        onupdate = function(inst)
            if inst.sg:ServerStateMatches() then
                if inst.entity:FlattenMovementPrediction() then
                    inst.sg:GoToState("idle", "noanim")
                end
            elseif inst.bufferedaction == nil then
                inst.sg:GoToState("idle")
            end
        end,

        ontimeout = function(inst)
            inst:ClearBufferedAction()
            inst.sg:GoToState("idle")
        end,
    },
}

return {
    sgs = {
        wilson = states,
        wilson_client = client_states,
    },
}