-- lua/realcsm/niknaks_suninfo.lua
-- NikNaks-powered BSP sun info reader.
-- Reads light_environment directly from the BSP entity lump, bypassing the
-- engine edict list (which is absent on maps where the compiler stripped it or
-- it was never targetnamed).
--
-- API:
--   RealCSM.NikNaksSunInfo.Get()
--     → { angle=Angle, color=Color, brightness=number, ambientColor=Color, ambientBrightness=number }
--     or nil if NikNaks unavailable / no light_environment in BSP.
--
-- Caches per-map. Reset on map change via a hook.
--
-- REQUIRES: NikNaks (workshop 1835812634) to be loaded.
-- If NikNaks is absent, Get() returns nil and the caller falls back to the
-- engine entity-based lookup.

if SERVER then return end  -- client only; server uses ents.FindByClass normally

local M = {}
RealCSM.NikNaksSunInfo = M

local _cache = nil   -- cached result for current map

-- Parse a "_light"-style value string: "R G B intensity" or "R G B".
-- Returns Color, brightness (linear PT scale).
local function parseLightValue(str)
	if not str then return nil, nil end
	local r, g, b, intensity = string.match(tostring(str), "(%d+)%s+(%d+)%s+(%d+)%s*(%d*)")
	if not r then return nil, nil end
	r, g, b = tonumber(r), tonumber(g), tonumber(b)
	intensity = tonumber(intensity) or 200
	-- Convert 0-255 colour + intensity to a PT brightness value.
	-- Source's light_environment intensity is in the range ~0-1000; typical
	-- daylight is ~200-500. Store raw intensity — cl_init divides by 400
	-- in Think (same as GetSunBrightness() / 400 for the entity network var).
	-- Store raw intensity for reference; brightness is intentionally NOT set
	-- via NikNaks since GMod PT brightness and VRAD _light intensity are in
	-- incompatible units. The entity's SetSunBrightness(1000) default is
	-- empirically correct for most maps. Users can adjust via the slider.
	-- NikNaks is used for COLOUR and ANGLE only.
	return Color(r, g, b, 255), nil  -- nil brightness = don't override
end

-- Read angles from BSP light_environment.
-- The entity uses "angles" (Valve pitch/yaw/roll) but light_environment also
-- has a separate "pitch" key that overrides the X component.
local function parseAngles(ent)
	local ang = ent.angles  -- already converted to Angle by NikNaks postEntParse
	if type(ang) ~= "Angle" then ang = Angle(0, 0, 0) end
	-- "pitch" overrides the angles' pitch (separate key, more reliable)
	local pitchOverride = tonumber(ent.pitch)
	if pitchOverride then
		ang = Angle(pitchOverride, ang.y, ang.r)
	end
	return ang
end

--- Read light_environment from BSP entity lump via NikNaks.
--- Returns a table or nil.
function M.Get()
	if _cache ~= nil then return _cache end

	-- Require NikNaks.
	if not NikNaks or not NikNaks.CurrentMap then
		_cache = false   -- false = "checked, nothing found"
		return nil
	end

	local bsp = NikNaks.CurrentMap
	if not bsp then _cache = false; return nil end

	local envs = bsp:FindByClass("light_environment")
	if not envs or #envs == 0 then
		_cache = false
		return nil
	end

	-- Use the first light_environment (maps should only have one meaningful one).
	local env = envs[1]

	local color,    brightness        = parseLightValue(env["_light"])
	local ambColor, ambBrightness     = parseLightValue(env["_ambient"])
	local angle                       = parseAngles(env)

	if not color then
		-- Malformed entity; fall back.
		_cache = false
		return nil
	end

	_cache = {
		angle            = angle,
		color            = Vector(color.r / 255, color.g / 255, color.b / 255),
		brightness       = brightness,
		ambientColor     = ambColor and Vector(ambColor.r / 255, ambColor.g / 255, ambColor.b / 255) or Vector(1, 1, 1),
		ambientBrightness = ambBrightness or 0,
	}
	return _cache
end

--- Invalidate cache (call on map change).
function M.Reset()
	_cache = nil
end

hook.Add("InitPostEntity",  "RealCSM_NikNaksSunInfo_Init",  function() M.Reset() end)
hook.Add("OnReloaded",      "RealCSM_NikNaksSunInfo_Reset", function() M.Reset() end)
