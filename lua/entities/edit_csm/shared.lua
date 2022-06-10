-- TODO:
-- - Use a single ProjectedTexture when r_flashlightdepthres is 0 (since there's no shadows then anyway)

AddCSLuaFile()
DEFINE_BASECLASS("base_edit_csm")

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
CreateClientConVar(	 "csm_legacydisablesun", 0,  true, false)
CreateClientConVar(	 "csm_haslightenv", 0,  false, false)
CreateClientConVar(	 "csm_hashdr", 0,  false, false)
CreateClientConVar(	 "csm_enabled", 1,  false, false)
CreateClientConVar(	 "csm_filter", 0.10,  false, false)

CreateConVar(	 "csm_stormfoxsupport", 0,  true, false)
CreateConVar(	 "csm_stormfox_brightness_multiplier", 80,  true, false)
CreateConVar(	 "csm_stormfox_coloured_sun", 0,  true, false)
local lightenvs = {ents.FindByClass("light_environment")}
local hasLightEnvs = false
local PROJECTION_DISTANCE = 32768.0 --327680.0
local PROJECTION_BRIGHTNESS_MULTIPLIER = 70.0 --1000.0

local RemoveStaticSunPrev = false
local HideRTTShadowsPrev = false
local ShadowFilterPrev = 1.0
local ShadowResPrev = 8192.0
local shadfiltChanged = true
local csmEnabledPrev = false
local useskyandfog = false
local furtherEnabled = false
local furtherEnabledPrev = false
if (CLIENT) then
	if (render.GetHDREnabled()) then
		RunConsoleCommand("csm_hashdr", "1")
	else
		RunConsoleCommand("csm_hashdr", "0")
	end
end
if (SERVER) then
	util.AddNetworkString( "PlayerSpawned" )
	if (table.Count(ents.FindByClass("light_environment")) > 0) then
		RunConsoleCommand("csm_haslightenv", "1")
	end
end
local AppearanceKeys = {
	--{ Position = 0.25, SunColor = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.02, 0.05), SkyDuskColor = Vector(0.05, 0.22, 0.18), SkySunColor = Vector(0.00, 0.00, 0.00) },
	--{ Position = 0.30, SunColor = Color(255,  11,   0, 255), SunBrightness = 40.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.31, 0.57), SkyDuskColor = Vector(0.00, 0.00, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00) },
	--{ Position = 0.35, SunColor = Color(255, 217, 179, 255), SunBrightness = 18.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.00, 0.00, 0.00) },
	--{ Position = 0.65, SunColor = Color(255, 217, 179, 255), SunBrightness = 18.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.00, 0.00, 0.00) },
	--{ Position = 0.70, SunColor = Color(255,  11,   0, 255), SunBrightness = 40.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.31, 0.57), SkyDuskColor = Vector(0.00, 0.00, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00) },
	--{ Position = 0.75, SunColor = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.02, 0.05), SkyDuskColor = Vector(0.05, 0.22, 0.18), SkySunColor = Vector(0.00, 0.00, 0.00) }
	
	--{ Position = 0.25, SunColor = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.02, 0.05), SkyDuskColor = Vector(0.05, 0.22, 0.18), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) },
	--{ Position = 0.30, SunColor = Color(255,  11,   0, 255), SunBrightness = 40.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.01, 0.00, 0.03), SkyBottomColor = Vector(0.00, 0.05, 0.11), SkyDuskColor = Vector(1.00, 0.16, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00), FogColor = Vector(153, 110, 125) },
	--{ Position = 0.35, SunColor = Color(255, 217, 179, 255), SunBrightness = 18.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 94, 148, 199) },
	--{ Position = 0.65, SunColor = Color(255, 217, 179, 255), SunBrightness = 18.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 94, 148, 199) },
	--{ Position = 0.70, SunColor = Color(255,  11,   0, 255), SunBrightness = 40.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.01, 0.00, 0.03), SkyBottomColor = Vector(0.00, 0.05, 0.11), SkyDuskColor = Vector(1.00, 0.16, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00), FogColor = Vector(153, 110, 125) },
	--{ Position = 0.75, SunColor = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.02, 0.05), SkyDuskColor = Vector(0.05, 0.22, 0.18), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) }
	
	{ Position = 0.00, SunColor = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.00, 0.00), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) },
	{ Position = 0.25, SunColor = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.03, 0.03), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) },
	{ Position = 0.30, SunColor = Color(255,  11,   0, 255), SunBrightness = 40.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.01, 0.00, 0.03), SkyBottomColor = Vector(0.00, 0.05, 0.11), SkyDuskColor = Vector(1.00, 0.16, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00), FogColor = Vector(153, 110, 125) },
	{ Position = 0.35, SunColor = Color(255, 217, 179, 255), SunBrightness = 18.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.50, SunColor = Color(255, 217, 179, 255), SunBrightness = 18.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.18, 1.00), SkyBottomColor = Vector(0.00, 0.34, 0.67), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.65, SunColor = Color(255, 217, 179, 255), SunBrightness = 18.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.70, SunColor = Color(255,  11,   0, 255), SunBrightness = 40.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.01, 0.00, 0.03), SkyBottomColor = Vector(0.00, 0.05, 0.11), SkyDuskColor = Vector(1.00, 0.16, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00), FogColor = Vector(153, 110, 125) },
	{ Position = 0.75, SunColor = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.03, 0.03), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) }
}

function warn()
	if (SERVER) then
		--lightenvs = ents.FindByClass("light_environment")
		hasLightEnvs = (table.Count(lightenvs) > 0) 
		--print(hasLightEnvs)
		--print(table.Count(lightenvs))
		if (table.Count(ents.FindByClass("light_environment")) > 0) then
			RunConsoleCommand("csm_haslightenv", "1")
		else
			RunConsoleCommand("csm_haslightenv", "0")
			--self:SetRemoveStaticSun(false)
		end
	end
	if (CLIENT) then
		if (GetConVar( "csm_haslightenv" ):GetInt() == 0) then
			Derma_Message( "This map has no named light_environments, the CSM will not look nearly as good as it could.", "CSM Alert!", "OK!" )
		end
	end
	print(hasLightEnvs)
end

function ENT:createlamps()
	self.ProjectedTextures = { }
	
	for i = 1, 3 do
		
		self.ProjectedTextures[i] = ProjectedTexture()
		--self.ProjectedTextures[i]:SetOrthographic(true,1200,1200,1200,1200)
		self.ProjectedTextures[i]:SetEnableShadows(true)
		
		if (i == 1) then
			self.ProjectedTextures[i]:SetTexture("csm/mask_center")
		else
			self.ProjectedTextures[i]:SetTexture("csm/mask_ring")
		end

	end
end
function ENT:Initialize()
	RunConsoleCommand("csm_enabled", "1")
	if (SERVER) then	
		util.AddNetworkString( "PlayerSpawned" )
	end
	if (CLIENT) then
		if (file.Read( "csm.txt", "DATA" ) != "one" ) then
			--Derma_Message( "Hello! Welcome to the CSM addon! You should raise r_flashlightdepthres else the shadows will be blocky! Make sure you've read the FAQ for troubleshooting.", "CSM Alert!", "OK!" )
			local Frame = vgui.Create( "DFrame" )
			Frame:SetSize( 300, 200 ) 
			
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

			local Button = vgui.Create("DButton", Frame)
			Button:SetText( "Continue" )
			Button:SetPos( 160, 155 )
			local Button2 = vgui.Create("DButton", Frame)
			Button2:SetText( "Cancel" )
			Button2:SetPos( 80, 155 )
			Button.DoClick = function()
				file.Write( "csm.txt", "one" )
				Frame:Close()
			end

			Button2.DoClick = function()
				RunConsoleCommand("csm_enabled", "0")
				Frame:Close()
			end
		end
	end
	RunConsoleCommand("r_projectedtexture_filter", "0.1")
	RunConsoleCommand("r_shadows_gamecontrol", "0")
	shadfiltChanged = true
	if (SERVER) then
		
		--lightenvs = ents.FindByClass("light_environment")
		hasLightEnvs = (table.Count(lightenvs) > 0) 
		if hasLightEnvs then
			self:SetRemoveStaticSun(true)
		else 
			self:SetRemoveStaticSun(false)
			timer.Create( "warn", 0.1, 1, warn)
		end
	else
		timer.Create( "warn", 0.1, 1, warn)
	end
	--print(hasLightEnvs)
	BaseClass.Initialize(self)

	self:SetMaterial("gmod/edit_sun")
	
	if (self:GetRemoveStaticSun()) then
		timer.Create( "warn", 0.1, 1, warn)
		--timer.Create( "reload", 0.1, 1, warn)
		--RunConsoleCommand("sv_cheats", "1")
		
		RunConsoleCommand("r_radiosity", "2")
		
		
		if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
			--RunConsoleCommand("mat_reloadallmaterials")
			RunConsoleCommand("r_lightstyle", "0")
			RunConsoleCommand("r_ambientlightingonly", "1")
			if (CLIENT) then
				render.RedownloadAllLightmaps(true ,true)
			end
		else
			for k, v in ipairs(ents.FindByClass( "light_environment" )) do
				v:Fire("turnoff")
			end
		end
	end

	
	if (CLIENT) then
		self:createlamps()
	end
		--hook.Add("RenderScreenspaceEffects", "CsmRenderOverlay", RenderOverlay)
		--hook.Add("SetupWorldFog", self, self.SetupWorldFog )
	
	
	if (SERVER) then
		--self.EnvSun = FindEntity("env_sun")
		--self.EnvFogController = FindEntity("env_fog_controller")
	else
		--self.EnvSun = FindEntity("C_Sun")
		--self.EnvFogController = FindEntity("C_FogController")
	end
	
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
	
	self:NetworkVar("Bool", 0, "EnableFurther", { KeyName = "Enable Futher Light", Edit = { type = "Bool", order = 7, title = "Enable further cascade for large maps"}})
	self:NetworkVar("Float", 4, "SizeFurther",  { KeyName = "Size 4", Edit = { type = "Float", order = 8, min = 0.0, max = 65536.0, title = "Further cascade size" }})
	
	self:NetworkVar("Float", 5, "Orientation", { KeyName = "Orientation", Edit = { type = "Float", order = 10, min = 0.0, max = 360.0, title = "Sun orientation" }})
	self:NetworkVar("Bool", 1, "UseMapSunAngles", { KeyName = "Use Map Sun Angles", Edit = { type = "Bool", order = 11, title = "Use the Map Sun angles"}})
	self:NetworkVar("Bool", 2, "UseSkyFogEffects", { KeyName = "Use Sky and Fog Effects", Edit = { type = "Bool", order = 12, title = "Use Sky and Fog effects"}})
	self:NetworkVar("Float", 6, "MaxAltitude", { KeyName = "Maximum altitude", Edit = { type = "Float", order = 13, min = 0.0, max = 90.0, title = "Maximum altitude" }})
	self:NetworkVar("Float", 7, "Time", { KeyName = "Time", Edit = { type = "Float", order = 14, min = 0.0, max = 1.0, title = "Time of Day" }})
	self:NetworkVar("Float", 8, "SunNearZ", { KeyName = "NearZ", Edit = { type = "Float", order = 15, min = 0.0, max = 32768.0, title = "Sun NearZ (adjust if issues)" }})
	self:NetworkVar("Float", 9, "SunFarZ", { KeyName = "FarZ", Edit = { type = "Float", order = 16, min = 0.0, max = 32768.0, title = "Sun FarZ" }})

	self:NetworkVar("Bool", 3, "RemoveStaticSun", { KeyName = "Remove Vanilla Static Sun", Edit = { type = "Bool", order = 17, title = "Remove vanilla static Sun"}})
	self:NetworkVar("Bool", 4, "HideRTTShadows", { KeyName = "Hide RTT Shadows", Edit = { type = "Bool", order = 18, title = "Hide RTT Shadows"}})
	--self:NetworkVar("Float", 10, "ShadowFilter", { KeyName = "ShadowFilter", Edit = { type = "Float", order = 19, min = 0.0, max = 10.0, title = "Shadow filter"}})
	--self:NetworkVar("Int", 3, "ShadowRes", { KeyName = "ShadowRes", Edit = { type = "Float", order = 20, min = 0.0, max = 8192.0, title = "Shadow resolution"}})

	self:NetworkVar("Bool", 5, "EnableOffsets", { KeyName = "Enable Offsets", Edit = { type = "Bool", order = 21, title = "Enable Offsets"}})
	self:NetworkVar("Int", 0, "OffsetPitch", { KeyName = "Pitch Offset", Edit = { type = "Float", order = 22, min = -180.0, max = 180.0, title = "Pitch Offset" }})
	self:NetworkVar("Int", 1, "OffsetYaw", { KeyName = "Yaw Offset", Edit = { type = "Float", order = 23, min = -180.0, max = 180.0, title = "Yaw Offset" }})
	self:NetworkVar("Int", 2, "OffsetRoll", { KeyName = "Roll Offset", Edit = { type = "Float", order = 24, min = -180.0, max = 180.0, title = "Roll Offset" }})

	if (SERVER) then
		self:SetSunColour(Vector(1.0, 0.90, 0.80, 1.0))
		if (GetConVar( "csm_hashdr" ):GetInt() == 1) then
			self:SetSunBrightness(1000.0)
		else
			self:SetSunBrightness(200.0)
		end

		self:SetSizeNear(128.0)
		self:SetSizeMid(1024.0)
		self:SetSizeFar(8192.0)
		
		self:SetEnableFurther(false)
		self:SetSizeFurther(65536.0)
		
		
		self:SetUseMapSunAngles(true)
		self:SetUseSkyFogEffects(false)
		self:SetOrientation(135.0)
		self:SetMaxAltitude(50.0)
		self:SetTime(0.5)
		self:SetSunNearZ(25000.0)
		self:SetSunFarZ(32768.0)
		
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
    if (CLIENT) then
		if (FindEntity("edit_csm") != nil) then
			FindEntity("edit_csm"):Initialize()
		end
	end
end )

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end
function SUNOff()
	if (CLIENT) then
		for k, v in ipairs(ents.FindByClass( "light_environment" )) do
			v:Fire("turnoff")
		end
		--RunConsoleCommand("r_lightstyle", "-1")
		--render.RedownloadAllLightmaps(true ,true)
	end
end
function SUNOn()
	if (CLIENT) then
		for k, v in ipairs(ents.FindByClass( "light_environment" )) do
			v:Fire("turnon")
		end
		--RunConsoleCommand("r_lightstyle", "0")
		--render.RedownloadAllLightmaps(true ,true)
	end
end

function reloadLightmaps()
	if (CLIENT) then
		render.RedownloadAllLightmaps(true ,true)
	end
end

function ENT:OnRemove()
	
	furtherEnabled = false
	furtherEnabledPrev = false
	if (self:GetHideRTTShadows()) then
		RunConsoleCommand("r_shadows_gamecontrol", "1")
	end
	RunConsoleCommand("r_projectedtexture_filter", "1")
		
	if (self:GetRemoveStaticSun()) then
		--RunConsoleCommand("sv_cheats", "1")
		
		RunConsoleCommand("r_radiosity", "3")
		
		
		if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
			--RunConsoleCommand("mat_reloadallmaterials")
			--if (CLIENT) then
			RunConsoleCommand("r_ambientlightingonly", "0")

			RunConsoleCommand("r_lightstyle", "-1")
			timer.Create( "reload", 0.1, 1, reloadLightmaps )
			--timer.Simple(0.0001, function()
				--render.RedownloadAllLightmaps(true ,true)
			--end)
			--end
		else
			for k, v in ipairs(ents.FindByClass( "light_environment" )) do
				v:Fire("turnon")
			end
		end
	end
	if (CLIENT) then
		for i, projectedTexture in pairs(self.ProjectedTextures) do
			projectedTexture:Remove()
		end
		
		table.Empty(self.ProjectedTextures)
		
		--hook.Remove("CsmRenderOverlay")
	end
end

hook.Add( "ShadnowFilterChange", "shadfiltchanged", function()
	shadfiltChanged = true
end)

function ENT:Think()
	shadfiltChanged = false

	

	furtherEnabled = self:GetEnableFurther()
	if (furtherEnabledPrev != furtherEnabled) then
		if (furtherEnabled) then
			if (CLIENT) then
				self.ProjectedTextures[4] = ProjectedTexture()
				self.ProjectedTextures[4]:SetEnableShadows(false)
				
			end
			furtherEnabledPrev = true
		else
			if (CLIENT) then
				if (self.ProjectedTextures[4]:IsValid()) then
					self.ProjectedTextures[4]:Remove()
				end
				
			end
			furtherEnabledPrev = false
		end
	end
	if (GetConVar( "csm_enabled" ):GetInt() == 1) then
		if (csmEnabledPrev == true) then
			csmEnabledPrev = false
			RunConsoleCommand("r_radiosity", "2")
			if (self:GetHideRTTShadows()) then
				RunConsoleCommand("r_shadows_gamecontrol", "0")
			end
			for k, v in ipairs(ents.FindByClass( "light_environment" )) do
				v:Fire("turnoff")
				if (GetConVar( "csm_hashdr" ):GetInt() == 1) then
					self:SetSunBrightness(1000.0)
				else
					self:SetSunBrightness(200.0)
				end
			end
			
		end
	end

	if (GetConVar( "csm_enabled" ):GetInt() == 0) then
		if (csmEnabledPrev == false) then
			csmEnabledPrev = true
			RunConsoleCommand("r_radiosity", "3")
			if (self:GetHideRTTShadows()) then
				RunConsoleCommand("r_shadows_gamecontrol", "1")
			end
			for k, v in ipairs(ents.FindByClass( "light_environment" )) do
				v:Fire("turnon")
				self:SetSunBrightness(0.0)
			end
		end
	end
	local removestatsun = self:GetRemoveStaticSun()
	
	if (RemoveStaticSunPrev != removestatsun) then
		
		if (self:GetRemoveStaticSun()) then
			timer.Create( "warn", 0.1, 1, warn)
			--RunConsoleCommand("sv_cheats", "1")
			
			
			RunConsoleCommand("r_radiosity", "2")
			
			if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
				--RunConsoleCommand("mat_reloadallmaterials")
				if (CLIENT) then
					RunConsoleCommand("r_ambientlightingonly", "1")
					RunConsoleCommand("r_lightstyle", "0")
					render.RedownloadAllLightmaps(true ,true)
					--timer.Create( "reload", 0.1, 1, reloadLightmaps )
					
					timer.Create( "reload", 0.1, 1, reloadLightmaps)
				end
			else
				for k, v in ipairs(ents.FindByClass( "light_environment" )) do
					v:Fire("turnoff")
				end
			end
		else
			RunConsoleCommand("r_radiosity", "3")
			if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
				--RunConsoleCommand("mat_reloadallmaterials")
				if (CLIENT) then
					--render.RedownloadAllLightmaps(true ,true)
					RunConsoleCommand("r_lightstyle", "-1")
					RunConsoleCommand("r_ambientlightingonly", "0")
					timer.Create( "reload", 0.1, 1, reloadLightmaps)
				end
			else
				for k, v in ipairs(ents.FindByClass( "light_environment" )) do
					v:Fire("turnon")
				end
			end
		end
		
		RemoveStaticSunPrev = removestatsun
	end

	local hiderttshad = self:GetHideRTTShadows()
	if (HideRTTShadowsPrev != hiderttshad) then
		
		if (self:GetHideRTTShadows()) then
			RunConsoleCommand("r_shadows_gamecontrol", "0")
		else
		
			RunConsoleCommand("r_shadows_gamecontrol", "1")
	
		end
		HideRTTShadowsPrev = hiderttshad
	end

	--local shadres = self:GetShadowRes()
	--if (ShadowResPrev != shadres) then
		--ShadowResPrev = shadres
		--shadfiltChanged = true
		--RunConsoleCommand("r_flashlightdepthres", shadres)
		
	--end

	local shadfilt = GetConVar( "r_projectedtexture_filter" ):GetFloat()
	if (ShadowFilterPrev != shadfilt) then
		ShadowFilterPrev = shadfilt
		shadfiltChanged = true
		RunConsoleCommand("csm_filter", shadfilt)
		
	end
	--if (ShadowFilterPrev != GetConVar( "csm_filter" ):GetFloat()) then
		--shadfiltChanged = true
	--end
	--if (temp == nil) then temp = 0.0 end
	--self:SetTime((temp + (CurTime() * 0.01)) % 1.0)

	local pitch = 0
	local yaw = 0
	local roll = 0
	
	local usemapangles = false
	if (self:GetUseMapSunAngles()) then
		usemapangles = true
	else 
		usemapangles = false
	end

	if (CLIENT) then
		sun = util.GetSunInfo()
	else 
		if (usemapangles) then
			--self:SetTime(0)
			--self:SetOrientation(0)
		end
	end
	


	if (usemapangles) then
		pitch = 0
		yaw = 0
		roll = 0
		if( sun != nil ) then
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
			--print(sun.direction:Angle().pitch)
			--print(yaw)
			--print(roll)
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
	
	offset = offset * self:GetSunFarZ()
	if (usemapangles) then
		self.CurrentAppearance = CalculateAppearance((pitch + -180) / 360)
	else
		self.CurrentAppearance = CalculateAppearance(self:GetTime())
	end
	if (CLIENT) then
		local position = GetViewEntity():GetPos() + offset

		self.ProjectedTextures[1]:SetOrthographic(true, self:GetSizeNear(), self:GetSizeNear(), self:GetSizeNear(), self:GetSizeNear())
		self.ProjectedTextures[2]:SetOrthographic(true, self:GetSizeMid(),  self:GetSizeMid(),  self:GetSizeMid(),  self:GetSizeMid())
		self.ProjectedTextures[3]:SetOrthographic(true, self:GetSizeFar(),  self:GetSizeFar(),  self:GetSizeFar(),  self:GetSizeFar())
		
		if (furtherEnabled) then
			if (self.ProjectedTextures[4]:IsValid()) then
				self.ProjectedTextures[4]:SetOrthographic(true, self:GetSizeFurther(),  self:GetSizeFurther(),  self:GetSizeFurther(),  self:GetSizeFurther())
			end
		end
		for i, projectedTexture in pairs(self.ProjectedTextures) do
			if (shadfiltChanged) then
				projectedTexture:SetShadowFilter(GetConVar( "csm_filter" ):GetFloat())
			end
			--projectedTexture:SetColor(self.CurrentAppearance.SunColour)
			--projectedTexture:SetBrightness(self.CurrentAppearance.SunBrightness * PROJECTION_BRIGHTNESS_MULTIPLIER)
			
			if (GetConVar( "csm_stormfox_coloured_sun" ):GetInt() == 0) then
				projectedTexture:SetColor(self:GetSunColour():ToColor()) --csm_stormfox_coloured_sun
			else
				projectedTexture:SetColor(self.CurrentAppearance.SunColour)
			end
			--if (sun.direction:Angle().pitch < 360) then
				--projectedTexture:SetBrightness(self:GetSunBrightness() - (pitch + 340) * 8.5) 
			--elseif (sun.direction:Angle().pitch < 270) then
				--projectedTexture:SetBrightness(self:GetSunBrightness() - (pitch + 20) * 8.5)
			--else
				--projectedTexture:SetBrightness(self:GetSunBrightness())
			--end
			if (GetConVar( "csm_stormfoxsupport" ):GetInt() == 0) then
				projectedTexture:SetBrightness(self:GetSunBrightness())
			else 
				projectedTexture:SetBrightness(self.CurrentAppearance.SunBrightness * GetConVar( "csm_stormfox_brightness_multiplier" ):GetInt())
			end
			projectedTexture:SetPos(position)
			projectedTexture:SetAngles(angle)
			projectedTexture:SetNearZ(self:GetSunNearZ())
			projectedTexture:SetFarZ(self:GetSunFarZ() + 16384)
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

function RenderOverlay()
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
