-- Shitty solution to have a shadow for the player, weapon edition wow
CreateConVar( "csm_debug_pseudoplayer", 0,  false, false )
AddCSLuaFile()

ENT.Type 			= "anim"
ENT.PrintName		= "Pseudoweapon"
ENT.Author			= "Xenthio"
ENT.Information		= "For firstperson self shadows with CSM"
ENT.Category		= "Real CSM"

ENT.Spawnable		= false
ENT.AdminSpawnable	= false

local pseudoweapon

function ENT:Initialize()
    if pseudoweapon then
        pseudoweapon:Remove()
    end

    print("[Real CSM] - Pseudoweapon Initialised.")
    self:SetModel(LocalPlayer():GetActiveWeapon():GetModel())
    self:SetParent(LocalPlayer():GetActiveWeapon())
    self:AddEffects( EF_BONEMERGE )
    self:SetPos(LocalPlayer():GetActiveWeapon():GetPos())

    pseudoweapon = ClientsideModel("models/weapons/w_pistol.mdl")
    pseudoweapon:SetMoveType(MOVETYPE_NONE)
    pseudoweapon:SetParent(self)
    pseudoweapon:AddEffects( EF_BONEMERGE )

    pseudoweapon:SetRenderMode(2)
    pseudoweapon:SetColor(Color(255,255,255,0))
end
function ENT:Think()
    if GetConVar( "csm_localplayershadow" ):GetBool() == false then
        if pseudoweapon then
            pseudoweapon:Remove()
        end
        self:Remove()
    end

    if LocalPlayer():GetActiveWeapon():IsValid() and pseudoweapon != nil then
        pseudoweapon:SetModel(LocalPlayer():GetActiveWeapon():GetModel())
        pseudoweapon:SetNoDraw( false )
    elseif not LocalPlayer():Alive() then
        pseudoweapon:SetNoDraw( true )
    end

    if !LocalPlayer():GetActiveWeapon():IsValid() or (LocalPlayer():GetActiveWeapon():GetWeaponWorldModel() == "") then
        pseudoweapon:SetNoDraw( true )
        self:SetNoDraw( true )
    end

    if pseudoweapon:GetModel() != self:GetModel() then
        self:SetModel(LocalPlayer():GetActiveWeapon():GetModel())
        self:SetParent(LocalPlayer():GetActiveWeapon())
        self:AddEffects( EF_BONEMERGE )
        self:SetPos(LocalPlayer():GetPos())
        pseudoweapon:SetMoveType(MOVETYPE_NONE)
        pseudoweapon:SetParent(self)
        pseudoweapon:AddEffects( EF_BONEMERGE )
    end
end

function ENT:OnRemove()
    if pseudoweapon then
        pseudoweapon:Remove()
    end
end
-- remove on auto refresh
hook.Add("OnReloaded", "RealCSMOnAutoReloadPseudoplayer", function()
    if pseudoweapon then
        pseudoweapon:Remove()
    end
    ENT:Remove()
end)
