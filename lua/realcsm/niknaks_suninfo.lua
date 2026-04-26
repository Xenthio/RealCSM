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
	-- _light intensity is in VRAD units. cl_init Think does GetSunBrightness()/400
	-- to get PT brightness, so store intensity*400 so the final PT brightness = intensity.
	-- e.g. _light intensity=800 → SetSunBrightness(320000) → /400 = 800 PT brightness... 
	-- wait, that would be insane. The empirical /400 divisor means 1000 stored → 2.5 PT.
	-- We want _light 800 to give ~2.0 PT (similar to 800/400). So just store raw intensity:
	-- SetSunBrightness(800) → /400 = 2.0 PT brightness. That's the correct mapping.
	local brightness = intensity  -- stored as-is; cl_init divides by 400

	-- Colour: _light stores raw sRGB (0-255) from Hammer.
	-- pt:SetColor feeds m_Color directly (linear space) so we must linearize:
	-- linear = pow(srgb/255, 2.2) * 255
	local function lin(x)
		return math.pow(x / 255, 2.2) * 255
	end
	return Color(math.floor(lin(r)+0.5), math.floor(lin(g)+0.5), math.floor(lin(b)+0.5), 255), brightness
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

	-- Mirror VRAD's HDR selection logic:
	-- In HDR: prefer _lightHDR if RGB != -1 -1 -1, then multiply by _lightscaleHDR.
	-- In LDR: always use _light.
	local isHDR = render.GetHDREnabled()
	local color, brightness
	if isHDR then
		local hdrStr = tostring(env["_lightHDR"] or "")
		local hr, hg, hb, hi = string.match(hdrStr, "(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*(-?%d*)")
		hr, hg, hb, hi = tonumber(hr), tonumber(hg), tonumber(hb), tonumber(hi)
		-- _lightHDR is valid if RGB are not all -1
		if hr and not (hr == -1 and hg == -1 and hb == -1) then
			-- Valid HDR override: use HDR rgb with HDR intensity scaler
			local hdrScale = tonumber(env["_lightscaleHDR"]) or 1.0
			color     = Color(math.max(0,hr), math.max(0,hg), math.max(0,hb), 255)
			brightness = (hi and hi >= 0 and hi or 200) * hdrScale
		else
			-- _lightHDR has -1 -1 -1 rgb: VRAD treats this as completely invalid
			-- (pow(-1/255, 2.2) = NaN) and falls back to _light entirely,
			-- then multiplies by _lightscaleHDR. We do the same.
			local lcolor, lbright = parseLightValue(env["_light"])
			local hdrScale = tonumber(env["_lightscaleHDR"]) or 1.0
			local hdrbright = (lbright or 200) * hdrScale
			-- If HDR result is suspiciously low the map has no real HDR data;
			-- use _light intensity unchanged (e.g. d1_trainstation _lightHDR=1).
			if hdrbright < 10 then
				brightness = lbright or 200
			else
				brightness = hdrbright
			end
			color = lcolor
		end
	else
		color, brightness = parseLightValue(env["_light"])
	end

	local ambColor, ambBrightness = parseLightValue(env["_ambient"])
	local angle                   = parseAngles(env)

	if not color then
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
