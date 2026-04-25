-- lua/realcsm/convars.lua
-- Single source of truth for ALL RealCSM ConVars.
-- Include from any realm; it creates only the right cvars for that realm.

RealCSM = RealCSM or {}

-- ── Client ConVars ──────────────────────────────────────────────────────────
-- { name, default, save, userinfo }
local clientDefs = {
	{ "csm_enabled",                          1,        false, false },
	{ "csm_update",                           1,        false, false },
	{ "csm_skyboxfix",                        1,        true,  false },
	{ "csm_spawnalways",                      0,        true,  false },
	{ "csm_spawnwithlightenv",                0,        true,  false },
	{ "csm_propradiosity",                    4,        true,  false },
	{ "csm_blobbyao",                         0,        true,  false },
	{ "csm_wakeprops",                        1,        true,  false },
	{ "csm_spread",                           0,        false, false },
	{ "csm_spread_samples",                   7,        true,  false },
	{ "csm_spread_radius",                    0.5,      true,  false },
	{ "csm_spread_layers",                    1,        true,  false },
	{ "csm_spread_layer_density",             0,        true,  false },
	{ "csm_spread_layer_alloctype",           0,        false, false },
	{ "csm_spread_layer_reservemiddle",       1,        false, false },
	{ "csm_spread_method",                    0,        true,  false }, -- 0=Optimal 1=Vogel 2=Legacy
	{ "csm_localplayershadow",                0,        true,  false },
	{ "csm_localplayershadow_old",            0,        false, false },
	{ "csm_further",                          0,        true,  false },
	{ "csm_furthershadows",                   1,        true,  false },
	{ "csm_harshcutoff",                      0,        true,  false },
	{ "csm_farshadows",                       1,        true,  false },
	{ "csm_nofar",                            0,        false, false },
	{ "csm_sizescale",                        1,        true,  false },
	{ "csm_perfmode",                         0,        true,  false }, -- legacy alias; use csm_cascade_count instead
	{ "csm_singlecascade",                    0,        true,  false }, -- legacy alias; use csm_cascade_count instead
	{ "csm_cascade_count",                    3,        true,  false }, -- 1=single, 2=perf, 3=normal
	{ "csm_redownloadonremove",               1,        true,  false },
	{ "csm_filter",                           0.08,     false, false },
	{ "csm_filter_distancescale",             1,        false, false },
	{ "csm_depthresasmultiple",               0,        false, false },
	{ "csm_depthformat",                      16,       true,  false }, -- shadow depth buffer bits: 16 or 24
	{ "csm_depthbias",                        0.000035, false, false },
	{ "csm_depthbias_slopescale",             2,        false, false },
	{ "csm_depthbias_distancescale",          0.0,      false, false },
	{ "csm_experimental_translucentshadows",  0,        true,  false },
	{ "csm_texelsnap",                         1,        true,  false },
	-- Per-cascade shadow update skipping (x86-64/dev branch feature).
	-- Value = max seconds between that cascade's shadow updates. Updates also
	-- trigger on texel snap (cascade moved) or sun angle change. 0 = disabled
	-- (update every frame). 0.03s on far cascade is a cheap perf win.
	{ "csm_farskip",                          0.03,     true,  false },
	{ "csm_midskip",                          0,        true,  false },
	{ "csm_nearskip",                         0,        true,  false },
	-- Multiplier for the cascade snap grid size. Applied to ALL cascades so
	-- they stay in lockstep and masks don't drift. Higher = snap less often,
	-- shadow stays locked across more movement. Pairs with *_skip convars.
	{ "csm_skip_snapmult",                    1,        true,  false },
	-- Experimental: replace static circular masks (csm/mask_center, mask_ring,
	-- mask_end) with runtime render targets painted to match the camera view
	-- frustum projected into light space. Cascades tile without overlap and
	-- without wasting texels on empty corners. MVP uses AABB cutouts.
	{ "csm_frustum_masks",                    0,        true,  false },
	{ "csm_frustum_debug",                    0,        true,  false },
	{ "csm_frustum_viz",                      0,        true,  false },
	-- Auto depth-range: trace-based NearZ/FarZ calculation instead of hardcoded values.
	{ "csm_auto_nearfarz",                    0,        true,  false },
	-- Dedicated skybox sun lamp (positioned in sky_camera space, enabled only during skybox draw).
	{ "csm_skyboxlamp",                       0,        true,  false },
	-- Mute normal cascade lamps during skybox render to prevent bleed.
	-- Costs N*2 extra Update() calls per frame. Disable if no bleed is visible.
	{ "csm_skyboxlamp_mutenormal",             1,        true,  false },
	-- Debug overlay: show current NearZ/FarZ values on screen.
	{ "csm_debug_nearfarz",                   0,        false, false },
	-- Sun occlusion culling: park all lamps when player is fully indoors.
	{ "csm_sunocclude",                       0,        true,  false },
	{ "csm_legacydisablesun",                 0,        true,  false },
	{ "csm_haslightenv",                      0,        false, false },
	{ "csm_hashdr",                           0,        false, false },
	{ "csm_debug_cascade",                    0,        false, false },
	{ "csm_disable_warnings",                 0,        false, false },
}

-- ── Server ConVars ──────────────────────────────────────────────────────────
-- { name, default, flags }
local serverDefs = {
	{ "csm_spawnalways",                    0, FCVAR_ARCHIVE },
	{ "csm_spawnwithlightenv",              0, FCVAR_ARCHIVE },
	{ "csm_allowwakeprops",                 1, FCVAR_ARCHIVE },
	{ "csm_allowfpshadows_old",             0, FCVAR_ARCHIVE },
	{ "csm_getENVSUNcolour",                1, FCVAR_ARCHIVE },
	{ "csm_stormfoxsupport",                0, FCVAR_ARCHIVE },
	{ "csm_stormfox_brightness_multiplier", 1, FCVAR_ARCHIVE },
	{ "csm_stormfox_coloured_sun",          0, FCVAR_ARCHIVE },
	-- Server-readable mirrors of client convars (needed on dedicated servers).
	{ "csm_propradiosity",                  4, FCVAR_ARCHIVE },
	{ "csm_legacydisablesun",               0, FCVAR_ARCHIVE },
	{ "csm_sv_maxdepthres",                 0, FCVAR_ARCHIVE },
}

local cvars = {}

if CLIENT then
	for _, def in ipairs(clientDefs) do
		local name, default, save, userinfo = def[1], def[2], def[3], def[4]
		cvars[name] = CreateClientConVar(name, default, save, userinfo)
	end
end

if SERVER then
	for _, def in ipairs(serverDefs) do
		local name, default, flags = def[1], def[2], def[3]
		if not GetConVar(name) then
			cvars[name] = CreateConVar(name, default, flags)
		else
			cvars[name] = GetConVar(name)
		end
	end
end

RealCSM.CVars = cvars

-- Lazy accessor – returns the ConVar object, fetching from engine if not cached.
function RealCSM.CVar(name)
	if not cvars[name] then
		cvars[name] = GetConVar(name)
	end
	return cvars[name]
end
