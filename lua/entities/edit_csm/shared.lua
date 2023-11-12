-- TODO:
-- - Use a single ProjectedTexture when r_flashlightdepthres is 0 (since there's no shadows then anyway)

AddCSLuaFile()
DEFINE_BASECLASS("base_edit_csm")

--jit.opt.start(2) -- same as -O2
--jit.opt.start("-dce")
--jit.opt.start("hotloop=10", "hotexit=2")
--jit.on()
-- Above are some dumb experiments, don't include them 

ENT.Spawnable = true
ENT.AdminOnly = true

--ENT.Base = "base_edit"
ENT.PrintName = "CSM Editor"
ENT.Category = "Editors"

local sun = {
	direction = Vector(0, 0, 0),
	obstruction = 0,
}
local warnedyet = false
cvar_csm_legacydisablesun = CreateClientConVar(	 "csm_legacydisablesun", 0,  true, false)
cvar_csm_haslightenv = CreateClientConVar(	 "csm_haslightenv", 0,  false, false)
cvar_csm_hashdr = CreateClientConVar(	 "csm_hashdr", 0,  false, false)
cvar_csm_enabled = CreateClientConVar(	 "csm_enabled", 1,  false, false)

CreateClientConVar(	 "csm_update", 1,  false, false)
CreateClientConVar(	 "csm_filter", 0.08,  false, false)
CreateClientConVar(	 "csm_spread_layer_alloctype", 0,  false, false)
CreateClientConVar(	 "csm_spread_layer_reservemiddle", 1,  false, false)


CreateConVar(	 "csm_stormfoxsupport", 0,  FCVAR_ARCHIVE)
CreateConVar(	 "csm_stormfox_brightness_multiplier", 1, FCVAR_ARCHIVE)
CreateConVar(	 "csm_stormfox_coloured_sun", 0, FCVAR_ARCHIVE)
local lightenvs = {ents.FindByClass("light_environment")}
local hasLightEnvs = false

local RemoveStaticSunPrev = false
local HideRTTShadowsPrev = false
local BlobShadowsPrev = false
local ShadowFilterPrev = 1.0
local DepthBiasPrev = 1.0
local SlopeScaleDepthBiasPrev = 1.0
local shadfiltChanged = true
local csmEnabledPrev = false
local useskyandfog = false
local furtherEnabled = false
local furtherEnabledPrev = false
local furtherEnabledShadows = false
local furtherEnabledShadowsPrev = false
local farEnabledShadows = true
local farEnabledShadowsPrev = true
local spreadEnabled = false
local spreadEnabledPrev = false
local spreadSample = 6
local spreadSamplePrev = 6
local spreadLayer = 1
local spreadLayerPrev = 0
local propradiosity = 4
local propradiosityPrev = 4
local perfMode = false
local perfModePrev = false
local fpShadowsPrev = false

local fpshadowcontroller
local fpshadowcontrollerCLIENT

local lightAlloc = {} -- var PISS --old name for reference, maybe stop using dumb names
--local SHIT = {} -- var SHIT
local lightPoints = {} -- var FUCK

if (CLIENT) then
	if (render.GetHDREnabled()) then
		RunConsoleCommand("csm_hashdr", "1")
	else
		RunConsoleCommand("csm_hashdr", "0")
	end
end
if (SERVER) then
	util.AddNetworkString( "killCLientShadowsCSM" )
	util.AddNetworkString( "PlayerSpawned" )
	util.AddNetworkString( "hasLightEnvNet" )
	util.AddNetworkString( "csmPropWakeup" )
	util.AddNetworkString( "ReloadLightMapsCSM" )
	if (table.Count(ents.FindByClass("light_environment")) > 0) then
		RunConsoleCommand("csm_haslightenv", "1")
	end
end
local AppearanceKeys = {
	{ Position = 0.00, SunColour = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.00, 0.00), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) },
	{ Position = 0.25, SunColour = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.03, 0.03), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) },
	{ Position = 0.30, SunColour = Color(255,  140,  0, 255), SunBrightness = 1.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.01, 0.00, 0.03), SkyBottomColor = Vector(0.00, 0.05, 0.11), SkyDuskColor = Vector(1.00, 0.16, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00), FogColor = Vector(153, 110, 125) },
	{ Position = 0.35, SunColour = Color(255, 217, 179, 255), SunBrightness = 3.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.50, SunColour = Color(255, 217, 179, 255), SunBrightness = 3.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.18, 1.00), SkyBottomColor = Vector(0.00, 0.34, 0.67), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.65, SunColour = Color(255, 217, 179, 255), SunBrightness = 3.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.70, SunColour = Color(255,  140,  0, 255), SunBrightness = 1.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.01, 0.00, 0.03), SkyBottomColor = Vector(0.00, 0.05, 0.11), SkyDuskColor = Vector(1.00, 0.16, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00), FogColor = Vector(153, 110, 125) },
	{ Position = 0.75, SunColour = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.03, 0.03), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) }
}

net.Receive( "hasLightEnvNet", function( len, ply )
	RunConsoleCommand("csm_haslightenv", "1")
end)
function wakeup()
	if SERVER and GetConVar("csm_allowwakeprops"):GetBool() then
		print("[Real CSM] - Radiosity changed, waking up all props. (csm_wakeprops = 1)")
		for k, v in ipairs(ents.FindByClass( "prop_physics" )) do
			v:Fire("wake")
		end
	end
end
function findlight()
	if (SERVER) then
		hasLightEnvs = (table.Count(lightenvs) > 0)
		if (table.Count(ents.FindByClass("light_environment")) > 0) then
			RunConsoleCommand("csm_haslightenv", "1")
			net.Start( "hasLightEnvNet" )
			net.Broadcast()
		else
			RunConsoleCommand("csm_haslightenv", "0")
		end
	end
end
function warn()
	findlight()
	if CLIENT and (GetConVar( "csm_haslightenv" ):GetInt() == 0) then
		Derma_Message( "This map has no named light_environments, the CSM will not look nearly as good as it could.", "CSM Alert!", "OK!" )
	end
	--print(hasLightEnvs)
end

function ENT:createlamps()
	self.ProjectedTextures = { }
	for i = 1, 3 do
		self.ProjectedTextures[i] = ProjectedTexture()
		self.ProjectedTextures[i]:SetEnableShadows(true)
		if (i == 1) then
			self.ProjectedTextures[i]:SetTexture("csm/mask_center")
			if perfMode then
				self.ProjectedTextures[i]:Remove()
			end
		else
			if (i == 2) and perfMode then
				self.ProjectedTextures[i]:SetTexture("csm/mask_center")
			else
				self.ProjectedTextures[i]:SetTexture("csm/mask_ring")
			end
		end
	end
	if spreadEnabled and CLIENT then
		self:allocLights()
		self.ProjectedTextures[2]:SetTexture("csm/mask_center")
		for i = 1, GetConVar( "csm_spread_samples"):GetInt() - 2 do
			self.ProjectedTextures[i + 4] = ProjectedTexture()
			self.ProjectedTextures[i + 4]:SetEnableShadows(true)
			self.ProjectedTextures[i + 4]:SetTexture("csm/mask_center")
		end
	end
end

function ENT:SUNOff()
	if (SERVER) then -- TODO: make this turn off only on the client
		for k, v in ipairs(ents.FindByClass( "light_environment" )) do
			v:Fire("turnoff")
		end
	end
end
function ENT:SUNOn()
	if (SERVER) then -- TODO: make this turn off only on the client
		for k, v in ipairs(ents.FindByClass( "light_environment" )) do
			v:Fire("turnon")
		end
		net.Start( "ReloadLightMapsCSM" )
		net.Broadcast()
	end
end

function ENT:Initialize()
	for k, v in ipairs(ents.FindByClass( "edit_csm" )) do
		if v != self and SERVER then
			net.Start( "killCLientShadowsCSM" )
			net.Broadcast()
			v:Remove()
		end
	end
	RunConsoleCommand("r_projectedtexture_filter", "0.1")
	if !GetConVar( "csm_blobbyao" ):GetBool() then
		RunConsoleCommand("r_shadows_gamecontrol", "0")
	else
		BlobShadowsPrev = false
	end
	shadfiltChanged = true

	RunConsoleCommand("csm_enabled", "1")
	-- whats this for again??
	RunConsoleCommand("r_farz", "50000")
	if CLIENT and (file.Read( "csm.txt", "DATA" ) != "two" ) then
		--Derma_Message( "Hello! Welcome to the CSM addon! You should raise r_flashlightdepthres else the shadows will be blocky! Make sure you've read the FAQ for troubleshooting.", "CSM Alert!", "OK!" )
		local Frame = vgui.Create( "DFrame" )
		Frame:SetSize( 300, 240 )

		RunConsoleCommand("r_flashlightdepthres", "512") -- set it to the lowest of the low to avoid crashes

		Frame:Center()
		Frame:SetTitle( "CSM First Time Spawn!" )
		Frame:SetVisible( true )
		Frame:SetDraggable( false )
		Frame:ShowCloseButton( true )
		Frame:MakePopup()
		local label1 = vgui.Create( "DLabel", Frame )
		label1:SetPos( 15, 40 )
		label1:SetSize(	300, 20)
		label1:SetText( "Welcome to the CSM addon!" )
		local label2 = vgui.Create( "DLabel", Frame )
		label2:SetPos( 15, 55 )
		label2:SetSize(	300, 20)
		label2:SetText( "This is your first time spawning CSM, go set your quality!" )
		local label3 = vgui.Create( "DLabel", Frame )
		label3:SetPos( 15, 70 )
		label3:SetSize(	300, 20)
		label3:SetText( "Refer to the F.A.Q for troubleshooting and help!" )
		local lowButton = vgui.Create("DButton", Frame)
		lowButton:SetText( "Low" )
		lowButton:SetPos( 20, 100 )
		local mediumButton = vgui.Create("DButton", Frame)
		mediumButton:SetText( "Medium" )
		mediumButton:SetPos( 120, 100 )
		local highButton = vgui.Create("DButton", Frame)
		highButton:SetText( "High" )
		highButton:SetPos( 220, 100 )
		highButton.DoClick = function()
			RunConsoleCommand("r_flashlightdepthres", "8192")
		end
		mediumButton.DoClick = function()
			RunConsoleCommand("r_flashlightdepthres", "4096")
		end
		lowButton.DoClick = function()
			RunConsoleCommand("r_flashlightdepthres", "2048")
		end

		local DermaNumSlider = vgui.Create( "DNumSlider", Frame )
		DermaNumSlider:SetPos( 8, 120 )				-- Set the position
		DermaNumSlider:SetSize( 300, 30 )			-- Set the size
		DermaNumSlider:SetText( "Shadow Quality" )	-- Set the text above the slider
		DermaNumSlider:SetMin( 0 )				 	-- Set the minimum number you can slide to
		DermaNumSlider:SetMax( 8192 )				-- Set the maximum number you can slide to
		DermaNumSlider:SetDecimals( 0 )				-- Decimal places - zero for whole number
		DermaNumSlider:SetConVar( "r_flashlightdepthres" )	-- Changes the ConVar when you slide

		--local DermaNumSlider2 = vgui.Create( "DNumSlider", Frame )
		--DermaNumSlider2:SetPos( 8, 140 )				-- Set the position
		--DermaNumSlider2:SetSize( 300, 30 )			-- Set the size
		--DermaNumSlider2:SetText( "Shadow Filter" )	-- Set the text above the slider
		--DermaNumSlider2:SetMin( 0 )				 	-- Set the minimum number you can slide to
		--DermaNumSlider2:SetMax( 10 )				-- Set the maximum number you can slide to
		--DermaNumSlider2:SetDecimals( 2 )				-- Decimal places - zero for whole number
		--DermaNumSlider2:SetConVar( "r_projectedtexture_filter" )	-- Changes the ConVar when you slide

		local DermaCheckbox2 = vgui.Create( "DCheckBoxLabel", Frame )
		DermaCheckbox2:SetText("Performance Mode (for better framerate / less lag)")
		--DermaCheckbox2:SetPos( 8, 164 )				-- Set the position
		DermaCheckbox2:SetPos( 8, 150 )				-- Set the position
		DermaCheckbox2:SetSize( 300, 30 )			-- Set the size

		DermaCheckbox2:SetConVar( "csm_perfmode" )

		local Button = vgui.Create("DButton", Frame)
		Button:SetText( "Continue" )
		Button:SetPos( 160, 195 )
		local Button2 = vgui.Create("DButton", Frame)
		Button2:SetText( "Cancel" )
		Button2:SetPos( 80, 195 )
		Button.DoClick = function()
			file.Write( "csm.txt", "two" )
			Frame:Close()
		end

		Button2.DoClick = function()
			RunConsoleCommand("csm_enabled", "0")
			Frame:Close()
		end
	end

	if (SERVER) then
		if GetConVar( "csm_allowfpshadows_old" ):GetBool() then
			fpshadowcontroller = ents.Create( "csm_pseudoplayer_old" )
			fpshadowcontroller:Spawn()
		end
		util.AddNetworkString( "PlayerSpawned" )
		hasLightEnvs = (table.Count(lightenvs) > 0)
		if hasLightEnvs then
			self:SetRemoveStaticSun(true)
		else
			self:SetRemoveStaticSun(false)
			timer.Create( "warn", 0.1, 1, warn)
		end
	else
		fpShadowsPrev = !GetConVar( "csm_localplayershadow" ):GetBool()
		timer.Create( "warn", 0.1, 1, warn)
	end

	BaseClass.Initialize(self)
	self:SetMaterial( "csm/edit_csm" )
	if (self:GetRemoveStaticSun()) then
		timer.Create( "warn", 0.1, 1, warn)
		RunConsoleCommand("r_radiosity", GetConVar( "csm_propradiosity" ):GetString())
		if (GetConVar( "csm_wakeprops" ):GetBool()) then
			wakeup()
		end
		if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
			RunConsoleCommand("r_lightstyle", "0")
			RunConsoleCommand("r_ambientlightingonly", "1")
			if (CLIENT) then
				timer.Create( "reload", 0.1, 1, reloadLightmaps)
			end
		else
			self:SUNOff()
		end
	end

	if (CLIENT) then
		self:createlamps()
	end
		--hook.Add("RenderScreenspaceEffects", "CsmRenderOverlay", RenderOverlay)
		--hook.Add("SetupWorldFog", self, self.SetupWorldFog )

	--if (SERVER) then
		--self.EnvSun = FindEntity("env_sun")
		--self.EnvFogController = FindEntity("env_fog_controller")
	--else
		--self.EnvSun = FindEntity("C_Sun")
		--self.EnvFogController = FindEntity("C_FogController")
	--end

	--self.EnvSkyPaint = FindEntity("env_skypaint")
end

function ENT:SetupWorldFog()
	--render.FogMode(1)
	--render.FogStart(0.0)
	--render.FogEnd(32768.0)
	--render.FogMaxDensity(0.9)
	--render.FogColor(self.CurrentAppearance.FogColor.x, self.CurrentAppearance.FogColor.y, self.CurrentAppearance.FogColor.z)

	return false
end

function ENT:SetupDataTables()
	self:NetworkVar("Vector", 0, "SunColour", { KeyName = "Sun colour", Edit = { type = "VectorColor", order = 2, title = "Sun colour"}})
	self:NetworkVar("Float", 0, "SunBrightness", { KeyName = "Sun brightness", Edit = { type = "Float", order = 3, min = 0.0, max = 10000.0, title = "Sun brightness"}})

	self:NetworkVar("Float", 1, "SizeNear", { KeyName = "Size 1", Edit = { type = "Float", order = 4, min = 0.0, max = 32768.0, title = "Near cascade size" }})
	self:NetworkVar("Float", 2, "SizeMid",  { KeyName = "Size 2", Edit = { type = "Float", order = 5, min = 0.0, max = 32768.0, title = "Middle cascade size" }})
	self:NetworkVar("Float", 3, "SizeFar",  { KeyName = "Size 3", Edit = { type = "Float", order = 6, min = 0.0, max = 32768.0, title = "Far cascade size" }}) --16384

	--self:NetworkVar("Bool", 0, "EnableFurther", { KeyName = "Enable Futher Light", Edit = { type = "Bool", order = 7, title = "Enable further cascade for large maps"}})
	self:NetworkVar("Float", 4, "SizeFurther",  { KeyName = "Size 4", Edit = { type = "Float", order = 8, min = 0.0, max = 65536.0, title = "Further cascade size" }})
	--self:NetworkVar("Bool", 1, "EnableFurtherShadows", { KeyName = "Enable Futher Shadows", Edit = { type = "Bool", order = 7, title = "Enable shadows on further cascade"}})

	self:NetworkVar("Float", 5, "Orientation", { KeyName = "Orientation", Edit = { type = "Float", order = 10, min = 0.0, max = 360.0, title = "Sun orientation" }})
	self:NetworkVar("Bool", 2, "UseMapSunAngles", { KeyName = "Use Map Sun Angles", Edit = { type = "Bool", order = 11, title = "Use the Map Sun angles"}})
	self:NetworkVar("Bool", 3, "UseSkyFogEffects", { KeyName = "Use Sky and Fog Effects", Edit = { type = "Bool", order = 12, title = "Use Sky and Fog effects"}})
	self:NetworkVar("Float", 6, "MaxAltitude", { KeyName = "Maximum altitude", Edit = { type = "Float", order = 13, min = 0.0, max = 90.0, title = "Maximum altitude" }})
	self:NetworkVar("Float", 7, "Time", { KeyName = "Time", Edit = { type = "Float", order = 14, min = 0.0, max = 1.0, title = "Time of Day" }})
	self:NetworkVar("Float", 9, "Height", { KeyName = "Height", Edit = { type = "Float", order = 15, min = 0.0, max = 50000.0, title = "Sun Height" }})
	self:NetworkVar("Float", 10, "SunNearZ", { KeyName = "NearZ", Edit = { type = "Float", order = 16, min = 0.0, max = 32768.0, title = "Sun NearZ (adjust if issues)" }})
	self:NetworkVar("Float", 11, "SunFarZ", { KeyName = "FarZ", Edit = { type = "Float", order = 17, min = 0.0, max = 50000.0, title = "Sun FarZ" }})

	self:NetworkVar("Bool", 4, "RemoveStaticSun", { KeyName = "Remove Vanilla Static Sun", Edit = { type = "Bool", order = 18, title = "Remove vanilla static Sun"}})
	self:NetworkVar("Bool", 5, "HideRTTShadows", { KeyName = "Hide RTT Shadows", Edit = { type = "Bool", order = 19, title = "Hide RTT Shadows"}})

	--self:NetworkVar("Float", 10, "ShadowFilter", { KeyName = "ShadowFilter", Edit = { type = "Float", order = 19, min = 0.0, max = 10.0, title = "Shadow filter"}})
	--self:NetworkVar("Int", 3, "ShadowRes", { KeyName = "ShadowRes", Edit = { type = "Float", order = 20, min = 0.0, max = 8192.0, title = "Shadow resolution"}})

	self:NetworkVar("Bool", 6, "EnableOffsets", { KeyName = "Enable Offsets", Edit = { type = "Bool", order = 21, title = "Enable Offsets"}})
	self:NetworkVar("Int", 0, "OffsetPitch", { KeyName = "Pitch Offset", Edit = { type = "Float", order = 22, min = -180.0, max = 180.0, title = "Pitch Offset" }})
	self:NetworkVar("Int", 1, "OffsetYaw", { KeyName = "Yaw Offset", Edit = { type = "Float", order = 23, min = -180.0, max = 180.0, title = "Yaw Offset" }})
	self:NetworkVar("Int", 2, "OffsetRoll", { KeyName = "Roll Offset", Edit = { type = "Float", order = 24, min = -180.0, max = 180.0, title = "Roll Offset" }})

	if (SERVER) then
		-- Yeah I hardcoded the construct sun colour, the env_suns one is shit
		if GetConVar( "csm_getENVSUNcolour"):GetBool() and game.GetMap() != "gm_construct" and FindEntity("env_sun") != nil then
			self:SetSunColour(FindEntity("env_sun"):GetColor():ToVector()) --Vector(1.0, 0.90, 0.80, 1.0))
		else
			self:SetSunColour(Vector(1.0, 0.90, 0.80, 1.0))
		end
		if (GetConVar( "csm_hashdr" ):GetInt() == 1) then
			self:SetSunBrightness(1000)
		else
			self:SetSunBrightness(200)
		end

		self:SetSizeNear(128.0)
		self:SetSizeMid(1024.0)
		self:SetSizeFar(8192.0)

		--self:SetEnableFurther(false)
		self:SetSizeFurther(65536.0)
		--self:SetEnableFurtherShadows(true)


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
		--self:SetShadowFilter(0.1)
		--self:SetShadowRes(8192)

		self:SetEnableOffsets(false)
		self:SetOffsetPitch(0)
		self:SetOffsetYaw(0)
		self:SetOffsetRoll(0)
		shadfiltChanged = true
	end
end

hook.Add( "PlayerInitialSpawn", "playerspawned", function( ply )
	net.Start( "PlayerSpawned" )
	net.Send( ply )
end )


net.Receive( "PlayerSpawned", function( len, ply )
	if CLIENT and (FindEntity("edit_csm") != nil) and (GetConVar( "csm_spawnalways" ):GetBool()) then
		FindEntity("edit_csm"):Initialize()
	end
end )

net.Receive( "ReloadLightMapsCSM", function( len, ply )
	if CLIENT and GetConVar("csm_redownloadonremove"):GetBool() then
		render.RedownloadAllLightmaps(false ,true)
	end
end )

net.Receive( "csmPropWakeup", function( len, ply )
	if SERVER then
		wakeup()
	end
end )

net.Receive( "killCLientShadowsCSM", function( len, ply )
	if CLIENT and fpshadowcontrollerCLIENT and fpshadowcontrollerCLIENT:IsValid() then
		fpshadowcontrollerCLIENT:Remove()
	end
end )

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end


function reloadLightmaps()
	if (CLIENT) then
		render.RedownloadAllLightmaps(false ,true)
	end
end

function ENT:OnRemove()
	--print("Removed")
	if fpshadowcontrollerCLIENT and fpshadowcontrollerCLIENT:IsValid() then
		fpshadowcontrollerCLIENT:Remove()
	end
	RunConsoleCommand("r_farz", "-1")
	if (GetConVar( "csm_spawnalways" ):GetInt() == 0) then
		furtherEnabled = false
		furtherEnabledPrev = false
		if (self:GetHideRTTShadows()) then
			RunConsoleCommand("r_shadows_gamecontrol", "1")
		end
		if GetConVar( "csm_blobbyao" ):GetBool() then
			RunConsoleCommand("r_shadowrendertotexture", "1")
			RunConsoleCommand("r_shadowdist", "10000")
		end
		RunConsoleCommand("r_projectedtexture_filter", "1")

		if (self:GetRemoveStaticSun()) then


			RunConsoleCommand("r_radiosity", "3")
			if (GetConVar( "csm_wakeprops" ):GetBool()) then
				wakeup()
			end
			if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
				RunConsoleCommand("r_ambientlightingonly", "0")

				RunConsoleCommand("r_lightstyle", "-1")
				timer.Create( "reload", 0.1, 1, reloadLightmaps )
			else
				self:SUNOn()
			end
		end
	end
	if SERVER and fpshadowcontroller and fpshadowcontroller:IsValid() then
		fpshadowcontroller:Remove()

	end
	if (CLIENT) then
		for i, projectedTexture in pairs(self.ProjectedTextures) do
			projectedTexture:Remove()
		end

		table.Empty(self.ProjectedTextures)
	end
end

hook.Add( "ShadnowFilterChange", "shadfiltchanged", function()
	shadfiltChanged = true
end)

function ENT:Think()
	if (GetConVar( "csm_enabled" ):GetInt() == 1) and (csmEnabledPrev == false) then
		furtherEnabledShadowsPrev = !GetConVar( "csm_furthershadows" ):GetBool()
		furtherEnabledPrev = !GetConVar( "csm_further" ):GetBool()
		csmEnabledPrev = true
		if (self:GetRemoveStaticSun()) then
			if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
				RunConsoleCommand("r_ambientlightingonly", "1")

				RunConsoleCommand("r_lightstyle", "1")
				timer.Create( "reload", 0.1, 1, reloadLightmaps )
			else
				self:SUNOff()
			end
		end
		RunConsoleCommand("r_radiosity", GetConVar( "csm_propradiosity" ):GetString())
		if (GetConVar( "csm_wakeprops" ):GetBool()) then
			wakeup()
		end
		if (self:GetHideRTTShadows()) then
			RunConsoleCommand("r_shadows_gamecontrol", "0")
			BlobShadowsPrev = false
		end
		if GetConVar( "csm_blobbyao" ):GetBool() then
			RunConsoleCommand("r_shadowrendertotexture", "0")
			RunConsoleCommand("r_shadowdist", "20")
			RunConsoleCommand("r_shadows_gamecontrol", "1")
		end
		if (CLIENT) then
			self:createlamps()
		end
	end

	if (GetConVar( "csm_enabled" ):GetInt() == 0) and (csmEnabledPrev == true) then
		csmEnabledPrev = false
		if (self:GetRemoveStaticSun()) then
			if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
				RunConsoleCommand("r_ambientlightingonly", "0")

				RunConsoleCommand("r_lightstyle", "-1")
				timer.Create( "reload", 0.1, 1, reloadLightmaps )
			else
				self:SUNOn()
			end
		end
		RunConsoleCommand("r_radiosity", "3")
		if (GetConVar( "csm_wakeprops" ):GetBool()) then
			wakeup()
		end
		RunConsoleCommand("r_shadowrendertotexture", "1")
		RunConsoleCommand("r_shadowdist", "10000")
		if (self:GetHideRTTShadows()) then
			RunConsoleCommand("r_shadows_gamecontrol", "1")
		end
		if (CLIENT) then
			for i, projectedTexture in pairs(self.ProjectedTextures) do
				projectedTexture:Remove()
			end
			table.Empty(self.ProjectedTextures)
		end
	end


	propradiosity = GetConVar( "csm_propradiosity" ):GetString()
	if CLIENT and (propradiosityPrev != propradiosity) and GetConVar( "csm_enabled" ):GetBool() then
		RunConsoleCommand("r_radiosity", propradiosity)
		if (GetConVar( "csm_wakeprops" ):GetBool()) then
			net.Start( "csmPropWakeup" )
			net.SendToServer()
		end
		propradiosityPrev = propradiosity
	end
	if (GetConVar( "csm_enabled" ):GetInt() != 1) then return end
	--print("hi")
	shadfiltChanged = false

	fpShadows = GetConVar( "csm_localplayershadow" ):GetBool()
	if CLIENT and (fpShadowsPrev != fpShadows) then
		if (fpShadows) then
			--print("MAKING")
			fpshadowcontrollerCLIENT = ents.CreateClientside( "csm_pseudoplayer" )
			fpshadowcontrollerCLIENT:Spawn()
			fpShadowsPrev = true
		else
			--print("REMOVING")
			if fpshadowcontrollerCLIENT and fpshadowcontrollerCLIENT:IsValid() then
				fpshadowcontrollerCLIENT:Remove()
			end
			fpShadowsPrev = false
		end
	end

	furtherEnabledShadows = GetConVar( "csm_furthershadows" ):GetBool()
	furtherEnabled = GetConVar( "csm_further" ):GetBool()
	if (furtherEnabledPrev != furtherEnabled) then
		if (furtherEnabled) then
			if (CLIENT) then
				self.ProjectedTextures[4] = ProjectedTexture()
				self.ProjectedTextures[4]:SetTexture("csm/mask_ring")
				if (furtherEnabledShadows) then
					self.ProjectedTextures[4]:SetEnableShadows(true)
				else
					self.ProjectedTextures[4]:SetEnableShadows(false)
				end
			end
			furtherEnabledPrev = true
		else
			if CLIENT and (self.ProjectedTextures[4] != nil) and (self.ProjectedTextures[4]:IsValid()) then -- hacky: fix the cause properly
				self.ProjectedTextures[4]:Remove()
			end
			furtherEnabledPrev = false
		end
	end


	spreadSample = GetConVar( "csm_spread_samples" ):GetInt()
	if (spreadSamplePrev != spreadSample) then
		if (CLIENT) then
			for i, projectedTexture in pairs(self.ProjectedTextures) do
				projectedTexture:Remove()
			end
			table.Empty(self.ProjectedTextures)
			self:createlamps()
		end
		spreadSamplePrev = spreadSample

	end

	spreadLayer = GetConVar( "csm_spread_layers" ):GetInt()
	if (spreadLayerPrev != spreadLayer) then
		if (CLIENT) then
			self:allocLights()
		end
		spreadLayerPrev = spreadLayer

	end

	perfMode = GetConVar( "csm_perfmode" ):GetBool()
	if (perfModePrev != perfMode) and GetConVar( "csm_enabled" ):GetBool() then
		if (perfMode) then
			if CLIENT and (self.ProjectedTextures[1] != nil) and (self.ProjectedTextures[1]:IsValid()) then
				self.ProjectedTextures[2]:SetTexture("csm/mask_center")
				self.ProjectedTextures[1]:Remove()
			end
			perfModePrev = true
		else
			if (CLIENT) then
				for i, projectedTexture in pairs(self.ProjectedTextures) do
					projectedTexture:Remove()
				end
				table.Empty(self.ProjectedTextures)
				self:createlamps()
			end
			perfModePrev = false
		end
	end

	spreadEnabled = GetConVar( "csm_spread" ):GetBool()
	if (spreadEnabledPrev != spreadEnabled) and GetConVar( "csm_enabled" ):GetBool() then
		if (spreadEnabled) then
			if CLIENT and (self.ProjectedTextures[2] != nil) and (self.ProjectedTextures[2]:IsValid()) then
				self.ProjectedTextures[2]:SetTexture("csm/mask_center")
				for i = 1, GetConVar( "csm_spread_samples"):GetInt() - 2 do
					self.ProjectedTextures[i + 4] = ProjectedTexture()
					self.ProjectedTextures[i + 4]:SetEnableShadows(true)
					self.ProjectedTextures[i + 4]:SetTexture("csm/mask_center")
				end
			end
			spreadEnabledPrev = true
		else
			if (CLIENT) then
				for i, projectedTexture in pairs(self.ProjectedTextures) do
					projectedTexture:Remove()
				end
				table.Empty(self.ProjectedTextures)
				self:createlamps()
			end
			spreadEnabledPrev = false
		end
	end

	furtherEnabledShadows = GetConVar( "csm_furthershadows" ):GetBool()
	if (furtherEnabledShadowsPrev != furtherEnabledShadows) then
		if (furtherEnabledShadows) then
			if CLIENT and (self.ProjectedTextures[4] != nil) and (self.ProjectedTextures[4]:IsValid()) then
				self.ProjectedTextures[4]:SetEnableShadows(true)
				furtherEnabledShadowsPrev = true
			end
		else
			if CLIENT and (self.ProjectedTextures[4] != nil) and (self.ProjectedTextures[4]:IsValid()) then
				self.ProjectedTextures[4]:SetEnableShadows(false)
				furtherEnabledShadowsPrev = false
			end
		end
	end

	farEnabledShadows = GetConVar( "csm_farshadows" ):GetBool()
	if (farEnabledShadowsPrev != farEnabledShadows) then
		if (farEnabledShadows) then
			if CLIENT and (self.ProjectedTextures[3] != nil) and (self.ProjectedTextures[3]:IsValid()) then
				self.ProjectedTextures[3]:SetEnableShadows(false)
				farEnabledShadowsPrev = true
			end
		else
			if CLIENT and (self.ProjectedTextures[3] != nil) and (self.ProjectedTextures[3]:IsValid()) then
				self.ProjectedTextures[3]:SetEnableShadows(true)
				farEnabledShadowsPrev = false
			end
		end
	end


	local removestatsun = self:GetRemoveStaticSun()



	if (RemoveStaticSunPrev != removestatsun) then
		if (self:GetRemoveStaticSun()) then
			timer.Create( "warn", 0.1, 1, warn)
			RunConsoleCommand("r_radiosity", GetConVar( "csm_propradiosity" ):GetString())
			if (GetConVar( "csm_wakeprops" ):GetBool()) then
				wakeup()
			end
			if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
				if (CLIENT) then
					RunConsoleCommand("r_ambientlightingonly", "1")
					RunConsoleCommand("r_lightstyle", "0")
					timer.Create( "reload", 0.1, 1, reloadLightmaps)
				end
			else
				self:SUNOff()
			end
		else
			RunConsoleCommand("r_radiosity", "3")
			if (GetConVar( "csm_wakeprops" ):GetBool()) then
				wakeup()
			end
			if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
				if (CLIENT) then
					RunConsoleCommand("r_lightstyle", "-1")
					RunConsoleCommand("r_ambientlightingonly", "0")
					timer.Create( "reload", 0.1, 1, reloadLightmaps)
				end
			else
				self:SUNOn()
			end
		end
		RemoveStaticSunPrev = removestatsun
	end

	if (CLIENT) then

		local hiderttshad = self:GetHideRTTShadows()
		local BlobShadows = GetConVar( "csm_blobbyao" ):GetBool()

		if (HideRTTShadowsPrev != hiderttshad) and !BlobShadows then

			if (hiderttshad) then
				RunConsoleCommand("r_shadows_gamecontrol", "0")
			else
				RunConsoleCommand("r_shadows_gamecontrol", "1")
			end
			HideRTTShadowsPrev = hiderttshad
		end
		sun = util.GetSunInfo()
		local shadfilt = GetConVar( "r_projectedtexture_filter" ):GetFloat()
		if (ShadowFilterPrev != shadfilt) then
			ShadowFilterPrev = shadfilt
			shadfiltChanged = true
			RunConsoleCommand("csm_filter", shadfilt)
		end

		if (BlobShadowsPrev != BlobShadows) and GetConVar( "csm_enabled" ):GetBool() then
			BlobShadowsPrev = BlobShadows
			if (BlobShadows) then
				HideRTTShadowsPrev = true
				hiderttshad = false
				RunConsoleCommand("r_shadowrendertotexture", "0")
				RunConsoleCommand("r_shadowdist", "20")
				RunConsoleCommand("r_shadows_gamecontrol", "1")
				BlobShadowsPrev = true
			else
				RunConsoleCommand("r_shadowrendertotexture", "1")
				RunConsoleCommand("r_shadowdist", "10000")
				if (hiderttshad) then
					RunConsoleCommand("r_shadows_gamecontrol", "0")
				else
					RunConsoleCommand("r_shadows_gamecontrol", "1")
				end
				BlobShadowsPrev = false
			end
		end
	end

	local pitch = 0
	local yaw = 0
	local roll = 0

	if (self:GetUseMapSunAngles()) then
		pitch = 0
		yaw = 0
		roll = 0
		if ( sun != nil ) then
			pitch = sun.direction:Angle().pitch + 90
			yaw = sun.direction:Angle().yaw
			roll = sun.direction:Angle().roll
		else
			if (warnedyet == false) then
				Derma_Message( "This map has no env_sun. CSM will not be able to find the sun position and rotation!", "CSM Alert!", "OK!" )
				warnedyet = true
			end
			pitch = -180.0 + (self:GetTime() * 360.0)
			yaw = self:GetOrientation()
			roll = 90.0 - self:GetMaxAltitude()
		end
	else
		pitch = -180.0 + (self:GetTime() * 360.0)
		yaw = self:GetOrientation()
		roll = 90.0 - self:GetMaxAltitude()
	end

	if (self:GetEnableOffsets()) then
		pitch = pitch + self:GetOffsetPitch()
		yaw = yaw + self:GetOffsetYaw()
		roll = roll + self:GetOffsetRoll()
	end

	local offset = Vector(0, 0, 1)
	local offset2 = Vector(0, 0, 1)
	if (usemapangles) then
		offset:Rotate(Angle(pitch, 0, 0))
		offset:Rotate(Angle(0, yaw, roll))
		offset2:Rotate(Angle(pitch, 0, 0))
		offset2:Rotate(Angle(0, yaw, roll))
	else
		offset:Rotate(Angle(pitch, 0, 0))
		offset:Rotate(Angle(0, yaw, roll))
		offset2:Rotate(Angle(pitch, 0, 0))
		offset2:Rotate(Angle(0, yaw, roll))
	end

	local angle = Angle()
	local direction = offset;
	if (usemapangles) then
		 angle = (vector_origin - offset2):Angle()
	else
		 angle = (vector_origin - offset):Angle()
	end
	self.CurrentAppearance = CalculateAppearance((pitch + -180) / 360)
	offset = offset * self:GetHeight() --self:GetSunFarZ()
	if (usemapangles) then
		self.CurrentAppearance = CalculateAppearance((pitch + -180) / 360)
	else
		self.CurrentAppearance = CalculateAppearance(self:GetTime())
	end

	-- for csm_debug_cascade
	debugColours = {}
	debugColours[1] = Color(0, 255, 0, 255)
	debugColours[2] = Color(255, 0, 0, 255)
	debugColours[3] = Color(255, 255, 0, 255)
	debugColours[4] = Color(0, 0, 255, 255)
	debugColours[5] = Color(0, 255, 255, 255)
	debugColours[6] = Color(255, 0, 255, 255)
	debugColours[7] = Color(255, 255, 255, 255)

	if CLIENT and (GetConVar( "csm_enabled" ):GetInt() == 1) and (GetConVar( "csm_update" ):GetInt() == 1) then
		local position = GetViewEntity():GetPos() + offset

		if (self.ProjectedTextures[1] == nil) and !perfMode then
			self:createlamps()
		end

		self.ProjectedTextures[1]:SetOrthographic(true, self:GetSizeNear() * GetConVar( "csm_sizescale" ):GetFloat() , self:GetSizeNear() * GetConVar( "csm_sizescale" ):GetFloat() , self:GetSizeNear() * GetConVar( "csm_sizescale" ):GetFloat() , self:GetSizeNear() * GetConVar( "csm_sizescale" ):GetFloat() )
		self.ProjectedTextures[2]:SetOrthographic(true, self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() )
		self.ProjectedTextures[3]:SetOrthographic(true, self:GetSizeFar() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeFar() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeFar() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeFar() * GetConVar( "csm_sizescale" ):GetFloat() )


		--local lightAlloc = {} -- var PISS
		--local SHIT = {} -- var SHIT
		--local lightPoints = {} -- var FUCK
		if furtherEnabled and (self.ProjectedTextures[4] != nil) and (self.ProjectedTextures[4]:IsValid()) then
			self.ProjectedTextures[4]:SetOrthographic(true, self:GetSizeFurther() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeFurther() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeFurther() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeFurther() * GetConVar( "csm_sizescale" ):GetFloat() )
		end
		if (spreadEnabled) then
			if (self.ProjectedTextures[1] != nil) and (self.ProjectedTextures[1]:IsValid()) then
				self.ProjectedTextures[1]:SetOrthographic(true, self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() )
			end
			for i = 1, GetConVar( "csm_spread_samples" ):GetInt() - 2 do
				if (self.ProjectedTextures[4 + i] != nil) and (self.ProjectedTextures[4 + i]:IsValid()) then
					self.ProjectedTextures[4 + i]:SetOrthographic(true, self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() ,  self:GetSizeMid() * GetConVar( "csm_sizescale" ):GetFloat() )
				end
			end
		end

		depthBias = GetConVar( "csm_depthbias" ):GetFloat()
		slopeScaleDepthBias = GetConVar( "csm_slopescaledepthbias" ):GetFloat()
		for i, projectedTexture in pairs(self.ProjectedTextures) do
			if (shadfiltChanged) then
				projectedTexture:SetShadowFilter(GetConVar( "csm_filter" ):GetFloat())
			end
			projectedTexture:SetShadowDepthBias(depthBias)
			projectedTexture:SetShadowSlopeScaleDepthBias(slopeScaleDepthBias)
			sunBright = (self:GetSunBrightness()) / 400
			if (GetConVar( "csm_stormfoxsupport" ):GetInt() == 0) then
				if (spreadEnabled) then
					if (i == 1) then
						projectedTexture:SetBrightness(sunBright / GetConVar( "csm_spread_samples" ):GetInt())
					elseif (i == 2) then
						projectedTexture:SetBrightness(sunBright / GetConVar( "csm_spread_samples" ):GetInt())
					elseif (i > 4) then
						projectedTexture:SetBrightness(sunBright / GetConVar( "csm_spread_samples" ):GetInt())
					else
						projectedTexture:SetBrightness(sunBright)
					end
				else
					projectedTexture:SetBrightness(sunBright)
				end
			else
				self.CurrentAppearance = CalculateAppearance((pitch + -180) / 360)
				projectedTexture:SetBrightness(self.CurrentAppearance.SunBrightness * GetConVar( "csm_stormfox_brightness_multiplier" ):GetFloat())
				--print((self.CurrentAppearance.SunBrightness) )
			end
			if GetConVar("csm_debug_cascade"):GetBool() then
				for i2, projectedTexture2 in pairs(self.ProjectedTextures) do
					projectedTexture2:SetColor(debugColours[i])
					--projectedTexture2:SetBrightness(2)
				end
			elseif (GetConVar( "csm_stormfox_coloured_sun" ):GetBool()) then
				self.CurrentAppearance = CalculateAppearance((pitch + -180) / 360)
				--print(self.CurrentAppearance.SunColour)
				projectedTexture:SetColor(self.CurrentAppearance.SunColour)
			else
				projectedTexture:SetColor(self:GetSunColour():ToColor()) --csm_stormfox_coloured_sun
			end
			projectedTexture:SetPos(position)

			projectedTexture:SetAngles(angle)
			if (spreadEnabled) then
				-- angle them all in a circle shape
				mtest = Matrix()
				mtest:SetAngles(angle)
				chuck = Angle(0, 0, 0)
				if (i == 1) then
					chuck = lightPoints[1]
				elseif (i == 2) then
					chuck = lightPoints[2]
				elseif (i > 4) then
					chuck = lightPoints[i - 2]
				end
				offset3 = Angle(chuck.x, 0, 0)
				offset4 = Angle(0, chuck.y, 0)
				mtest:Rotate(offset3 + offset4)
				projectedTexture:SetAngles(mtest:GetAngles())
			end

			projectedTexture:SetNearZ(self:GetSunNearZ())
			projectedTexture:SetFarZ(self:GetSunFarZ() * 1.025)
			projectedTexture:SetQuadraticAttenuation(0)
			projectedTexture:SetLinearAttenuation(0)
			projectedTexture:SetConstantAttenuation(1) -- TODO: FIX STORMFOX BRIGHTNESS WHEN THIS IS SET TO 1
			projectedTexture:Update()
		end

	end
	useskyandfog = self:GetUseSkyFogEffects()

	if (useskyandfog) then
		if (IsValid(self.EnvSun)) then
			self.EnvSun:SetKeyValue("sun_dir", tostring(direction))
		end

		if (IsValid(self.EnvSkyPaint)) then
			self.EnvSkyPaint:SetKeyValue("TopColor", tostring(self.CurrentAppearance.SkyTopColor))
			self.EnvSkyPaint:SetKeyValue("BottomColor", tostring(self.CurrentAppearance.SkyBottomColor))
			self.EnvSkyPaint:SetKeyValue("DuskColor", tostring(self.CurrentAppearance.SkyDuskColor))
			self.EnvSkyPaint:SetKeyValue("SunColor", tostring(self.CurrentAppearance.SkySunColor))
		end

		if (IsValid(self.EnvFogController)) then
			self.EnvFogController:SetKeyValue("fogcolor", tostring(self.CurrentAppearance.FogColor))
		end
	end

end

--[[
function RenderOverlay() -- unused, if you want this stuff, use stormfox.
	local shaderParams = {
		["$pp_colour_addr"] = 0,
		["$pp_colour_addg"] = 0,
		["$pp_colour_addb"] = 0,
		["$pp_colour_brightness"] = 0,
		["$pp_colour_contrast"] = 1.0 - self.CurrentAppearance.ScreenDarkenFactor,
		["$pp_colour_colour"] = 1,
		["$pp_colour_mulr"] = 0,
		["$pp_colour_mulg"] = 0,
		["$pp_colour_mulb"] = 0
	}

	DrawColorModify(shaderParams)
end
--]]

function ENT:allocLights()
--yikes = 1
	lightAlloc = {}
	lightPoints = {}
	-- csm_spread_layer_density
	for i2 = 1, GetConVar( "csm_spread_layers" ):GetInt() do
		beans = (GetConVar( "csm_spread_samples" ):GetInt() / GetConVar( "csm_spread_layers" ):GetInt()) --/ (GetConVar( "csm_spread_layers" ):GetInt())) * 
		if i2 == 1 then
			beans = math.ceil(beans)
		else
			beans = math.floor(beans)
		end
		table.insert(lightAlloc, beans)

	end

	sum = 0
	failsafe = 0

	while (sum != GetConVar( "csm_spread_samples" ):GetInt()) and failsafe != 2 do -- Division can be fucky so this is here, we need perfect division
		failsafe = 1 + failsafe
		sum = 0
		for k,v in pairs(lightAlloc) do
			sum = sum + v
		end

		if (sum > GetConVar( "csm_spread_samples" ):GetInt()) then
			--print(PISS[GetConVar( "csm_spread_layers" ):GetInt()])
			lightAlloc[GetConVar( "csm_spread_layers" ):GetInt()] = lightAlloc[GetConVar( "csm_spread_layers" ):GetInt()] - 1
			--PISS[GetConVar( "csm_spread_layers" ):GetInt() - 1] = PISS[GetConVar( "csm_spread_layers" ):GetInt() - 1] - 1

		elseif (sum < GetConVar( "csm_spread_samples" ):GetInt()) then

			lightAlloc[failsafe] = lightAlloc[failsafe] + 1

		end
	end




	alloctype = GetConVar( "csm_spread_layer_alloctype" ):GetInt()
	if alloctype == 1 and GetConVar( "csm_spread_layers" ):GetInt() > 2 then
		for k,v in pairs(lightAlloc) do
			if lightAlloc[k] > 2 then
				lightAlloc[k] = lightAlloc[k] - (k - 2)
			end
		end
	elseif GetConVar( "csm_spread_layers" ):GetInt() > 1 and lightAlloc[GetConVar( "csm_spread_layers" ):GetInt()] > 3 then
		lightAlloc[GetConVar( "csm_spread_layers" ):GetInt()] = lightAlloc[GetConVar( "csm_spread_layers" ):GetInt()] - 1
		lightAlloc[1] = lightAlloc[1] + 1
	end

	if lightAlloc[GetConVar( "csm_spread_layers" ):GetInt()] > 3 and GetConVar( "csm_spread_layers" ):GetInt() > 1 and GetConVar( "csm_spread_layer_reservemiddle" ):GetBool() then
		lightAlloc[GetConVar( "csm_spread_layers" ):GetInt()] = lightAlloc[GetConVar( "csm_spread_layers" ):GetInt()] - 1
	end

	for i2 = 1, GetConVar( "csm_spread_layers" ):GetInt() do
		beans = lightAlloc[i2]
		--[[
		beans = (GetConVar( "csm_spread_samples" ):GetInt() / GetConVar( "csm_spread_layers" ):GetInt()) --/ (GetConVar( "csm_spread_layers" ):GetInt())) * 
		if i2 == 1 then
			beans = math.ceil(beans)
		else
			beans = math.floor(beans)
		end
		--]]
		i2r = GetConVar( "csm_spread_layers" ):GetInt() - (i2 - 1)
		for degrees = 1, 360, 360 / beans do

			local x, y = PointOnCircle( degrees, ((i2r - ((GetConVar("csm_spread_layer_density"):GetFloat() * - 1) * (i2 - 1))) / GetConVar( "csm_spread_layers" ):GetInt()) * GetConVar( "csm_spread_radius" ):GetFloat(), 0, 0 )
			table.insert(lightPoints, Angle(x, y, 0))
			--yikes = yikes + 1
		end
		if GetConVar( "csm_spread_layers" ):GetInt() > 1 and lightAlloc[GetConVar( "csm_spread_layers" ):GetInt()] > 1 and i2 == GetConVar( "csm_spread_layers" ):GetInt() and GetConVar( "csm_spread_layer_reservemiddle" ):GetBool() then
			table.insert(lightPoints, Angle(0, 0, 0))
		end
	end
	--PrintTable(lightAlloc)
	--PrintTable(lightPoints)
end

function PointOnCircle( angle, radius, offsetX, offsetY ) -- ACTUALLY NERD SHIT LMFAO
	angle =  math.rad( angle )
	local x = math.cos( angle ) * radius + offsetX
	local y = math.sin( angle ) * radius + offsetY
	return x, y
end


function CalculateAppearance(position)
	local from, to

	for i, key in pairs(AppearanceKeys) do
		if (key.Position == position) then
			return key
		end

		if (key.Position < position) then
			from = key
		end

		if (key.Position > position) then
			to = key
			break
		end
	end

	if from == nil then
		from = AppearanceKeys[#AppearanceKeys]
	end

	if to == nil then
		to = AppearanceKeys[1]
	end

	local t = (position - from.Position) / (to.Position - from.Position)
	local result = { }

	for i, key in pairs(from) do
		if type(key) == "table" then
			result[i] = LerpColor(t, from[i], to[i])
		else
			result[i] = Lerp(t, from[i], to[i])
		end
	end

	return result
end

function LerpColor(t, fromColor, toColor)
	local r = Lerp(t, fromColor.r, toColor.r)
	local g = Lerp(t, fromColor.g, toColor.g)
	local b = Lerp(t, fromColor.b, toColor.b)
	local a = Lerp(t, fromColor.a, toColor.a)

	return Color(r, g, b, a)
end

function HexToRgb(hex)
	local r = tonumber(string.sub(hex, 1, 2), 16)
	local g = tonumber(string.sub(hex, 3, 4), 16)
	local b = tonumber(string.sub(hex, 5, 6), 16)

	return Color(r, g, b, 1.0)
end

function FindEntity(class)
	local entities = ents.FindByClass(class)

	if (#entities > 0) then
		return entities[1]
	else
		return nil
	end
end
