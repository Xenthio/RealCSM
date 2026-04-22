-- lua/autorun/realcsm_client.lua
-- CLIENT ONLY. ConVars, first-time setup UI, toolmenu, net handlers.

if not CLIENT then return end

include("realcsm/convars.lua")

-- ── HDR detection ────────────────────────────────────────────────────────────
-- Done once at load; the entity also checks this on spawn.
RunConsoleCommand("csm_hashdr", render.GetHDREnabled() and "1" or "0")

-- ── Net: server enforces a quality cap ──────────────────────────────────────
net.Receive("RealCSMEnforceDepthRes", function()
	local cap = net.ReadInt(16)
	local current = GetConVar("r_flashlightdepthres"):GetInt()
	if cap > 0 and current > cap then
		RunConsoleCommand("r_flashlightdepthres", tostring(cap))
		print("[Real CSM] Server capped shadow map resolution to " .. cap)
	end
end)

-- ── Net: server-pushed sun info (optional server-driven day/night) ──────────
-- Stored here so the entity's Think can read it without a network roundtrip.
RealCSM.ServerSunInfo = nil
net.Receive("RealCSMSunInfo", function()
	RealCSM.ServerSunInfo = {
		pitch      = net.ReadFloat(),
		yaw        = net.ReadFloat(),
		roll       = net.ReadFloat(),
		brightness = net.ReadFloat(),
	}
end)

-- ── Net: reload lightmaps when the server says so ───────────────────────────
net.Receive("RealCSMReloadLightmaps", function()
	if GetConVar("csm_redownloadonremove"):GetBool() then
		render.RedownloadAllLightmaps(false, true)
	end
end)

-- ── Net: remove the clientside fp-shadow entity when server says so ─────────
net.Receive("RealCSMKillClientShadows", function()
	-- The entity cl_init.lua stores its fp controller in RealCSM.FPShadowController.
	if RealCSM.FPShadowController and RealCSM.FPShadowController:IsValid() then
		RealCSM.FPShadowController:Remove()
		RealCSM.FPShadowController = nil
	end
end)

-- ── First-time setup UI ──────────────────────────────────────────────────────

local function FirstTimeSetup()
	local Frame = vgui.Create("DFrame")
	Frame:SetSize(330, 290)
	Frame:Center()
	Frame:SetTitle("CSM First Time Load!")
	Frame:SetVisible(true)
	Frame:SetDraggable(false)
	Frame:ShowCloseButton(true)
	Frame:MakePopup()

	local function label(text, x, y, w, col)
		local lbl = vgui.Create("DLabel", Frame)
		lbl:SetPos(x, y)
		lbl:SetSize(w or 300, 20)
		lbl:SetText(text)
		if col then lbl:SetTextColor(col) end
		return lbl
	end

	label("Thanks for using Real CSM!",                                          15, 40,  300, Color(255,255,255))
	label("In order to allow me to support this addon and keep it free,",        15, 55)
	label("it would be nice if you could consider donating to my Patreon!",      15, 70)
	label("https://www.patreon.com/xenthio",                                     15, 85,  300, Color(255,255,255))
	label("Refer to the F.A.Q for troubleshooting and help!",                    15, 110)
	label("More quality settings appear when CSM is next activated,",            15, 125)
	label("then can be found in the spawnmenu \"Utilities\" tab.",               15, 140)

	local perfCheck = vgui.Create("DCheckBoxLabel", Frame)
	perfCheck:SetText("Performance Mode")
	perfCheck:SetPos(15, 165)
	perfCheck:SetSize(300, 30)
	perfCheck:SetTextColor(Color(255,255,255))
	perfCheck:SetConVar("csm_perfmode")
	label("Use fewer shadow cascades for better performance.",                    39, 185, 300, Color(180,180,180))

	local spawnCheck = vgui.Create("DCheckBoxLabel", Frame)
	spawnCheck:SetText("Spawn on load")
	spawnCheck:SetPos(15, 200)
	spawnCheck:SetSize(300, 30)
	spawnCheck:SetTextColor(Color(255,255,255))
	spawnCheck:SetConVar("csm_spawnalways")
	label("Spawn Real CSM on map load, serverside only.",                         39, 220, 300, Color(180,180,180))

	local continueBtn = vgui.Create("DButton", Frame)
	continueBtn:SetText("Continue")
	continueBtn:SetPos(133, 255)
	continueBtn.DoClick = function()
		file.Write("realcsm.txt", "one")
		if GetConVar("csm_spawnalways"):GetInt() == 1 then
			RunConsoleCommand("gmod_admin_cleanup")
		end
		Frame:Close()
	end
end

RealCSM.FirstTimeSetup = FirstTimeSetup

local function firstTimeCheck()
	local flag = file.Read("realcsm.txt", "DATA")
	if flag ~= "two" and flag ~= "one" then
		FirstTimeSetup()
	end
end

hook.Add("InitPostEntity", "RealCSMFirstTimeCheck", firstTimeCheck)

-- ── Client toolmenu ──────────────────────────────────────────────────────────

local ConVarsDefault = {
	csm_spawnalways    = "0",
	csm_spawnwithlightenv = "0",
	csm_propradiosity  = "4",
	csm_blobbyao       = "0",
	csm_wakeprops      = "1",
	csm_spread         = "0",
	csm_spread_samples = "7",
	csm_spread_radius  = "0.5",
	csm_localplayershadow = "0",
	csm_further        = "0",
	csm_furthershadows = "1",
	csm_sizescale      = "1",
	csm_perfmode       = "0",
	csm_depthbias      = "0.000002",
	csm_depthbias_slopescale = "2",
}

hook.Add("PopulateToolMenu", "RealCSMClient", function()
	spawnmenu.AddToolMenuOption("Utilities", "User", "CSM_Client", "#CSM", "", "", function(panel)
		panel:ClearControls()

		panel:ControlHelp("Thanks for using Real CSM! Please consider donating to support development:")
		panel:ControlHelp("https://www.patreon.com/xenthio")

		panel:AddControl("ComboBox", {
			MenuButton = 1,
			Folder     = "presetCSM",
			Options    = { ["#preset.default"] = ConVarsDefault },
			CVars      = table.GetKeys(ConVarsDefault),
		})

		panel:CheckBox("CSM Enabled", "csm_enabled")

		panel:CheckBox("Performance mode", "csm_perfmode")
		panel:ControlHelp("Only 2 cascade rings – lower quality, better performance.")

		panel:CheckBox("Super performance mode (disable far cascade shadows)", "csm_farshadows")

		-- Shadow quality sliders with linked update logic.
		local qualitySlider = panel:NumSlider("Shadow Quality", "r_flashlightdepthres", 0, 16384, 0)
		panel:ControlHelp("Shadow map resolution.")
		qualitySlider.OnValueChanged = function(self, value)
			RunConsoleCommand("csm_depthresasmultiple", math.floor((math.log(value) / math.log(2)) - 6))
			RunConsoleCommand("r_flashlightdepthres", value)
		end

		local multSlider = panel:NumSlider("Shadow Quality as Multiple", "csm_depthresasmultiple", 0, 8, 0)
		panel:ControlHelp("Shadow map resolution as an exponential multiplier.")
		multSlider.OnValueChanged = function(self, value)
			value = math.floor(value)
			if multSlider:IsEditing() then
				RunConsoleCommand("r_flashlightdepthres", 2 ^ (value + 6))
			end
		end
		multSlider:SetValue(math.log(qualitySlider:GetValue()) / math.log(2) - 6)

		panel:NumSlider("Shadow Filter", "csm_filter", 0, 20)
		panel:ControlHelp("Source engine shadow filter. 0.08 is a good default; use 1.00 for lower resolutions.")

		panel:CheckBox("Filter distance correction", "csm_filter_distancescale")
		panel:ControlHelp("Scale filter per cascade to prevent blurring on far rings.")

		local radiosity = panel:ComboBox("Prop Radiosity", "csm_propradiosity")
		radiosity:AddChoice("0: no radiosity",                                             0)
		radiosity:AddChoice("1: ambient cube (6 samples)",                                 1)
		radiosity:AddChoice("2: 162 samples",                                              2)
		radiosity:AddChoice("3: 162 samples statics, 6 samples rest (GMod default)",       3)
		radiosity:AddChoice("4: 162 samples statics, leaf node rest (Real CSM default)",   4)
		panel:ControlHelp("Prop indirect lighting quality (r_radiosity).")

		panel:CheckBox("Update and Wake Props", "csm_wakeprops")
		panel:ControlHelp("Wake props after radiosity changes.")

		panel:CheckBox("Enable AO-like Blob Shadows", "csm_blobbyao")
		panel:ControlHelp("Enables blob shadows tuned to look like ambient occlusion.")

		panel:CheckBox("Shadow Spread (penumbra simulation)", "csm_spread")
		panel:ControlHelp("Simulates sun penumbra. Disables near ring. Only applied to the mid ring.")
		panel:NumSlider("Spread Radius", "csm_spread_radius", 0, 1)
		panel:ControlHelp("Spread radius in degrees. Real-world value: 0.5. Artistic: up to 1.0.")
		panel:NumSlider("Spread Samples", "csm_spread_samples", 2, 16, 0)
		panel:ControlHelp("WARNING: above 7 requires launching GMod with extra shadow maps. High values may crash!")
		panel:NumSlider("Spread Circle Layers", "csm_spread_layers", 1, 6, 0)
		panel:ControlHelp("Layers of circles packing the spread. 1 = softer, 2 = more accurate.")

		panel:CheckBox("Draw Firstperson Shadows (Experimental)", "csm_localplayershadow")
		panel:ControlHelp("See your own shadow in firstperson.")

		panel:NumSlider("Size / Distance Scale", "csm_sizescale", 0, 5)
		panel:ControlHelp("Cascade size multiplier – affects both reach and perceived quality.")

		panel:CheckBox("Hard distance cutoff", "csm_harshcutoff")
		panel:ControlHelp("Hard edge on the final cascade instead of a gradient fade.")

		panel:CheckBox("Enable further cascade (large maps)", "csm_further")
		panel:ControlHelp("Adds a fourth cascade for greater shadow draw distance.")
		panel:CheckBox("Enable shadows on further cascade", "csm_furthershadows")

		panel:NumSlider("Shadowmap Depth Bias", "csm_depthbias", -1, 1, 6)
		panel:NumSlider("Shadowmap Slope Scale Depth Bias", "csm_depthbias_slopescale", 0, 6, 1)

		panel:CheckBox("Cascade Debug Colors", "csm_debug_cascade")
		panel:ControlHelp("Each cascade rendered in a distinct colour for debugging.")

		local resetBtn = panel:Button("Open First-Time Setup")
		resetBtn.DoClick = FirstTimeSetup
	end)
end)
