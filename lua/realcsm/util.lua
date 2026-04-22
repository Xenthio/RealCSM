-- lua/realcsm/util.lua
-- Shared utility functions for RealCSM. No side effects.

RealCSM = RealCSM or {}

local M = {}
RealCSM.Util = M

-- AppearanceKeys: time-of-day colour table. Position is 0..1 (time of day).
local AppearanceKeys = {
	{ Position = 0.00, SunColour = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.00, 0.00), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) },
	{ Position = 0.25, SunColour = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.03, 0.03), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) },
	{ Position = 0.30, SunColour = Color(255,  140,  0, 255), SunBrightness =  0.3, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.01, 0.00, 0.03), SkyBottomColor = Vector(0.00, 0.05, 0.11), SkyDuskColor = Vector(1.00, 0.16, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00), FogColor = Vector(153, 110, 125) },
	{ Position = 0.35, SunColour = Color(255, 217, 179, 255), SunBrightness =  1.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.50, SunColour = Color(255, 217, 179, 255), SunBrightness =  1.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.18, 1.00), SkyBottomColor = Vector(0.00, 0.34, 0.67), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.65, SunColour = Color(255, 217, 179, 255), SunBrightness =  1.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.70, SunColour = Color(255,  140,  0, 255), SunBrightness =  0.3, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.01, 0.00, 0.03), SkyBottomColor = Vector(0.00, 0.05, 0.11), SkyDuskColor = Vector(1.00, 0.16, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00), FogColor = Vector(153, 110, 125) },
	{ Position = 0.75, SunColour = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.03, 0.03), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) },
}

-- Returns the first entity of the given class, or nil.
function M.FindEntity(class)
	return ents.FindByClass(class)[1]
end

-- Maps an angle in degrees to a point on a circle of the given radius.
function M.PointOnCircle(angle, radius, offsetX, offsetY)
	angle = math.rad(angle)
	local x = math.cos(angle) * radius + offsetX
	local y = math.sin(angle) * radius + offsetY
	return x, y
end

function M.LerpColor(t, fromColor, toColor)
	return Color(
		Lerp(t, fromColor.r, toColor.r),
		Lerp(t, fromColor.g, toColor.g),
		Lerp(t, fromColor.b, toColor.b),
		Lerp(t, fromColor.a, toColor.a)
	)
end

function M.HexToRgb(hex)
	return Color(
		tonumber(string.sub(hex, 1, 2), 16),
		tonumber(string.sub(hex, 3, 4), 16),
		tonumber(string.sub(hex, 5, 6), 16),
		1.0
	)
end

-- Interpolates the AppearanceKeys table for the given time-of-day position (0..1).
function M.CalculateAppearance(position)
	local from, to

	for _, key in pairs(AppearanceKeys) do
		if key.Position == position then return key end
		if key.Position < position then from = key end
		if key.Position > position then to = key; break end
	end

	if from == nil then from = AppearanceKeys[#AppearanceKeys] end
	if to   == nil then to   = AppearanceKeys[1] end

	local t = (position - from.Position) / (to.Position - from.Position)
	local result = {}

	for k, v in pairs(from) do
		if type(v) == "table" then
			result[k] = M.LerpColor(t, from[k], to[k])
		else
			result[k] = Lerp(t, from[k], to[k])
		end
	end

	return result
end
