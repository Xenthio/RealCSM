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
function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

function ENT:Initialize()

    if (CLIENT) then
        RunConsoleCommand("r_flashlightnear", "50")
        self:SetModel(LocalPlayer():GetModel())
        self:SetPos(LocalPlayer():GetPos())
        self:SetPredictable( true )

        weaponmodel = "models/weapons/w_pistol.mdl"
        if LocalPlayer():GetActiveWeapon():IsValid() and (LocalPlayer():GetActiveWeapon():GetWeaponWorldModel() != "") then
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
        --AddOriginToPVS(self:GetPos())
        self:UseClientSideAnimation()
        for i = 0, 16 do
            self:AddLayeredSequence( 0, 0 )
        end

        --self:AddGesture(320)
    end
end

function ENT:Think()
    if CLIENT then
        if GetConVar( "csm_localplayershadow" ):GetBool() and LocalPlayer():IsValid() and LocalPlayer():Alive() then

            if pseudoweapon == nil then
                weaponmodel = "models/weapons/w_pistol.mdl"
                if LocalPlayer():GetActiveWeapon():IsValid() and (LocalPlayer():GetActiveWeapon():GetWeaponWorldModel() != "") then
                    weaponmodel = LocalPlayer():GetActiveWeapon():GetModel()
                end
                pseudoweapon = ClientsideModel(weaponmodel)
                pseudoweapon:SetPos(self:GetPos())
                pseudoweapon:SetupBones()
                pseudoweapon:SetMoveType(MOVETYPE_NONE)
                pseudoweapon:SetPredictable( true )
                pseudoweapon:SetParent( self )
                pseudoweapon:AddEffects( 1 )
                print("uh oh")
            end
            if LocalPlayer():GetActiveWeapon():IsValid() and pseudoweapon != nil then
                pseudoweapon:SetModel(LocalPlayer():GetActiveWeapon():GetModel())
                pseudoweapon:SetNoDraw( false )
            end
            if !LocalPlayer():GetActiveWeapon():IsValid() or (LocalPlayer():GetActiveWeapon():GetWeaponWorldModel() == "") then
                pseudoweapon:SetNoDraw( true )
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

            for k = 1, LocalPlayer():GetNumBodyGroups() do
                self:SetBodygroup(k, LocalPlayer():GetBodygroup(k))
            end
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
            pcall(function() pseudoweapon:SetNoDraw( true ) end)
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


-- https://github.com/Facepunch/garrysmod-issues/issues/861
-- eat shit
-- better idea why dont I just have it always in pvs.
--[[
local parentLookup = {}
local function cacheParents()
    parentLookup = {}
    local tbl = ents.GetAll()
    for i = 1, #tbl do
        local v = tbl[i]
        if v:EntIndex() == -1 then
            local parent = v:GetInternalVariable("m_hNetworkMoveParent")
            local children = parentLookup[parent]
            if !children then children = {}; parentLookup[parent] = children end
            children[#children + 1] = v
        end
    end
end

local function fixChildren(parent, transmit)
    local tbl = parentLookup[parent]
    if tbl then
        for i = 1, #tbl do
            local child = tbl[i]
            if transmit then
                --print("parented " .. tostring(child) .. " to " .. tostring(parent))
                child:SetNoDraw(false)
                child:SetParent(parent)
                fixChildren(child, transmit)
            else
                --print("parent " .. tostring(parent) .. " is dorment. hiding " .. tostring(child))
                child:SetNoDraw(true)
                fixChildren(child, transmit)
            end
        end
    end
end

local lastTime = 0
hook.Add("NotifyShouldTransmit", "testCSMfixCSSS", function(ent, transmit)
    local time = RealTime()
    if lastTime < time then
        cacheParents()
        lastTime = time
    end
    
    fixChildren(ent, transmit)
end)
--]]