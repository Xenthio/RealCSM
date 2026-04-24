-- lua/autorun/realcsm_shared.lua
-- Runs on BOTH client and server on every map load.
-- Handles: net string registration, the PlayerInitialSpawn full-load trick.

RealCSM = RealCSM or {}

-- Send module files to clients (needed for cl_init.lua and realcsm_client.lua includes).
if SERVER then
	AddCSLuaFile("realcsm/convars.lua")
	AddCSLuaFile("realcsm/util.lua")
	AddCSLuaFile("realcsm/rtt.lua")
	AddCSLuaFile("realcsm/skyboxfix.lua")
end

-- ── Net strings (server registers, client just receives) ────────────────────
if SERVER then
	util.AddNetworkString("RealCSMPlayerSpawnedFully")  -- tell client they are fully in
	util.AddNetworkString("RealCSMKillClientShadows")   -- tell client to remove fp shadow ent
	util.AddNetworkString("RealCSMHasLightEnv")         -- broadcast light_environment presence
	util.AddNetworkString("RealCSMPropWakeup")          -- client→server: please wake props
	util.AddNetworkString("RealCSMReloadLightmaps")     -- server→client: redownload lightmaps
	util.AddNetworkString("RealCSMSunInfo")             -- server→client: broadcast sun angles (StormFox / server-driven)
	util.AddNetworkString("RealCSMEnforceDepthRes")     -- server→client: cap shadow quality
	util.AddNetworkString("RealCSMSunOn")               -- client→server: re-enable static sun
	util.AddNetworkString("RealCSMSunOff")              -- client→server: disable static sun

	AddCSLuaFile("realcsm/spread.lua")
	AddCSLuaFile("realcsm/frustummasks.lua")
end

-- ── PlayerInitialSpawn full-load trick ─────────────────────────────────────
-- Fires "RealCSMPlayerFullLoad" once the player's first real SetupMove runs,
-- meaning they are properly in-game (not just spawned in the void).
hook.Add("PlayerInitialSpawn", "RealCSMFullLoadSetup", function(ply)
	hook.Add("SetupMove", ply, function(self, mvply, _, cmd)
		if self == mvply and not cmd:IsForced() then
			hook.Run("RealCSMPlayerFullLoad", self)
			hook.Remove("SetupMove", self)
			if SERVER then
				net.Start("RealCSMPlayerSpawnedFully")
				net.Send(mvply)
			end
		end
	end)
end)
