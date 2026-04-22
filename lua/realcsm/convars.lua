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
	{ "csm_localplayershadow",                0,        true,  false },
	{ "csm_localplayershadow_old",            0,        false, false },
	{ "csm_further",                          0,        true,  false },
	{ "csm_furthershadows",                   1,        true,  false },
	{ "csm_harshcutoff",                      0,        true,  false },
	{ "csm_farshadows",                       1,        true,  false },
	{ "csm_nofar",                            0,        false, false },
	{ "csm_sizescale",                        1,        true,  false },
	{ "csm_perfmode",                         0,        true,  false },
	{ "csm_redownloadonremove",               1,        true,  false },
	{ "csm_filter",                           0.08,     false, false },
	{ "csm_filter_distancescale",             1,        false, false },
	{ "csm_depthresasmultiple",               0,        false, false },
	{ "csm_depthbias",                        0.000035, false, false },
	{ "csm_depthbias_slopescale",             2,        false, false },
	{ "csm_depthbias_distancescale",          0.0,      false, false },
	{ "csm_experimental_translucentshadows",  0,        true,  false },
	{ "csm_texelsnap",                         1,        true,  false },
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
	-- If nonzero, clients are told not to exceed this shadow map resolution.
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
