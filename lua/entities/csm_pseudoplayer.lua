-- Shitty solution to have a shadow for the player
CreateConVar( "csm_debug_pseudoplayer", 0,  false, false )
AddCSLuaFile()

ENT.Type 			= "anim"
ENT.PrintName		= "Pseudoplayer"
ENT.Author			= "Xenthio"
ENT.Information		= "For firstperson self shadows with CSM"
ENT.Category		= "Real CSM"

ENT.Spawnable		= false
ENT.AdminSpawnable	= false

local pseudoweapon
local pseudoplayer

function ENT:Initialize()
    RunConsoleCommand("r_flashlightnear", "50")
    if pseudoplayer and pseudoplayer.IsValid() then
        pseudoplayer:Remove()
    end
    if pseudoweapon and pseudoweapon.IsValid() then
        pseudoweapon:Remove()
    end

    print("[Real CSM] - Pseudoplayer Initialised.")
    self:SetModel(LocalPlayer():GetModel())
    self:SetParent(LocalPlayer())
    self:AddEffects( EF_BONEMERGE )
    self:SetPos(LocalPlayer():GetPos())

    self:SetNoDraw( true )

    pseudoplayer = ClientsideModel(LocalPlayer():GetModel())
    pseudoplayer:SetMoveType(MOVETYPE_NONE)
    pseudoplayer:SetParent(self)
    pseudoplayer:AddEffects( EF_BONEMERGE )

    pseudoweapon = ents.CreateClientside( "csm_pseudoweapon" )
    pseudoweapon:Spawn()

    pseudoplayer:SetRenderMode(2)
    pseudoplayer:SetColor(Color(255,255,255,0))

end
function ENT:Think()

    if GetConVar( "csm_localplayershadow" ):GetBool() == false then
        if pseudoplayer then
            pseudoplayer:Remove()
        end
        if pseudoweapon then
            pseudoweapon:Remove()
        end
        self:Remove()
    end
    if LocalPlayer():Alive()  then
        pseudoplayer:SetNoDraw( false )
    else
        pseudoplayer:SetNoDraw( true )
    end
    if LocalPlayer():GetObserverMode() != OBS_MODE_NONE or (LocalPlayer():GetViewEntity() != LocalPlayer()) or LocalPlayer():ShouldDrawLocalPlayer() then
        pseudoplayer:SetNoDraw( true )
    end
    if pseudoplayer:GetModel() != LocalPlayer():GetModel() then
        print("[Real CSM] - Pseudoplayer model changed.")
        self:RemoveEffects( EF_BONEMERGE )
        self:SetModel(LocalPlayer():GetModel())
        self:SetParent(LocalPlayer())
        self:AddEffects( EF_BONEMERGE )

        pseudoplayer:RemoveEffects( EF_BONEMERGE )
        pseudoplayer:SetModel(LocalPlayer():GetModel())
        pseudoplayer:SetParent(self)
        pseudoplayer:AddEffects( EF_BONEMERGE )
    end
    for k = 1, LocalPlayer():GetNumBodyGroups() do
        pseudoplayer:SetBodygroup(k, LocalPlayer():GetBodygroup(k))
    end
end

function ENT:OnRemove()
    RunConsoleCommand("r_flashlightnear", "4")
    if pseudoplayer then
        pseudoplayer:Remove()
    end
    if pseudoweapon then
        pseudoweapon:Remove()
    end
end
-- remove on auto refresh
hook.Add("OnReloaded", "RealCSMOnAutoReloadPseudoplayer", function()
    if pseudoplayer then
        pseudoplayer:Remove()
    end
    if pseudoweapon then
        pseudoweapon:Remove()
    end
    ENT:Remove()
end)
