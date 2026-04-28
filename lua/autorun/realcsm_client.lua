-- lua/autorun/realcsm_client.lua
-- CLIENT ONLY. ConVars, first-time setup UI, toolmenu, net handlers.

if not CLIENT then return end

include("realcsm/convars.lua")

-- NikNaks (optional): used by csm_sunocclude for BSP PVS leaf checks.
-- Attempt to load it here so it's available when sunocclude.lua runs.
-- We must not call require() when the module is absent: GMod prints a
-- C-level "Couldn't include file" message before the Lua error is thrown,
-- which pcall can't suppress. Use file.Exists with both known VFS paths
-- ("LUA" for the standard mounted path, "GAME" for x86-64 builds where
-- the workshop mounts modules under lua/ in the GAME search path).
local function _canLoadNikNaks()
	return file.Exists("includes/modules/niknaks.lua", "LUA")
		or file.Exists("lua/includes/modules/niknaks.lua", "GAME")
end
if not NikNaks and _canLoadNikNaks() then
	require("niknaks")
end

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
net.Receive("RealCSMHasLightEnv", function()
	local hasLightEnv = net.ReadBool()
	RunConsoleCommand("csm_haslightenv", hasLightEnv and "1" or "0")
end)

net.Receive("RealCSMReloadLightmaps", function()
	if GetConVar("csm_redownloadonremove"):GetBool() then
		render.RedownloadAllLightmaps(false, true)
	end
end)
-- ── Net: sky_camera world position (not networked by default in GMod) ──────────
RealCSM.SkyCameraPos = nil
net.Receive("RealCSMSkyCameraPos", function()
	RealCSM.SkyCameraPos = net.ReadVector()
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
	Frame:SetSize(330, 310)
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
	label("it would be nice if you could consider supporting me on Ko-fi!",      15, 70)
	label("https://ko-fi.com/xenthio",                                     15, 85,  300, Color(255,255,255))
	label("Refer to the F.A.Q for troubleshooting and help!",                    15, 110)
	label("Optional: install NikNaks (workshop: 1835812634) for",               15, 128, 300, Color(200, 220, 255))
	label("accurate sun colours, brightness + sun occlusion culling.",          15, 143, 300, Color(200, 220, 255))
	label("More quality settings appear when CSM is next activated,",           15, 162)
	label("then can be found in the spawnmenu \"Utilities\" tab.",               15, 177)

	local spawnCheck = vgui.Create("DCheckBoxLabel", Frame)
	spawnCheck:SetText("Spawn on load")
	spawnCheck:SetPos(15, 195)
	spawnCheck:SetSize(300, 30)
	spawnCheck:SetTextColor(Color(255,255,255))
	spawnCheck:SetConVar("csm_spawnalways")
	label("Spawn Real CSM on map load, serverside only.",                         39, 215, 300, Color(180,180,180))

	local continueBtn = vgui.Create("DButton", Frame)
	continueBtn:SetText("Continue")
	continueBtn:SetPos(120, 270)
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

-- ── NikNaks first-seen popup ─────────────────────────────────────────────────
-- Shown once when NikNaks is detected for the first time, prompting the user
-- to enable the features it unlocks (currently: sun occlusion culling).
local function NikNaksWelcomePopup()
	local Frame = vgui.Create("DFrame")
	Frame:SetSize(340, 220)
	Frame:Center()
	Frame:SetTitle("Real CSM: NikNaks detected!")
	Frame:SetVisible(true)
	Frame:SetDraggable(false)
	Frame:ShowCloseButton(true)
	Frame:MakePopup()

	local function label(text, x, y, w, col)
		local lbl = vgui.Create("DLabel", Frame)
		lbl:SetPos(x, y)
		lbl:SetSize(w or 310, 20)
		lbl:SetText(text)
		if col then lbl:SetTextColor(col) end
		return lbl
	end

	label("NikNaks is installed — Real CSM can now use it for:",        15, 35, 310, Color(200, 220, 255))
	label("  • Accurate per-map sun colour and brightness",             15, 53, 310, Color(200, 220, 255))
	label("    (automatic, always active when NikNaks is present)",      15, 68, 310, Color(160, 180, 210))
	label("  • Sun occlusion culling (skip shadow updates indoors)",    15, 86, 310, Color(200, 220, 255))
	label("    Enable below — it\'s off by default.",                    15, 101, 310, Color(160, 180, 210))

	local occludeCheck = vgui.Create("DCheckBoxLabel", Frame)
	occludeCheck:SetText("Enable sun occlusion culling")
	occludeCheck:SetPos(15, 128)
	occludeCheck:SetSize(310, 24)
	occludeCheck:SetTextColor(Color(255, 255, 255))
	occludeCheck:SetConVar("csm_sunocclude")

	local closeBtn = vgui.Create("DButton", Frame)
	closeBtn:SetText("Got it!")
	closeBtn:SetPos(125, 180)
	closeBtn:SetSize(90, 28)
	closeBtn.DoClick = function()
		file.Write("realcsm_niknaks_seen.txt", "1")
		Frame:Close()
	end
end

local function nikNaksCheck()
	if not file.Exists("includes/modules/niknaks.lua", "LUA") then return end
	if file.Read("realcsm_niknaks_seen.txt", "DATA") == "1" then return end
	NikNaksWelcomePopup()
end

hook.Add("InitPostEntity", "RealCSMNikNaksCheck", nikNaksCheck)

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
	-- ── General ────────────────────────────────────────────────────────────────
	spawnmenu.AddToolMenuOption("Utilities", "Real CSM", "CSM_General", "General", "", "", function(panel)
		panel:ClearControls()

		panel:ControlHelp("Thanks for using Real CSM! Consider supporting development:")
		panel:ControlHelp("https://ko-fi.com/xenthio")
		local nikNaksInstalled = file.Exists("includes/modules/niknaks.lua", "LUA")
		if not nikNaksInstalled then
			panel:ControlHelp("Tip: Install NikNaks (workshop) for automatic per-map sun colour and brightness.")
		end

		panel:AddControl("ComboBox", {
			MenuButton = 1,
			Folder     = "presetCSM",
			Options    = { ["#preset.default"] = ConVarsDefault },
			CVars      = table.GetKeys(ConVarsDefault),
		})

		panel:CheckBox("CSM Enabled", "csm_enabled")

		local cascadeCombo = panel:ComboBox("Cascade Mode", "csm_cascade_count")
		cascadeCombo:AddChoice("3 Cascades (Normal)", 3)
		cascadeCombo:AddChoice("2 Cascades (Performance)", 2)
		cascadeCombo:AddChoice("1 Cascade (Shadow Mapping)", 1)
		panel:ControlHelp("3 = full quality, 2 = perf mode (no near ring), 1 = single shadow frustum (cheapest).")

		panel:CheckBox("Super performance mode", "csm_farshadows")
		panel:ControlHelp("Disable shadows on the far cascade, for more performance.")

		panel:CheckBox("Skybox Fixes", "csm_skyboxlamp")
		panel:ControlHelp("Fixes dark lightless skyboxes. 2 extra PT Updates/frame minimum.")
		panel:CheckBox("Skybox lamp: mute normal cascades (reduces bleed, costs N*2 Updates/frame)", "csm_skyboxlamp_mutenormal")
		panel:ControlHelp("Off by default. Enable if normal cascade lamps bleed into the skybox.")

		panel:NumSlider("Size / Distance Scale", "csm_sizescale", 0, 5)
		panel:ControlHelp("Cascade size multiplier – affects both reach and perceived quality.")

		panel:CheckBox("Hard distance cutoff", "csm_harshcutoff")
		panel:ControlHelp("Hard edge on the final cascade instead of a gradient fade.")

		panel:CheckBox("Enable further cascade (large maps)", "csm_further")
		panel:ControlHelp("Adds a fourth cascade for greater shadow draw distance.")
		panel:CheckBox("Enable shadows on further cascade", "csm_furthershadows")

		panel:CheckBox("Draw Firstperson Shadows (Experimental)", "csm_localplayershadow")
		panel:ControlHelp("See your own shadow in firstperson.")

		local resetBtn = panel:Button("Open First-Time Setup")
		resetBtn.DoClick = FirstTimeSetup
	end)

	-- ── Quality ────────────────────────────────────────────────────────────────
	spawnmenu.AddToolMenuOption("Utilities", "Real CSM", "CSM_Quality", "Quality", "", "", function(panel)
		panel:ClearControls()

		panel:ControlHelp("Support development: https://ko-fi.com/xenthio")
		local qualitySlider = panel:NumSlider("Shadow Quality", "r_flashlightdepthres", 0, 16384, 0)
		panel:ControlHelp("Shadow map resolution.")
		qualitySlider.OnValueChanged = function(self, value)
			if value > 0 then
				RunConsoleCommand("csm_depthresasmultiple", math.floor((math.log(value) / math.log(2)) - 6))
			end
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

		local depthFmtCombo = panel:ComboBox("Shadow Depth Buffer Format", "csm_depthformat")
		depthFmtCombo:AddChoice("D16 (default, 16-bit, no code needed)", 16)
		depthFmtCombo:AddChoice("D24 (higher precision, less acne — requires spawn)", 24)
		panel:ControlHelp("D24 reduces shadow acne on large cascades. Applied once at CSM spawn; requires map reload to revert. Experimental.")

		panel:NumSlider("Shadowmap Depth Bias", "csm_depthbias", -1, 1, 6)
		panel:NumSlider("Shadowmap Slope Scale Depth Bias", "csm_depthbias_slopescale", 0, 6, 1)

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

		local spreadMethodCombo = panel:ComboBox("Spread Sample Pattern", "csm_spread_method")
		spreadMethodCombo:AddChoice("0: Optimal (hardcoded ideal packing, best quality)", 0)
		spreadMethodCombo:AddChoice("1: Vogel / Golden-angle spiral (good for any count)", 1)
		spreadMethodCombo:AddChoice("2: Legacy layer-based (original algorithm)", 2)
		panel:ControlHelp("Optimal uses pre-computed Vogel spiral packings for N=1-32, exact analytical for small N. Falls back to Vogel above 32. Legacy exposes the layer controls below.")
		panel:NumSlider("Spread Circle Layers (Legacy only)", "csm_spread_layers", 1, 6, 0)
		panel:ControlHelp("Only used by the Legacy pattern method.")

		panel:CheckBox("Texel Snapping", "csm_texelsnap")
		panel:ControlHelp("Snaps each cascade's position to its shadow-map texel grid in light space, eliminating shadow shimmer as the camera moves.")

		panel:Help("Runtime Frustum Cascade Placement (EXPERIMENTAL)")
		panel:CheckBox("Enable runtime frustum placement", "csm_frustum_placement")
		panel:ControlHelp("Fits each cascade tightly to the camera view frustum slice. Better shadow texel utilisation, no wasted corners. Incompatible with shadow spread.")
		panel:CheckBox("Enable cascade cutout masks", "csm_cascade_masks")
		panel:ControlHelp("Soft cutout masks blend overlap between cascades. Works with or without runtime placement; uses each cascade's current ortho box.")
		panel:NumSlider("Edge softness (UV fraction)", "csm_edge_uv", 0, 0.499, 3)
		panel:ControlHelp("Soft-edge band width on the cascade mask borders (0 = hard edge, 0.1 = 10% soft).")
		panel:NumSlider("Far cascade FOV scale", "csm_far_fov_scale", 0.3, 1.0, 2)
		panel:ControlHelp("Tighten the outermost cascade for more shadow distance at the cost of peripheral coverage.")
		panel:CheckBox("Asymmetric ortho (tighter, anisotropic)", "csm_asymmetric_ortho")
		panel:ControlHelp("Non-square cascade boxes. Tighter fit for non-square view frustums but shadow texels become anisotropic.")
	end)

	-- ── Culling ────────────────────────────────────────────────────────────────
	spawnmenu.AddToolMenuOption("Utilities", "Real CSM", "CSM_Culling", "Culling", "", "", function(panel)
		panel:ClearControls()

		panel:ControlHelp("Support development: https://ko-fi.com/xenthio")
		local ptMeta = FindMetaTable("ProjectedTexture")
		local hasSkipAPI = ptMeta and ptMeta.SetSkipShadowUpdates ~= nil
		if hasSkipAPI then
			panel:NumSlider("Far Cascade Skip (s)", "csm_farskip", 0, 5, 2)
			panel:NumSlider("Mid Cascade Skip (s)", "csm_midskip", 0, 5, 2)
			panel:NumSlider("Near Cascade Skip (s)", "csm_nearskip", 0, 5, 2)
			panel:ControlHelp("Max seconds between shadow updates per cascade. 0 = update every frame. Updates still trigger on texel snap or sun angle change. Requires x86-64 or dev branch.")
			panel:NumSlider("Snap Multiplier", "csm_skip_snapmult", 1, 32, 1)
			panel:ControlHelp("Coarsens the snap grid for all cascades. Higher = shadows stay locked across more camera movement. Pair with skip sliders to prevent shadow drag during skipped frames.")
		else
			panel:Help("Cascade Skip: unavailable on this GMod branch (requires x86-64 or dev).")
		end

		panel:CheckBox("Auto NearZ/FarZ (recommended)", "csm_auto_nearfarz")
		panel:ControlHelp("Trace-calculates the optimal shadow depth range from the sun's position. Reduces light-leak through thin surfaces by tightening the shadow volume.")

		panel:Help("Sun Occlusion Culling (EXPERIMENTAL)")
		panel:ControlHelp("Requires the NikNaks workshop addon (1835812634). Falls back to no culling if missing.")
		panel:CheckBox("Enable", "csm_sunocclude")
		panel:ControlHelp("Parks all cascade lamps when the player can't see any sunlit area.")

		local occCombo = panel:ComboBox("Mode", "csm_sunocclude_mode")
		occCombo:AddChoice("Direction-independent (PVS-only)",     "0")
		occCombo:AddChoice("Directional (PVS + sun raycast bake)", "1")
		local curMode = GetConVar("csm_sunocclude_mode"):GetInt()
		occCombo:SetValue(curMode == 1
			and "Directional (PVS + sun raycast bake)"
			or  "Direction-independent (PVS-only)")
		panel:ControlHelp("PVS-only: cheap, less accurate. Directional: ~1-2s bake when the sun moves more than 10°, more accurate.")

		panel:CheckBox("View frustum cull", "csm_sunocclude_frustum")
		panel:ControlHelp("Also park lamps when sunlit areas are off-screen. Padded by 30% FOV to reduce edge pop. Works with both modes.")
	end)

	-- ── Debug ──────────────────────────────────────────────────────────────────
	spawnmenu.AddToolMenuOption("Utilities", "Real CSM", "CSM_Debug", "Debug", "", "", function(panel)
		panel:ClearControls()

		panel:ControlHelp("Support development: https://ko-fi.com/xenthio")
		panel:CheckBox("Cascade Debug Colors", "csm_debug_cascade")
		panel:ControlHelp("Each cascade rendered in a distinct colour for debugging.")

		panel:CheckBox("Debug: log cascade placement", "csm_frustum_debug")
		panel:CheckBox("Debug: draw cascade AABBs on HUD", "csm_frustum_viz")

		panel:CheckBox("Debug: show NearZ/FarZ on screen", "csm_debug_nearfarz")
		panel:ControlHelp("Displays current NearZ, FarZ and precision ratio in the bottom-left corner. Useful for diagnosing dark spots or over-wide shadow volumes.")

		panel:CheckBox("Debug: Sun Occlusion overlay", "csm_occlude_debug")
		panel:ControlHelp("Shows current leaf, mode, frustum state and culling decision on screen.")
	end)
end)

-- ── Server settings toolmenu (Admin tab) ────────────────────────────────────
-- This runs on the client because PopulateToolMenu is a client hook.
-- The convars it controls are server-side; clients send them via net when changed.
-- ── Server toolmenu ──────────────────────────────────────────────────────────

hook.Add("PopulateToolMenu", "RealCSMServer", function()
	spawnmenu.AddToolMenuOption("Utilities", "Real CSM", "CSM_Server", "Server (Admin)", "", "", function(panel)
		panel:ClearControls()

		panel:ControlHelp("Thanks for using Real CSM! Consider supporting development:")
		panel:ControlHelp("https://ko-fi.com/xenthio")
		local nikNaksInstalled = file.Exists("includes/modules/niknaks.lua", "LUA")
		if not nikNaksInstalled then
			panel:ControlHelp("Tip: Install NikNaks (workshop) for automatic per-map sun colour and brightness.")
		end

		panel:CheckBox("Auto-spawn CSM on map load (Experimental)",                "csm_spawnalways")
		panel:CheckBox("Only spawn if map has a light_environment (Experimental)", "csm_spawnwithlightenv")
		panel:CheckBox("Allow clients to wake up all props",                        "csm_allowwakeprops")
		panel:CheckBox("Allow legacy firstperson shadow entity",                    "csm_allowfpshadows_old")
		panel:CheckBox("Read env_sun colour on spawn",                              "csm_getENVSUNcolour")

		panel:NumSlider("Max client shadow map resolution (0 = unlimited)", "csm_sv_maxdepthres", 0, 16384, 0)
		panel:ControlHelp("Caps r_flashlightdepthres on clients when they join. Useful on low-spec servers.")
	end)
end)

-- ── RealCSM 2.0 Changelog popup ──────────────────────────────────────────────

local function ShowChangelog()
	local W, H = 480, 520
	local Frame = vgui.Create("DFrame")
	Frame:SetSize(W, H)
	Frame:Center()
	Frame:SetTitle("Real CSM 2.0 — What's New")
	Frame:SetDraggable(true)
	Frame:ShowCloseButton(true)
	Frame:MakePopup()

	local scroll = vgui.Create("DScrollPanel", Frame)
	scroll:SetPos(8, 28)
	scroll:SetSize(W - 16, H - 70)

	local function heading(text, y)
		local lbl = vgui.Create("DLabel", scroll)
		lbl:SetPos(8, y)
		lbl:SetSize(W - 40, 22)
		lbl:SetText(text)
		lbl:SetFont("DermaDefaultBold")
		lbl:SetTextColor(Color(255, 220, 80))
		return lbl
	end
	local function item(text, y)
		local lbl = vgui.Create("DLabel", scroll)
		lbl:SetPos(16, y)
		lbl:SetSize(W - 48, 18)
		lbl:SetText(text)
		lbl:SetTextColor(Color(220, 220, 220))
		lbl:SetWrap(true)
		lbl:SetAutoStretchVertical(true)
		return lbl
	end

	local y = 4
	local function h(t) heading(t, y) y = y + 24 end
	local function li(t) item(t, y) y = y + 20 end
	local function gap() y = y + 8 end

	h("Real CSM 2.0 — Full Rewrite")
	li("The entire codebase has been rewritten from scratch.")
	li("Cleaner architecture, no global pollution, proper client/server split.")
	li("You might find that A LOT less addons are broken now.")
	gap()

	h("New Features")
	li("- Texel Snapping — eliminates shadow shimmer as you move (on by default)")
	li("- Cascade Mode dropdown — Normal / Performance / Shadow Mapping (1 lamp)")
	li("- Spread Sample Patterns — Optimal, Vogel spiral, or Legacy layer-based")
	li("- Server sun override API — RealCSM.BroadcastSunInfo() for other addons")
	li("- Server quality cap — csm_sv_maxdepthres to limit client shadow res")
	li("- RealCSM.Lamps — global table of active ProjectedTextures for other addons")
	li("- D24 depth buffer upgrade (opt-in) — reduces shadow acne on large cascades")
	li("- Variable rate shadowmapping on far cascade (experimental, requires dev or x86-64 branch)")
	gap()

	h("Bug Fixes")
	li("- Radiosity now restores to previous value instead of hardcoded 3")
	li("- Disabling CSM via checkbox now properly restores lighting")
	li("- Double lamp creation on spawn fixed")
	gap()

	h("Reporting Bugs (Please report any!)")
	li("GitHub: https://github.com/Xenthio/RealCSM/issues")
	li("Discord: https://discord.gg/VkZjdjsSjJ")
	li("Please include your csm_ convar values and any console errors.")
	gap()

	h("Settings")
	li("All settings are in Spawnmenu -> Utilities -> User -> CSM")
	li("Server settings: Utilities -> Admin -> CSM")

	local closeBtn = vgui.Create("DButton", Frame)
	closeBtn:SetText("Got it!")
	closeBtn:SetPos(W/2 - 60, H - 38)
	closeBtn:SetSize(120, 28)
	closeBtn.DoClick = function()
		file.Write("realcsm_v2.txt", "seen")
		Frame:Close()
	end
end

local function ChangelogCheck()
	if file.Read("realcsm_v2.txt", "DATA") ~= "seen" then
		timer.Simple(2, function()
			if IsValid(LocalPlayer()) then ShowChangelog() end
		end)
	end
end

hook.Add("InitPostEntity", "RealCSMChangelog", ChangelogCheck)

-- Console command to re-show the changelog at any time.
concommand.Add("csm_show_changelog", function()
	ShowChangelog()
end)
