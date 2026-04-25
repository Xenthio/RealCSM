-- lua/autorun/realcsm_server.lua
-- SERVER ONLY. ConVars, toolmenu, StormFox integration, auto-spawn, net handlers.

if not SERVER then return end

include("realcsm/convars.lua")

-- Ensure new client-only modules are sent to clients on dedicated servers.
AddCSLuaFile("realcsm/depthrange.lua")
AddCSLuaFile("realcsm/skyboxlamp.lua")

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function wakeProps()
	if GetConVar("csm_allowwakeprops"):GetBool() then
		print("[Real CSM] - Radiosity changed, waking up all props.")
		for _, v in ipairs(ents.FindByClass("prop_physics")) do
			v:Fire("wake")
		end
	end
end

local function actualSpawn()
	local ent = ents.Create("edit_csm")
	ent:SetPos(Vector(0, 0, -10000))
	ent:Spawn()
end

local function spawnCSM()
	local spawnEnabled   = GetConVar("csm_spawnalways")
	local envCheckToggle = GetConVar("csm_spawnwithlightenv")
	local lightEnvExists = #ents.FindByClass("light_environment") > 0

	RunConsoleCommand("csm_haslightenv", lightEnvExists and "1" or "0")

	if spawnEnabled:GetBool() and not ents.FindByClass("edit_csm")[1] then
		if envCheckToggle:GetBool() then
			if lightEnvExists then actualSpawn() end
		else
			actualSpawn()
		end
	end

	-- If StormFox drives the sun but auto-spawn is off, keep light_environments on.
	if GetConVar("csm_stormfoxsupport"):GetBool() and not spawnEnabled:GetBool() then
		for _, v in ipairs(ents.FindByClass("light_environment")) do
			v:Fire("turnon")
		end
	end
end

-- ── Net: client requests prop wakeup ────────────────────────────────────────

net.Receive("RealCSMPropWakeup", function(_, ply)
	wakeProps()
end)

-- ── Net: enforce server shadow quality cap on joining clients ───────────────
-- When csm_sv_maxdepthres > 0, tell the client to clamp their depth res.
local function enforceQualityCap(ply)
	local cap = GetConVar("csm_sv_maxdepthres"):GetInt()
	if cap > 0 then
		net.Start("RealCSMEnforceDepthRes")
		net.WriteInt(cap, 16)
		net.Send(ply)
	end
end

-- ── Net: broadcast sun info (for server-driven sun simulation) ──────────────
-- Other addons (e.g. a custom day/night cycle) can call this to push
-- sun angles to all clients without going through the entity NetworkVars.
-- Usage: RealCSM.BroadcastSunInfo(pitch, yaw, roll, brightness)
function RealCSM.BroadcastSunInfo(pitch, yaw, roll, brightness)
	net.Start("RealCSMSunInfo")
	net.WriteFloat(pitch)
	net.WriteFloat(yaw)
	net.WriteFloat(roll)
	net.WriteFloat(brightness or 1.0)
	net.Broadcast()
end

-- ── StormFox2 integration ────────────────────────────────────────────────────

hook.Add("stormfox2.postinit", "RealCSMStormFoxSupport", function()
	RunConsoleCommand("csm_stormfoxsupport", "1")
	StormFox2.Setting.Set("maplight_dynamic",    false)
	StormFox2.Setting.Set("maplight_lightstyle", false)
	StormFox2.Setting.Set("maplight_lightenv",   false)
	for _, v in ipairs(ents.FindByClass("light_environment")) do
		v:Fire("turnoff")
	end
end)

-- ── Auto-spawn hooks ─────────────────────────────────────────────────────────

hook.Add("PostCleanupMap",        "RealCSMCleanup",   spawnCSM)
hook.Add("RealCSMPlayerFullLoad", "RealCSMAutoSpawn", spawnCSM)

hook.Add("RealCSMPlayerFullLoad", "RealCSMQualityCap", function(ply)
	enforceQualityCap(ply)
end)
