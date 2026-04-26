AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")
DEFINE_BASECLASS("base_edit_csm")

include("realcsm/convars.lua")

local function findEntity(class)
	return ents.FindByClass(class)[1]
end

-- ── Sun control ───────────────────────────────────────────────────────────────

function ENT:SUNOff()
	-- TODO: This is a serverside Fire("turnoff") on light_environment, which means ALL clients
	-- lose the static sun simultaneously. There's no per-client way to toggle it in Source.
	-- This means on a multiplayer server, if one client disables CSM via csm_enabled, it turns
	-- off the sun for *everyone*. There's no clean fix for this without engine-level changes.
	-- A partial workaround would be to not touch light_environment at all and instead rely purely
	-- on the projected textures overriding the static lighting, but that changes the look significantly.
	for _, v in ipairs(ents.FindByClass("light_environment")) do
		v:Fire("turnoff")
	end
end

function ENT:SUNOn()
	for _, v in ipairs(ents.FindByClass("light_environment")) do
		v:Fire("turnon")
	end
	net.Start("RealCSMReloadLightmaps")
	net.Broadcast()
end

-- ── Initialize ────────────────────────────────────────────────────────────────

function ENT:Initialize()
	-- Kill any existing CSM entity (only one should ever exist).
	for _, v in ipairs(ents.FindByClass("edit_csm")) do
		if v ~= self then
			net.Start("RealCSMKillClientShadows")
			net.Broadcast()
			v:Remove()
		end
	end

	self:SetModel("models/maxofs2d/cube_tool.mdl")
	self:SetMaterial("csm/edit_csm")

	-- Set network var defaults from BSP light_environment.
	-- NikNaks is client-only so this just sets fallback defaults;
	-- the client's Initialize will override with accurate BSP values if NikNaks is present.
	local getENVSunColour = GetConVar("csm_getENVSUNcolour"):GetBool()
	local mapName         = game.GetMap()
	local envSun          = findEntity("env_sun")

	if getENVSunColour and mapName ~= "gm_construct" and IsValid(envSun) then
		self:SetSunColour(envSun:GetColor():ToVector())
	else
		self:SetSunColour(Vector(1.0, 0.90, 0.80))
	end
	self:SetSunBrightness(1000)

	self:SetSizeNear(128.0)
	self:SetSizeMid(1024.0)
	self:SetSizeFar(8192.0)
	self:SetSizeFurther(65536.0)

	self:SetUseMapSunAngles(true)
	self:SetUseSkyFogEffects(false)
	self:SetOrientation(135.0)
	self:SetMaxAltitude(50.0)
	self:SetTime(0.5)
	self:SetHeight(32768)
	self:SetSunNearZ(25000.0)
	self:SetSunFarZ(49152.0)

	self:SetRemoveStaticSun(true)
	self:SetHideRTTShadows(true)

	self:SetEnableOffsets(false)
	self:SetOffsetPitch(0)
	self:SetOffsetYaw(0)
	self:SetOffsetRoll(0)

	-- Check for light_environment and optionally warn.
	local hasLightEnv = #ents.FindByClass("light_environment") > 0
	RunConsoleCommand("csm_haslightenv", hasLightEnv and "1" or "0")

	-- Broadcast sky_camera position to clients (not networked by default).
	local skyCam = ents.FindByClass("sky_camera")[1]
	if IsValid(skyCam) then
		net.Start("RealCSMSkyCameraPos")
		net.WriteVector(skyCam:GetPos())
		net.Broadcast()
	end

	if hasLightEnv then
		self:SetRemoveStaticSun(true)
		-- Broadcast to all clients so their csm_haslightenv updates.
		net.Start("RealCSMHasLightEnv")
		net.WriteBool(hasLightEnv)
		net.Broadcast()
	else
		self:SetRemoveStaticSun(false)
		-- Warn will fire client-side via timer in cl_init.lua.
	end

	-- Spawn fp-shadow controller if allowed.
	if GetConVar("csm_allowfpshadows_old"):GetBool() then
		self._fpShadowController = ents.Create("csm_pseudoplayer_old")
		if IsValid(self._fpShadowController) then
			self._fpShadowController:Spawn()
		end
	end

	-- Turn off static sun if configured.
	if self:GetRemoveStaticSun() then
		if GetConVar("csm_legacydisablesun"):GetInt() == 1 then
			RunConsoleCommand("r_lightstyle", "0")
			RunConsoleCommand("r_ambientlightingonly", "1")
			net.Start("RealCSMReloadLightmaps")
			net.Broadcast()
		else
			self:SUNOff()
		end
		RunConsoleCommand("r_radiosity", GetConVar("csm_propradiosity"):GetString())
	end

	BaseClass.Initialize(self)
end

-- ── OnRemove ──────────────────────────────────────────────────────────────────

function ENT:OnRemove()
	if IsValid(self._fpShadowController) then
		self._fpShadowController:Remove()
	end

	if GetConVar("csm_spawnalways"):GetInt() == 0 then
		if self:GetRemoveStaticSun() then
			RunConsoleCommand("r_radiosity", "4")
			if GetConVar("csm_legacydisablesun"):GetInt() == 1 then
				RunConsoleCommand("r_ambientlightingonly", "0")
				RunConsoleCommand("r_lightstyle", "-1")
				net.Start("RealCSMReloadLightmaps")
				net.Broadcast()
			else
				self:SUNOn()
			end
		end
	end
end




-- Sun on/off driven by clients via net messages. More reliable than watching
-- csm_enabled serverside (client convar, async, not usable on dedicated).
-- Each CSM entity listens and acts on its own Fire(turnon/turnoff) state.
net.Receive("RealCSMSunOn", function(_, ply)
	for _, ent in ipairs(ents.FindByClass("edit_csm")) do
		if ent:GetRemoveStaticSun() then
			ent:SUNOn()
		end
	end
end)

net.Receive("RealCSMSunOff", function(_, ply)
	for _, ent in ipairs(ents.FindByClass("edit_csm")) do
		if ent:GetRemoveStaticSun() then
			ent:SUNOff()
		end
	end
end)

-- Watch csm_enabled serverside so SUNOn/SUNOff fire when the client toggles the checkbox.
-- NOTE: csm_enabled is a client convar. On dedicated servers GetConVar returns nil.
-- Kept as a safety net for single-player; real work is done via RealCSMSun{On,Off} net msgs.
function ENT:Think()
	self:NextThink(CurTime() + 0.1)
	return true
end
