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

local prevclassname = ""

function ENT:Initialize()
    if pseudoweapon then
        pseudoweapon:Remove()
    end

    print("[Real CSM] - Pseudoweapon Initialised.")
    self:SetParent(LocalPlayer():GetActiveWeapon())
    self:AddEffects( EF_BONEMERGE )
    self:SetNoDraw(true)

    pseudoweapon = ClientsideModel("error.mdl")
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

    if LocalPlayer():GetActiveWeapon():IsValid() and pseudoweapon != nil and LocalPlayer():Alive() then
        --if prevclassname != LocalPlayer():GetActiveWeapon():GetClass() or LocalPlayer():GetActiveWeapon():GetModel() != self:GetModel() then
        prevclassname = LocalPlayer():GetActiveWeapon():GetClass()
        self:SetModel(LocalPlayer():GetActiveWeapon():GetModel())
        self:RemoveEffects( EF_BONEMERGE )
        self:SetParent(LocalPlayer():GetActiveWeapon())
        self:AddEffects( EF_BONEMERGE )
        pseudoweapon:SetModel(LocalPlayer():GetActiveWeapon():GetModel())
        pseudoweapon:RemoveEffects( EF_BONEMERGE )
        pseudoweapon:SetParent(self)
        pseudoweapon:AddEffects( EF_BONEMERGE )
        pseudoweapon:SetNoDraw( false )
    else
        pseudoweapon:SetNoDraw( true )
    end

    if (LocalPlayer():GetActiveWeapon():IsValid() and LocalPlayer():GetActiveWeapon():GetWeaponWorldModel() == "") then
        pseudoweapon:SetNoDraw( true )
    end
   -- LocalPlayer():GetActiveWeapon():AddEFlags(EFL_FORCE_CHECK_TRANSMIT)
    --LocalPlayer():GetActiveWeapon():AddEFlags(EFL_IN_SKYBOX)
    --LocalPlayer():GetActiveWeapon():RemoveEFlags(EF_NODRAW)
    --debugoverlay.Text( self:GetPos(), "hello!", 0.001)
    --debugoverlay.Text( LocalPlayer():GetActiveWeapon():GetPos(), "PlyrWepon", 0.001)
    --pseudoweapon:AddEFlags(EFL_FORCE_CHECK_TRANSMIT)
    --pseudoweapon:AddEFlags(EFL_IN_SKYBOX)
    --self:AddEFlags(EFL_FORCE_CHECK_TRANSMIT)
    --self:AddEFlags(EFL_IN_SKYBOX)

    
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
