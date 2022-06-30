-- Shitty solution to have a shadow for the player
CreateConVar( "csm_debug_pseudoplayer", 0,  false, false )

AddCSLuaFile()
DEFINE_BASECLASS( "base_anim" )

ENT.Spawnable = false
ENT.AdminOnly = false

local debug = false


ENT.PrintName = "CSMPLAYERTEST"
ENT.Category = "Editors"
local pseudoweapon

function ENT:Initialize()

    if (CLIENT) then
        RunConsoleCommand("r_flashlightnear", "45")
        self:SetModel(LocalPlayer():GetModel())
        self:SetPos(LocalPlayer():GetPos())
        self:SetPredictable( true )

        weaponmodel = "models/weapons/w_pistol.mdl"
        if LocalPlayer():GetActiveWeapon():IsValid() then
            weaponmodel = LocalPlayer():GetActiveWeapon():GetModel()
        end
        pseudoweapon = ClientsideModel(weaponmodel)

        if !LocalPlayer():GetActiveWeapon():IsValid() then
            pseudoweapon:SetNoDraw( true )
        end
        pseudoweapon:SetPos(self:GetPos())
        pseudoweapon:SetupBones()
        --pseudoweapon:SetAngles(self:GetAngles())
        pseudoweapon:SetMoveType(MOVETYPE_NONE)
        --pseudoweapon:SetParent( self, LocalPlayer():LookupAttachment("weapon" ))



        pseudoweapon:SetPredictable( true )
        --pseudoweapon:SetParent( self, self:LookupBone( "ValveBiped.Anim_Attachment_RH" ))
        pseudoweapon:SetParent( self )
        pseudoweapon:AddEffects( 1 )
        --pseudoweapon:FollowBone( self, self:LookupBone( "ValveBiped.Anim_Attachment_RH" ))
        --self:AddEffects( 1 )


        self:UseClientSideAnimation()
        self:SetupBones()
        for i = 0, 15 do
            self:SetLayerSequence( i, LocalPlayer():GetLayerSequence( i ))
            self:SetLayerCycle( i, LocalPlayer():GetLayerCycle( i ))
            self:SetLayerPlaybackRate( i, LocalPlayer():GetLayerPlaybackRate( i ))
            self:SetLayerDuration( i, LocalPlayer():GetLayerDuration( i ))
            self:SetLayerWeight( i, LocalPlayer():GetLayerWeight( i ))

        end
        self:SetPos(LocalPlayer():GetPos())
    else

        self:UseClientSideAnimation()
        for i = 0, 15 do
            self:AddLayeredSequence( 0, 0 )
        end

        --self:AddGesture(320)
    end
end

function ENT:Think()
    if CLIENT then
        if GetConVar( "csm_localplayershadow" ):GetBool() and LocalPlayer():IsValid() and LocalPlayer():Alive() then

            if LocalPlayer():GetActiveWeapon():IsValid() then
                pseudoweapon:SetModel(LocalPlayer():GetActiveWeapon():GetModel())
                pseudoweapon:SetNoDraw( false )
            end


            --pseudoweapon:SetSkin(LocalPlayer():GetActiveWeapon():GetSkin()) -- why do i need this for shadow casting????
            --pseudoweapon:SetPos(LocalPlayer():GetActiveWeapon():GetPos())
            --pseudoweapon:SetAngles(LocalPlayer():GetActiveWeapon():GetAngles())
            self:SetNoDraw( false )
            if !(debug or GetConVar("csm_debug_pseudoplayer"):GetBool()) then
                if LocalPlayer():GetActiveWeapon():IsValid() then
                    pseudoweapon:SetRenderMode(2)
                    pseudoweapon:SetColor(Color(255,255,255,0))
                end
                self:SetRenderMode(2)
                self:SetColor(Color(255,255,255,0))
                self:SetPos(LocalPlayer():GetPos())
            else
                pseudoweapon:SetRenderMode(0)
                pseudoweapon:SetColor(Color(255,255,255,255))
                self:SetRenderMode(0)
                self:SetColor(Color(255,255,255,255))
                pseudoweapon:SetNoDraw( false )
            end
            self:SetCycle(LocalPlayer():GetCycle())
            self:SetSequence(LocalPlayer():GetSequence())

            --anims = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14}
            --for l, i in ipairs(anims) do
            for i = 0, 15 do
                self:SetLayerSequence( i, LocalPlayer():GetLayerSequence( i ))
                self:SetLayerCycle( i, LocalPlayer():GetLayerCycle( i ))
                --self:SetLayerPlaybackRate( i, LocalPlayer():GetLayerPlaybackRate( i ))
                --self:SetLayerDuration( i, LocalPlayer():GetLayerDuration( i ))
                self:SetLayerWeight( i, LocalPlayer():GetLayerWeight( i ))
            end
            self:SetModel(LocalPlayer():GetModel())

            a = LocalPlayer():GetRenderAngles()
            self:SetAngles(Angle(0,a.y,0))
            --self:AddEffects(LocalPlayer():GetEffects())

            --for i = 0, LocalPlayer():GetSequenceCount() do
                --self:SetLayerSequence( i, LocalPlayer():GetLayerSequence( i ) )
            --end

            for i = 0, LocalPlayer():GetNumPoseParameters() - 1 do
                local flMin, flMax = LocalPlayer():GetPoseParameterRange(i)
                local sPose = LocalPlayer():GetPoseParameterName(i)
                self:SetPoseParameter(sPose, math.Remap(LocalPlayer():GetPoseParameter(sPose), 0, 1, flMin, flMax))
            end

            --self:SetSequence(LocalPlayer():GetSequence())
            --self:SetSequence(LocalPlayer():GetActivity())
            --for i = 0, LocalPlayer():GetBoneCount() - 1 do
                --self:SetBonePosition(i, LocalPlayer():GetBonePosition(i))
            --end
        else
            pseudoweapon:SetNoDraw( true )
            self:SetNoDraw( true )
        end
    end
end

function ENT:OnRemove()
    if CLIENT then
        RunConsoleCommand("r_flashlightnear", "4")
        if LocalPlayer():IsValid() and LocalPlayer():GetActiveWeapon():IsValid() then
            pseudoweapon:Remove()
        end
    end
    --pseudoweapon:Remove()
end