include("shared.lua")
DEFINE_BASECLASS("base_edit_csm")

include("realcsm/convars.lua")
include("realcsm/util.lua")
include("realcsm/rtt.lua")
include("realcsm/skyboxfix.lua")
include("realcsm/spread.lua")

local Util      = RealCSM.Util
local RTT       = RealCSM.RTT
local SkyboxFix = RealCSM.SkyboxFix

-- ── Per-entity state (reset in Initialize, updated in Think) ─────────────────
-- We keep these as entity fields (self.*Prev) rather than file-level locals so
-- that if two CSM entities briefly coexist during map cleanup there's no crosstalk.

-- ── Spread / light allocation ─────────────────────────────────────────────────

function ENT:allocLights()
	local samples = GetConVar("csm_spread_samples"):GetInt()
	local radius  = GetConVar("csm_spread_radius"):GetFloat()
	local method  = GetConVar("csm_spread_method"):GetInt()

	local legacyParams = {
		layers        = GetConVar("csm_spread_layers"):GetInt(),
		density       = GetConVar("csm_spread_layer_density"):GetFloat(),
		reserveMiddle = GetConVar("csm_spread_layer_reservemiddle"):GetBool(),
		allocType     = GetConVar("csm_spread_layer_alloctype"):GetInt(),
	}

	self._lightPoints = RealCSM.Spread.GetPoints(method, samples, radius, legacyParams)
end

-- ── ProjectedTexture creation ─────────────────────────────────────────────────

function ENT:createLamps()
	self.ProjectedTextures = {}

	local cascadeCount   = GetConVar("csm_cascade_count"):GetInt()
	local furtherEnabled = GetConVar("csm_further"):GetBool()
	local harshCutoff    = GetConVar("csm_harshcutoff"):GetBool()
	local spreadEnabled  = GetConVar("csm_spread"):GetBool()

	-- Single cascade mode (count=1): one full-frame PT, no ring masks.
	if cascadeCount == 1 then
		self.ProjectedTextures[1] = ProjectedTexture()
		self.ProjectedTextures[1]:SetEnableShadows(true)
		self.ProjectedTextures[1]:SetTexture("csm/mask_center")
		RealCSM.Lamps = self.ProjectedTextures
		return
	end

	-- Cascade 1 (near): skipped in perf mode (count=2).
	self.ProjectedTextures[1] = ProjectedTexture()
	self.ProjectedTextures[1]:SetEnableShadows(true)
	self.ProjectedTextures[1]:SetTexture("csm/mask_center")
	if cascadeCount == 2 then
		self.ProjectedTextures[1]:Remove()
		self.ProjectedTextures[1] = nil
	end

	-- Cascade 2 (mid): acts as near in perf/2-cascade mode; center for spread.
	self.ProjectedTextures[2] = ProjectedTexture()
	self.ProjectedTextures[2]:SetEnableShadows(true)
	if cascadeCount == 2 or spreadEnabled then
		self.ProjectedTextures[2]:SetTexture("csm/mask_center")
	else
		self.ProjectedTextures[2]:SetTexture("csm/mask_ring")
	end

	-- Cascade 3 (far).
	self.ProjectedTextures[3] = ProjectedTexture()
	self.ProjectedTextures[3]:SetEnableShadows(true)
	if furtherEnabled or not harshCutoff then
		self.ProjectedTextures[3]:SetTexture("csm/mask_ring")
	else
		self.ProjectedTextures[3]:SetTexture("csm/mask_end")
	end

	-- Spread sample lights (indices 5+).
	if spreadEnabled then
		self:allocLights()
		local extra = GetConVar("csm_spread_samples"):GetInt() - 2
		for i = 1, extra do
			self.ProjectedTextures[4 + i] = ProjectedTexture()
			self.ProjectedTextures[4 + i]:SetEnableShadows(true)
			self.ProjectedTextures[4 + i]:SetTexture("csm/mask_center")
		end
	end

	-- Expose lamps globally so other addons can read them.
	-- RealCSM.Lamps is a read-only view; don't modify it externally.
	RealCSM.Lamps = self.ProjectedTextures
end

-- ── Shadow depth buffer upgrade ────────────────────────────────────────────────────
-- Re-registers GMod's shadow depth render targets with a higher bit-depth format.
-- D24 gives better precision, reducing shadow acne on large cascades.
-- This is a one-shot operation: re-running has no effect; only a game restart undoes it.
-- Called with pcall so a failure on unsupported GPUs doesn't break anything.
local _depthFormatUpgraded = false
local function UpgradeDepthFormat(want24)
	if _depthFormatUpgraded then return end
	if not want24 then return end  -- D16 = default, nothing to do

	-- Format IDs differ between x86-64 (CS:GO era) and x86 (TF2 era) branches.
	local fmt
	if BRANCH == "x86-64" then
		fmt = 48  -- IMAGE_FORMAT_D24X8_SHADOW
	else
		fmt = 31  -- IMAGE_FORMAT_NV_DST24
	end

	local size    = GetConVar("r_flashlightdepthres"):GetInt()
	if size <= 0 then size = 1024 end
	local rtFlags = render.GetHDREnabled() and CREATERENDERTARGETFLAGS_HDR or 0

	local ok, err = pcall(function()
		for i = 0, 7 do  -- cover up to 8 shadow maps (spread mode can use more)
			GetRenderTargetEx(
				"_rt_shadowdepthtexture_" .. i,
				size, size,
				RT_SIZE_LITERAL,
				MATERIAL_RT_DEPTH_ONLY,
				bit.bor(1, 4, 8),
				rtFlags,
				fmt
			)
		end
	end)

	if ok then
		print("[Real CSM] Shadow depth buffer upgraded to D24 (" .. (BRANCH == "x86-64" and "D24X8_SHADOW" or "NV_DST24") .. ")")
		_depthFormatUpgraded = true
	else
		print("[Real CSM] Depth buffer upgrade failed (non-fatal): " .. tostring(err))
	end
end

-- ── Initialize ────────────────────────────────────────────────────────────────

function ENT:Initialize()
	-- Per-entity state tracking (avoids file-level globals).
	self._prevRemoveStaticSun       = false
	self._prevHideRTTShadows        = false
	self._prevBlobShadows           = false
	self._prevShadowFilter          = -1
	self._prevCSMEnabled            = false
	self._prevFurther               = false
	self._prevFurtherShadows        = false
	self._prevHarshCutoff           = false
	self._prevFarShadows            = true
	self._prevSpreadEnabled         = false
	self._prevSpreadSamples         = GetConVar("csm_spread_samples"):GetInt()
	self._prevSpreadLayers          = GetConVar("csm_spread_layers"):GetInt()
	self._prevSpreadRadius          = GetConVar("csm_spread_radius"):GetFloat()
	self._prevSpreadMethod          = GetConVar("csm_spread_method"):GetInt()
	self._prevPropRadiosity         = -1
	self._prevCascadeCount          = GetConVar("csm_cascade_count"):GetInt()
	self._prevFPShadows             = not GetConVar("csm_localplayershadow"):GetBool()
	self._lightPoints               = {}
	self._warnedNoSun               = false
	-- Save r_radiosity before we touch it so we can restore it on remove/disable.
	self._prevRadiosity             = GetConVar("r_radiosity"):GetString()

	self:SetMaterial("csm/edit_csm")
	BaseClass.Initialize(self)

	-- HDR detection (update the cvar for the entity's brightness logic).
	RunConsoleCommand("csm_hashdr", render.GetHDREnabled() and "1" or "0")

	-- Skybox far-plane fix.
	SkyboxFix.On()

	-- RTT initial state.
	if not GetConVar("csm_blobbyao"):GetBool() then
		RTT.Disable()
	end

	RunConsoleCommand("csm_enabled", "1")
	self._prevCSMEnabled = true -- already setting up, don't double-create lamps in Think

	-- Warn if no light_environment.
	timer.Simple(0.1, function()
		if not IsValid(self) then return end
		self:_warnLightEnv()
	end)

	-- First-time-spawn UI (distinct from first-time-load; marks file as "two").
	if file.Read("realcsm.txt", "DATA") ~= "two" then
		self:_showFirstTimeSpawnUI()
	end

	-- Apply radiosity if sun is removed.
	if self:GetRemoveStaticSun() then
		RunConsoleCommand("r_radiosity", GetConVar("csm_propradiosity"):GetString())
		if GetConVar("csm_wakeprops"):GetBool() then
			net.Start("RealCSMPropWakeup")
			net.SendToServer()
		end
		if GetConVar("csm_legacydisablesun"):GetInt() == 1 then
			RunConsoleCommand("r_ambientlightingonly", "1")
			RunConsoleCommand("r_lightstyle", "0")
			timer.Simple(0.1, function()
				if render then render.RedownloadAllLightmaps(false, true) end
			end)
		end
	end

	-- Upgrade shadow depth buffer to D24 if configured (one-shot).
	UpgradeDepthFormat(GetConVar("csm_depthformat"):GetInt() == 24)

	self:createLamps()
end

-- ── Warning helpers ────────────────────────────────────────────────────────────

function ENT:_warnLightEnv()
	if GetConVar("csm_haslightenv"):GetInt() == 0
	   and not GetConVar("csm_disable_warnings"):GetBool() then
		Derma_Message(
			"This map has no named light_environment. CSM will not look as good as it could.",
			"CSM Alert!", "OK!"
		)
	end
end

-- ── First-time spawn UI ───────────────────────────────────────────────────────

function ENT:_showFirstTimeSpawnUI()
	RunConsoleCommand("r_flashlightdepthres", "1024")

	local Frame = vgui.Create("DFrame")
	Frame:SetSize(330, 290)
	Frame:Center()
	Frame:SetTitle("CSM First Time Spawn!")
	Frame:SetVisible(true)
	Frame:SetDraggable(false)
	Frame:ShowCloseButton(true)
	Frame:MakePopup()

	local function lbl(text, x, y, w)
		local l = vgui.Create("DLabel", Frame)
		l:SetPos(x, y)
		l:SetSize(w or 300, 20)
		l:SetText(text)
		return l
	end

	lbl("Welcome to Real CSM!",                                           15, 40)
	lbl("This is your first time spawning CSM. Go set your quality!",     15, 70)
	lbl("Refer to the F.A.Q for troubleshooting and help!",               15, 85)
	lbl("More settings are in the spawnmenu's \"Utilities\" tab.",        15, 100)

	local slider = vgui.Create("DNumSlider", Frame)
	slider:SetPos(15, 130)
	slider:SetSize(300, 30)
	slider:SetText("Shadow Quality")
	slider:SetMin(0)
	slider:SetMax(8192)
	slider:SetDecimals(0)
	slider:SetConVar("r_flashlightdepthres")

	local function makeQualityButton(label, x, res)
		local btn = vgui.Create("DButton", Frame)
		btn:SetText(label)
		btn:SetPos(x, 160)
		btn.DoClick = function() RunConsoleCommand("r_flashlightdepthres", res) end
	end
	makeQualityButton("Low",    15,  "2048")
	makeQualityButton("Medium", 135, "4096")
	makeQualityButton("High",   255, "8192")

	local perfCheck = vgui.Create("DCheckBoxLabel", Frame)
	perfCheck:SetText("Performance Mode")
	perfCheck:SetPos(15, 195)
	perfCheck:SetSize(300, 30)
	perfCheck:SetTextColor(Color(255,255,255))
	perfCheck:SetConVar("csm_perfmode")

	local perfLbl = vgui.Create("DLabel", Frame)
	perfLbl:SetPos(39, 215)
	perfLbl:SetSize(300, 20)
	perfLbl:SetTextColor(Color(180,180,180))
	perfLbl:SetText("Use fewer shadow cascades for better performance.")

	local continueBtn = vgui.Create("DButton", Frame)
	continueBtn:SetText("Continue")
	continueBtn:SetPos(175, 250)
	continueBtn.DoClick = function()
		file.Write("realcsm.txt", "two")
		Frame:Close()
	end

	local cancelBtn = vgui.Create("DButton", Frame)
	cancelBtn:SetText("Cancel")
	cancelBtn:SetPos(95, 250)
	cancelBtn.DoClick = function()
		RunConsoleCommand("csm_enabled", "0")
		Frame:Close()
	end
end

-- ── OnRemove ──────────────────────────────────────────────────────────────────

function ENT:OnRemove()
	SkyboxFix.Off()

	if RealCSM.FPShadowController and RealCSM.FPShadowController:IsValid() then
		RealCSM.FPShadowController:Remove()
		RealCSM.FPShadowController = nil
	end

	if GetConVar("csm_spawnalways"):GetInt() == 0 then
		if self:GetHideRTTShadows() then RTT.Enable() end

		if GetConVar("csm_blobbyao"):GetBool() then
			RunConsoleCommand("r_shadowrendertotexture", "1")
			RunConsoleCommand("r_shadowdist", "10000")
		end

		if self:GetRemoveStaticSun() then
			RunConsoleCommand("r_radiosity", self._prevRadiosity or "4")
			if GetConVar("csm_wakeprops"):GetBool() then
				net.Start("RealCSMPropWakeup")
				net.SendToServer()
			end
			if GetConVar("csm_legacydisablesun"):GetInt() == 1 then
				RunConsoleCommand("r_ambientlightingonly", "0")
				RunConsoleCommand("r_lightstyle", "-1")
				timer.Simple(0.1, function()
					if render then render.RedownloadAllLightmaps(false, true) end
				end)
			end
			-- Server Think watches csm_enabled and calls SUNOn() when it changes.
		end
	end

	if self.ProjectedTextures then
		for _, pt in pairs(self.ProjectedTextures) do
			if IsValid(pt) then pt:Remove() end
		end
		self.ProjectedTextures = nil
	end

	-- Clear the global lamp reference when CSM is removed.
	RealCSM.Lamps = nil
end

-- ── Think ──────────────────────────────────────────────────────────────────────

function ENT:Think()
	local csmEnabled = GetConVar("csm_enabled"):GetInt() == 1

	-- ── CSM enabled toggle ────────────────────────────────────────────────────
	if csmEnabled and not self._prevCSMEnabled then
		self._prevFurtherShadows = not GetConVar("csm_furthershadows"):GetBool()
		self._prevFurther        = not GetConVar("csm_further"):GetBool()
		self._prevCSMEnabled     = true

		if self:GetRemoveStaticSun() then
			if GetConVar("csm_legacydisablesun"):GetInt() == 1 then
				RunConsoleCommand("r_ambientlightingonly", "1")
				RunConsoleCommand("r_lightstyle", "1")
				timer.Simple(0.1, function()
					if render then render.RedownloadAllLightmaps(false, true) end
				end)
			end
			-- Server handles actual SUNOff.
		end

		RunConsoleCommand("r_radiosity", GetConVar("csm_propradiosity"):GetString())
		if GetConVar("csm_wakeprops"):GetBool() then
			net.Start("RealCSMPropWakeup")
			net.SendToServer()
		end

		if self:GetHideRTTShadows() then
			RTT.Disable()
			self._prevBlobShadows = false
		end
		if GetConVar("csm_blobbyao"):GetBool() then
			RTT.Enable()
			RunConsoleCommand("r_shadowrendertotexture", "0")
			RunConsoleCommand("r_shadowdist", "20")
		end

		self:createLamps()
	end

	if not csmEnabled and self._prevCSMEnabled then
		self._prevCSMEnabled = false

		if self:GetRemoveStaticSun() then
			if GetConVar("csm_legacydisablesun"):GetInt() == 1 then
				RunConsoleCommand("r_ambientlightingonly", "0")
				RunConsoleCommand("r_lightstyle", "-1")
				timer.Simple(0.1, function()
					if render then render.RedownloadAllLightmaps(false, true) end
				end)
			end
		end

		RunConsoleCommand("r_radiosity", self._prevRadiosity or "4")
		if GetConVar("csm_wakeprops"):GetBool() then
			net.Start("RealCSMPropWakeup")
			net.SendToServer()
		end
		RunConsoleCommand("r_shadowrendertotexture", "1")
		RunConsoleCommand("r_shadowdist", "10000")
		if self:GetHideRTTShadows() then RTT.Enable() end

		-- Reload lightmaps so static lighting comes back after sun was removed.
		timer.Simple(0.1, function()
			if render then render.RedownloadAllLightmaps(false, true) end
		end)

		if self.ProjectedTextures then
			for _, pt in pairs(self.ProjectedTextures) do
				if IsValid(pt) then pt:Remove() end
			end
			table.Empty(self.ProjectedTextures)
		end
	end

	-- ── Prop radiosity ─────────────────────────────────────────────────────────
	local propRad = GetConVar("csm_propradiosity"):GetString()
	if self._prevPropRadiosity ~= propRad and csmEnabled then
		RunConsoleCommand("r_radiosity", propRad)
		if GetConVar("csm_wakeprops"):GetBool() then
			net.Start("RealCSMPropWakeup")
			net.SendToServer()
		end
		self._prevPropRadiosity = propRad
	end

	if not csmEnabled then return end

	-- ── FP shadows ─────────────────────────────────────────────────────────────
	local fpShadows = GetConVar("csm_localplayershadow"):GetBool()
	if self._prevFPShadows ~= fpShadows then
		if fpShadows then
			RealCSM.FPShadowController = ents.CreateClientside("csm_pseudoplayer")
			if IsValid(RealCSM.FPShadowController) then
				RealCSM.FPShadowController:Spawn()
			end
		else
			if IsValid(RealCSM.FPShadowController) then
				RealCSM.FPShadowController:Remove()
				RealCSM.FPShadowController = nil
			end
		end
		self._prevFPShadows = fpShadows
	end

	-- ── Harsh cutoff ───────────────────────────────────────────────────────────
	local harshCutoff = GetConVar("csm_harshcutoff"):GetBool()
	if self._prevHarshCutoff ~= harshCutoff then
		local further = GetConVar("csm_further"):GetBool()
		local lastCascade = (further and self.ProjectedTextures[4]) and 4 or 3
		if self.ProjectedTextures and IsValid(self.ProjectedTextures[lastCascade]) then
			self.ProjectedTextures[lastCascade]:SetTexture(
				harshCutoff and "csm/mask_end" or "csm/mask_ring"
			)
		end
		self._prevHarshCutoff = harshCutoff
	end

	-- ── Further cascade toggle ──────────────────────────────────────────────────
	local furtherEnabled = GetConVar("csm_further"):GetBool()
	if self._prevFurther ~= furtherEnabled then
		if furtherEnabled then
			self.ProjectedTextures[4] = ProjectedTexture()
			local furtherShadows = GetConVar("csm_furthershadows"):GetBool()
			self.ProjectedTextures[4]:SetEnableShadows(furtherShadows)
			if harshCutoff then
				self.ProjectedTextures[3]:SetTexture("csm/mask_ring")
				self.ProjectedTextures[4]:SetTexture("csm/mask_end")
			else
				self.ProjectedTextures[4]:SetTexture("csm/mask_ring")
				self.ProjectedTextures[3]:SetTexture("csm/mask_ring")
			end
		else
			if IsValid(self.ProjectedTextures[4]) then
				self.ProjectedTextures[4]:Remove()
				self.ProjectedTextures[4] = nil
				if IsValid(self.ProjectedTextures[3]) then
					self.ProjectedTextures[3]:SetTexture(
						harshCutoff and "csm/mask_end" or "csm/mask_ring"
					)
				end
			end
		end
		self._prevFurther = furtherEnabled
	end

	-- ── Spread sample count change ──────────────────────────────────────────────
	local spreadSamples = GetConVar("csm_spread_samples"):GetInt()
	if self._prevSpreadSamples ~= spreadSamples then
		for _, pt in pairs(self.ProjectedTextures or {}) do
			if IsValid(pt) then pt:Remove() end
		end
		self.ProjectedTextures = {}
		self:createLamps()
		self._prevSpreadSamples = spreadSamples
	end

	-- ── Spread layer / radius / method change (recompute angle table) ────────────
	local spreadLayers = GetConVar("csm_spread_layers"):GetInt()
	local spreadRadius = GetConVar("csm_spread_radius"):GetFloat()
	local spreadMethod = GetConVar("csm_spread_method"):GetInt()
	if self._prevSpreadLayers ~= spreadLayers or self._prevSpreadRadius ~= spreadRadius or self._prevSpreadMethod ~= spreadMethod then
		self:allocLights()
		self._prevSpreadLayers = spreadLayers
		self._prevSpreadRadius = spreadRadius
		self._prevSpreadMethod = spreadMethod
	end

	-- ── Single cascade toggle ───────────────────────────────────────────────────
	local cascadeCount = GetConVar("csm_cascade_count"):GetInt()
	if self._prevCascadeCount ~= cascadeCount and csmEnabled then
		for _, pt in pairs(self.ProjectedTextures or {}) do
			if IsValid(pt) then pt:Remove() end
		end
		self.ProjectedTextures = {}
		self:createLamps()
		self._prevCascadeCount = cascadeCount
	end


	-- ── Spread enabled toggle ──────────────────────────────────────────────────
	local spreadEnabled = GetConVar("csm_spread"):GetBool()
	if self._prevSpreadEnabled ~= spreadEnabled and csmEnabled then
		if spreadEnabled then
			if self.ProjectedTextures and IsValid(self.ProjectedTextures[2]) then
				self.ProjectedTextures[2]:SetTexture("csm/mask_center")
				local extra = GetConVar("csm_spread_samples"):GetInt() - 2
				for i = 1, extra do
					self.ProjectedTextures[4 + i] = ProjectedTexture()
					self.ProjectedTextures[4 + i]:SetEnableShadows(true)
					self.ProjectedTextures[4 + i]:SetTexture("csm/mask_center")
				end
			end
		else
			for _, pt in pairs(self.ProjectedTextures or {}) do
				if IsValid(pt) then pt:Remove() end
			end
			self.ProjectedTextures = {}
			self:createLamps()
		end
		self._prevSpreadEnabled = spreadEnabled
	end

	-- ── Further shadows toggle ─────────────────────────────────────────────────
	local furtherShadows = GetConVar("csm_furthershadows"):GetBool()
	if self._prevFurtherShadows ~= furtherShadows then
		if self.ProjectedTextures and IsValid(self.ProjectedTextures[4]) then
			self.ProjectedTextures[4]:SetEnableShadows(furtherShadows)
		end
		self._prevFurtherShadows = furtherShadows
	end

	-- ── Far cascade shadows toggle ("super perf mode") ─────────────────────────
	-- csm_farshadows=1 = SUPER PERF MODE (shadows OFF); 0 = shadows ON.
	local superPerfMode = GetConVar("csm_farshadows"):GetBool()
	if self._prevFarShadows ~= superPerfMode then
		if self.ProjectedTextures and IsValid(self.ProjectedTextures[3]) then
			self.ProjectedTextures[3]:SetEnableShadows(not superPerfMode)
		end
		self._prevFarShadows = superPerfMode
	end

	-- ── csm_nofar: kill cascade 3 if requested ────────────────────────────────
	if GetConVar("csm_nofar"):GetBool() then
		if self.ProjectedTextures and IsValid(self.ProjectedTextures[3]) then
			self.ProjectedTextures[3]:Remove()
			self.ProjectedTextures[3] = nil
		end
	end

	-- ── Static sun network var change ──────────────────────────────────────────
	local removeStaticSun = self:GetRemoveStaticSun()
	if self._prevRemoveStaticSun ~= removeStaticSun then
		if removeStaticSun then
			timer.Simple(0.1, function()
				if IsValid(self) then self:_warnLightEnv() end
			end)
			RunConsoleCommand("r_radiosity", GetConVar("csm_propradiosity"):GetString())
			if GetConVar("csm_wakeprops"):GetBool() then
				net.Start("RealCSMPropWakeup")
				net.SendToServer()
			end
			if GetConVar("csm_legacydisablesun"):GetInt() == 1 then
				RunConsoleCommand("r_ambientlightingonly", "1")
				RunConsoleCommand("r_lightstyle", "0")
				timer.Simple(0.1, function()
					if render then render.RedownloadAllLightmaps(false, true) end
				end)
			end
			-- Server handles SUNOff.
		else
			RunConsoleCommand("r_radiosity", self._prevRadiosity or "4")
			if GetConVar("csm_wakeprops"):GetBool() then
				net.Start("RealCSMPropWakeup")
				net.SendToServer()
			end
			if GetConVar("csm_legacydisablesun"):GetInt() == 1 then
				RunConsoleCommand("r_ambientlightingonly", "0")
				RunConsoleCommand("r_lightstyle", "-1")
				timer.Simple(0.1, function()
					if render then render.RedownloadAllLightmaps(false, true) end
				end)
			end
			-- Server handles SUNOn.
		end
		self._prevRemoveStaticSun = removeStaticSun
	end

	-- ── RTT / blob shadows ─────────────────────────────────────────────────────
	local hideRTT    = self:GetHideRTTShadows()
	local blobShadows = GetConVar("csm_blobbyao"):GetBool()

	if self._prevHideRTTShadows ~= hideRTT and not blobShadows then
		if hideRTT then RTT.Disable() else RTT.Enable() end
		self._prevHideRTTShadows = hideRTT
	end

	if self._prevBlobShadows ~= blobShadows and csmEnabled then
		self._prevBlobShadows = blobShadows
		if blobShadows then
			self._prevHideRTTShadows = true
			RunConsoleCommand("r_shadowrendertotexture", "0")
			RunConsoleCommand("r_shadowdist", "20")
			RTT.Enable()
		else
			RunConsoleCommand("r_shadowrendertotexture", "1")
			RunConsoleCommand("r_shadowdist", "10000")
			if hideRTT then RTT.Disable() else RTT.Enable() end
		end
	end

	-- ── Sun angle calculation ──────────────────────────────────────────────────
	-- Priority: server-pushed RealCSM.ServerSunInfo, then util.GetSunInfo(),
	-- then shadow_control, then manual entity settings.
	local pitch, yaw, roll = 0, 0, 0

	if self:GetUseMapSunAngles() then
		-- Check for a server-broadcast sun (e.g. from a custom day/night addon).
		if RealCSM.ServerSunInfo then
			local si = RealCSM.ServerSunInfo
			pitch = si.pitch
			yaw   = si.yaw
			roll  = si.roll
		else
			local sunInfo = util.GetSunInfo()
			if sunInfo then
				local ang = sunInfo.direction:Angle()
				pitch = ang.pitch + 90
				yaw   = ang.yaw
				roll  = ang.roll
			else
				local shadowCtrl = ents.FindByClass("shadow_control")[1]
				if shadowCtrl then
					print("[Real CSM] - No env_sun; using shadow_control angles.")
					local ang = shadowCtrl:GetAngles()
					pitch = ang.pitch + 90
					yaw   = ang.yaw
					roll  = ang.roll
				else
					if not self._warnedNoSun and not GetConVar("csm_disable_warnings"):GetBool() then
						Derma_Message(
							"This map has no env_sun. CSM cannot find the sun position!",
							"CSM Alert!", "OK!"
						)
						self._warnedNoSun = true
					end
					pitch = -180.0 + (self:GetTime() * 360.0)
					yaw   = self:GetOrientation()
					roll  = 90.0 - self:GetMaxAltitude()
				end
			end
		end
	else
		pitch = -180.0 + (self:GetTime() * 360.0)
		yaw   = self:GetOrientation()
		roll  = 90.0 - self:GetMaxAltitude()
	end

	if self:GetEnableOffsets() then
		pitch = pitch + self:GetOffsetPitch()
		yaw   = yaw   + self:GetOffsetYaw()
		roll  = roll  + self:GetOffsetRoll()
	end

	-- Build sun direction vectors.
	local offset = Vector(0, 0, 1)
	offset:Rotate(Angle(pitch, 0, 0))
	offset:Rotate(Angle(0, yaw, roll))

	local sunAngle = (vector_origin - offset):Angle()
	local appearance

	if self:GetUseMapSunAngles() then
		appearance = Util.CalculateAppearance((pitch + -180) / 360)
	else
		appearance = Util.CalculateAppearance(self:GetTime())
	end
	self.CurrentAppearance = appearance

	-- Debug cascade colours (rebuilt each tick; cheap table of known colours).
	local debugColours = {
		Color(  0, 255,   0, 255),
		Color(255,   0,   0, 255),
		Color(255, 255,   0, 255),
		Color(  0,   0, 255, 255),
		Color(  0, 255, 255, 255),
		Color(255,   0, 255, 255),
		Color(255, 255, 255, 255),
	}

	-- ── ProjectedTexture update ────────────────────────────────────────────────
	if not csmEnabled or GetConVar("csm_update"):GetInt() ~= 1 then return end

	if not self.ProjectedTextures then self:createLamps() end

	local viewPos = GetViewEntity():GetPos()
	local position = viewPos + offset * self:GetHeight()

	-- ── Texel snapping ───────────────────────────────────────────────────────────
	-- Snaps position to the shadow-map texel grid in light space, eliminating
	-- sub-texel shadow shimmer as the camera moves.
	--
	-- KEY: all cascades snap to the SAME grid (the largest/coarsest cascade's
	-- texel size). If each cascade snaps independently to its own finer grid,
	-- the cascade mask boundaries drift relative to each other at low resolutions
	-- causing a visible flicker seam. Using the coarsest grid keeps all cascades
	-- in lock-step while still eliminating the shimmer.
	local depthRes = GetConVar("r_flashlightdepthres"):GetFloat()
	if depthRes <= 0 then depthRes = 1024 end

	local function texelSnap(pos, orthoSize, ang)
		if orthoSize <= 0 then return pos end
		local worldUnitsPerTexel = (orthoSize * 2) / depthRes
		local fwd, right, up = ang:Forward(), ang:Right(), ang:Up()
		local lx = pos:Dot(right)
		local ly = pos:Dot(up)
		local lz = pos:Dot(fwd)
		lx = math.floor(lx / worldUnitsPerTexel + 0.5) * worldUnitsPerTexel
		ly = math.floor(ly / worldUnitsPerTexel + 0.5) * worldUnitsPerTexel
		return right * lx + up * ly + fwd * lz
	end

	-- Ensure cascade 1 exists when in normal (3-cascade) mode.
	if not self.ProjectedTextures[1] and GetConVar("csm_cascade_count"):GetInt() == 3 then
		self:createLamps()
	end

	local sizeScale    = GetConVar("csm_sizescale"):GetFloat()
	local sizeNear     = self:GetSizeNear()  * sizeScale
	local sizeMid      = self:GetSizeMid()   * sizeScale
	local sizeFar      = self:GetSizeFar()   * sizeScale
	local sizeFurther  = self:GetSizeFurther() * sizeScale

	-- Per-cascade ortho size lookup (used for texel snapping below).
	local cascadeSize = {
		[1] = spreadEnabled and sizeMid or sizeNear,
		[2] = sizeMid,
		[3] = sizeFar,
		[4] = sizeFurther,
	}
	-- Spread extra lights all use sizeMid.
	if spreadEnabled then
		local extra = GetConVar("csm_spread_samples"):GetInt() - 2
		for i = 1, extra do cascadeSize[4 + i] = sizeMid end
	end

	-- Set orthographic extents.
	local function setOrtho(pt, s)
		if IsValid(pt) then
			pt:SetOrthographic(true, s, s, s, s)
		end
	end

	if self.ProjectedTextures[1] then setOrtho(self.ProjectedTextures[1], sizeNear) end
	setOrtho(self.ProjectedTextures[2], sizeMid)
	if IsValid(self.ProjectedTextures[3]) then setOrtho(self.ProjectedTextures[3], sizeFar) end
	if IsValid(self.ProjectedTextures[4]) then setOrtho(self.ProjectedTextures[4], sizeFurther) end

	-- Single cascade: use far size for the single frustum.
	if GetConVar("csm_cascade_count"):GetInt() == 1 then
		if self.ProjectedTextures[1] then setOrtho(self.ProjectedTextures[1], sizeFar) end
	end

	if spreadEnabled then
		if IsValid(self.ProjectedTextures[1]) then setOrtho(self.ProjectedTextures[1], sizeMid) end
		local extra = GetConVar("csm_spread_samples"):GetInt() - 2
		for i = 1, extra do
			if IsValid(self.ProjectedTextures[4 + i]) then
				setOrtho(self.ProjectedTextures[4 + i], sizeMid)
			end
		end
	end

	local stormfoxEnabled  = GetConVar("csm_stormfoxsupport"):GetInt() == 1
	local depthBias        = GetConVar("csm_depthbias"):GetFloat()
	local slopeScaleBias   = GetConVar("csm_depthbias_slopescale"):GetFloat()
	local distanceBias     = GetConVar("csm_depthbias_distancescale"):GetFloat()
	local debugCascade     = GetConVar("csm_debug_cascade"):GetBool()
	local colouredSun      = GetConVar("csm_stormfox_coloured_sun"):GetBool()
	local filterBase       = GetConVar("csm_filter"):GetFloat()
	local filterDist       = GetConVar("csm_filter_distancescale"):GetBool()
	local stormfoxBrMul    = GetConVar("csm_stormfox_brightness_multiplier"):GetFloat()
	local hdr              = GetConVar("csm_hashdr"):GetInt() == 1
	local spreadSamples    = GetConVar("csm_spread_samples"):GetInt()

	local sunBrightBase = self:GetSunBrightness() / 400

	local stormfoxApp
	if stormfoxEnabled then
		stormfoxApp = Util.CalculateAppearance((pitch + -180) / 360)
	end

	for i, pt in pairs(self.ProjectedTextures) do
		if not IsValid(pt) then continue end

		-- Brightness.
		local sunBright = sunBrightBase
		if stormfoxEnabled and stormfoxApp then
			sunBright = sunBright * stormfoxApp.SunBrightness * stormfoxBrMul
			sunBright = sunBright * (hdr and 1 or 0.2)
		end
		if spreadEnabled then
			if i == 1 or i == 2 or i > 4 then
				sunBright = sunBright / spreadSamples
			end
		end
		pt:SetBrightness(sunBright)

		-- Colour.
		if debugCascade then
			pt:SetColor(debugColours[i] or Color(255,255,255))
		elseif colouredSun and stormfoxApp then
			pt:SetColor(stormfoxApp.SunColour)
		else
			pt:SetColor(self:GetSunColour():ToColor())
		end

		-- Position and angle.
		-- Apply texel snapping if enabled: snap position to shadow-map texel grid
		-- in light space to eliminate sub-texel shadow shimmer as the camera moves.
		local ptPos = position
		if GetConVar("csm_texelsnap"):GetBool() then
			-- All cascades snap to the FAR cascade's (coarsest) texel grid so
			-- they move in lockstep and the mask boundaries don't drift.
			-- Use sizeFurther only when the further cascade is actually active;
			-- otherwise sizeFurther (default 65536) makes the grid absurdly coarse.
			local furtherActive = GetConVar("csm_further"):GetBool()
			local coarseSize = (furtherActive and sizeFurther > 0) and sizeFurther or sizeFar
			ptPos = texelSnap(position, coarseSize, sunAngle)
		end
		pt:SetPos(ptPos)
		pt:SetAngles(sunAngle)

		-- Spread: rotate each sample around the sun axis.
		if spreadEnabled and self._lightPoints then
			local chuck = Angle(0, 0, 0)
			if     i == 1 then chuck = self._lightPoints[1] or chuck
			elseif i == 2 then chuck = self._lightPoints[2] or chuck
			elseif i > 4  then chuck = self._lightPoints[i - 2] or chuck
			end
			local m = Matrix()
			m:SetAngles(sunAngle)
			m:Rotate(Angle(chuck.x, 0, 0) + Angle(0, chuck.y, 0))
			pt:SetAngles(m:GetAngles())
		end

		-- Depth bias.
		local distScale = distanceBias * (i - 1)
		pt:SetShadowDepthBias(depthBias + distScale)
		pt:SetShadowSlopeScaleDepthBias(slopeScaleBias)

		-- Filter scale per cascade.
		local filtScale = 1
		if filterDist and (i <= 3 or i > 4) then
			local dist = (i > 4) and 1 or i
			filtScale = 8 ^ (dist - 1)
		end
		pt:SetShadowFilter(filterBase / filtScale)

		pt:SetNearZ(self:GetSunNearZ())
		pt:SetFarZ(self:GetSunFarZ() * 1.025)
		pt:SetQuadraticAttenuation(0)
		pt:SetLinearAttenuation(0)
		pt:SetConstantAttenuation(1)
		pt:Update()
	end

	-- ── Sky/fog effects (via UseSkyFogEffects network var) ────────────────────
	if self:GetUseSkyFogEffects() then
		local envSun = ents.FindByClass("C_Sun")[1]
		if IsValid(envSun) then
			envSun:SetKeyValue("sun_dir", tostring(offset))
		end
		local envFog = ents.FindByClass("C_FogController")[1]
		if IsValid(envFog) then
			envFog:SetKeyValue("fogcolor", tostring(appearance.FogColor))
		end
		local envSkyPaint = ents.FindByClass("env_skypaint")[1]
		if IsValid(envSkyPaint) then
			envSkyPaint:SetKeyValue("TopColor",    tostring(appearance.SkyTopColor))
			envSkyPaint:SetKeyValue("BottomColor", tostring(appearance.SkyBottomColor))
			envSkyPaint:SetKeyValue("DuskColor",   tostring(appearance.SkyDuskColor))
			envSkyPaint:SetKeyValue("SunColor",    tostring(appearance.SkySunColor))
		end
	end
end

