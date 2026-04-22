-- lua/entities/edit_csm/init.lua
-- SERVER ONLY. Handles entity lifecycle, sun on/off, fp-shadow controller.

include("realcsm/convars.lua")

local function findEntity(class)
	return ents.FindByClass(class)[1]
end

-- ── Sun control ───────────────────────────────────────────────────────────────

function ENT:SUNOff()
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

	-- Set network var defaults.
	local getENVSunColour = GetConVar("csm_getENVSUNcolour"):GetBool()
	local mapName         = game.GetMap()
	local envSun          = findEntity("env_sun")

	if getENVSunColour and mapName ~= "gm_construct" and IsValid(envSun) then
		self:SetSunColour(envSun:GetColor():ToVector())
	else
		self:SetSunColour(Vector(1.0, 0.90, 0.80))
	end

	-- Brightness: clients will tell us via csm_hashdr, but we default based on
	-- the server's knowledge (listen server has render access; dedicated servers default high).
	self:SetSunBrightness(1000) -- clients will correct via csm_hashdr if needed

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

	if hasLightEnv then
		self:SetRemoveStaticSun(true)
		-- Broadcast to all clients so their csm_haslightenv updates.
		net.Start("RealCSMHasLightEnv")
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
			RunConsoleCommand("r_radiosity", "3")
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
