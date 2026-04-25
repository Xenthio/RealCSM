-- lua/realcsm/sunocclude.lua
-- Detects when the player is fully indoors (sun rays all blocked) and
-- parks all cascade lamps to save render passes.
--
-- Method: Cast 5 rays from the eye position in the sun's backward direction
-- (toward the light source). If ALL are blocked by solid non-sky geometry,
-- no sunlight reaches this location → safe to park lamps.
--
-- Caching: result is cached per 64-unit grid cell. Moving between cells
-- triggers a recompute. This means one TraceLine burst per ~4 player steps,
-- near-zero steady-state cost.
--
-- Convar: csm_sunocclude (default 0, opt-in).
-- When active, all lamps are parked (orthoSize=0.001). Think() still runs
-- to keep positions up to date so lamps un-park immediately when moving
-- back outdoors.

RealCSM = RealCSM or {}
local M = {}
RealCSM.SunOcclude = M

local GRID        = 64      -- cache cell size in world units
local RAY_LEN     = 65536
local OFFSETS_2D  = { -- lateral offsets in sun Right/Up plane
	Vector(0,   0,   0),
	Vector(128, 0,   0),
	Vector(-128,0,   0),
	Vector(0,   128, 0),
	Vector(0,  -128, 0),
}

-- ── State ──────────────────────────────────────────────────────────────────────

local _cache     = {}   -- [gx][gy][gz] = true/false (occluded)
local _lastCell  = nil
local _occluded  = false
local _savedOrthos = {}

-- ── Core check ────────────────────────────────────────────────────────────────

local function checkOccluded(eyePos, sunAngle)
	local fwd    = sunAngle:Forward()
	local toward = -fwd
	local right  = sunAngle:Right()
	local up     = sunAngle:Up()

	-- Always cast one straight-up (world Z) ray first.
	-- This catches skylights, roof openings, and any overhead sky access
	-- regardless of sun angle / lateral offset alignment.
	local trUp = util.TraceLine({
		start  = eyePos,
		endpos = eyePos + Vector(0, 0, RAY_LEN),
		mask   = MASK_SOLID_BRUSHONLY,
	})
	if not trUp.Hit or trUp.HitSky then return false end

	-- Sun-direction rays with lateral offsets.
	for _, ofs in ipairs(OFFSETS_2D) do
		local samplePos = eyePos + right * ofs.x + up * ofs.y
		local tr = util.TraceLine({
			start  = samplePos,
			endpos = samplePos + toward * RAY_LEN,
			mask   = MASK_SOLID_BRUSHONLY,
		})
		if not tr.Hit or tr.HitSky then return false end
	end
	return true
end

local function gridCell(pos)
	return
		math.floor(pos.x / GRID),
		math.floor(pos.y / GRID),
		math.floor(pos.z / GRID)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Call from entity Think() after sunAngle is computed.
-- lampTable: the ProjectedTextures table.
-- Returns true if lamps were parked (occluded).
function M.Think(eyePos, sunAngle, lampTable)
	if not GetConVar("csm_sunocclude"):GetBool() then
		-- If we were occluded last frame, restore now.
		if _occluded then
			M.Restore(lampTable)
			_occluded = false
		end
		return false
	end

	local gx, gy, gz = gridCell(eyePos)
	local cell = gx .. "," .. gy .. "," .. gz

	if cell ~= _lastCell then
		_lastCell = cell
		_occluded = checkOccluded(eyePos, sunAngle)
	end

	if _occluded then
		-- Park all lamps (zero render cost).
		for i, pt in pairs(lampTable) do
			if IsValid(pt) then
				local _, l, r, t, b = pt:GetOrthographic()
				if not _savedOrthos[i] then
					_savedOrthos[i] = (l + r + t + b) / 4
				end
				pt:SetOrthographic(true, 0.001, 0.001, 0.001, 0.001)
				pt:Update()
			end
		end
		return true
	else
		M.Restore(lampTable)
		return false
	end
end

function M.Restore(lampTable)
	if not lampTable then return end
	for i, pt in pairs(lampTable) do
		if IsValid(pt) and _savedOrthos[i] then
			local s = _savedOrthos[i]
			pt:SetOrthographic(true, s, s, s, s)
			pt:Update()
			_savedOrthos[i] = nil
		end
	end
end

function M.Reset()
	_cache       = {}
	_lastCell    = nil
	_occluded    = false
	_savedOrthos = {}
end
