-- lua/realcsm/depthrange.lua
-- Auto-calculates optimal NearZ / FarZ for the CSM projected textures.
--
-- NearZ / FarZ are distances along the sun forward axis from the lamp origin.
--
-- GEOMETRY:
--   The cascade is an ortho box in sun-space, orthoHalfSize wide and [nearZ,farZ] deep.
--   On flat ground at height h below the eye, the 4 footprint corners have depths:
--     eyeDepth ± upFactor * orthoHalfSize / sin(pitch)  (±right factor too)
--   where upFactor = |up.z| + |right.z|  (sun basis vector Z components),
--   and sin(pitch) = |fwd.z|.
--
--   FarZ  = eyeDepth + (h + upFactor * orthoHalfSize) / |fwd.z| + slack
--   NearZ = eyeDepth - (upFactor * orthoHalfSize) / |fwd.z| - slack
--
-- We find h with a single WORLD-Z trace downward from the eye position.
-- This avoids starting traces inside the 3D skybox brush volume where
-- the lamp usually sits (skybox brushes are above the playable area on
-- most maps and would be hit first by sun-direction traces).

RealCSM = RealCSM or {}
local M = {}
RealCSM.DepthRange = M

-- ── Config ────────────────────────────────────────────────────────────────────

local CACHE_INTERVAL  = 2.0
local SLACK_NEAR      = 512
local SLACK_FAR       = 2048
local MAX_TRACE_DOWN  = 65536   -- max downward trace for ground detection

-- ── State ──────────────────────────────────────────────────────────────────────

local _cache = { nearZ = 1.0, farZ = 65536.0, lastCalc = -999 }

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Trace straight down in world Z from eyePos.
-- Returns height above ground, or nil if no solid ground found below.
local function heightAboveGround(eyePos)
	local tr = util.TraceLine({
		start  = eyePos,
		endpos = eyePos + Vector(0, 0, -MAX_TRACE_DOWN),
		mask   = MASK_SOLID_BRUSHONLY,
	})
	if tr.Hit and not tr.HitSky then
		return tr.Fraction * MAX_TRACE_DOWN
	end
	return nil
end

-- ── Core calculation ──────────────────────────────────────────────────────────

local function calcRange(lampOrigin, eyePos, sunAngle, orthoHalfSize)
	local fwd   = sunAngle:Forward()
	local up    = sunAngle:Up()
	local right = sunAngle:Right()

	local eyeDepth = (eyePos - lampOrigin):Dot(fwd)

	-- Protect against near-horizontal sun (pitch < ~5°).
	local fwdZ     = math.max(math.abs(fwd.z), 0.08)

	-- Combined depth-variation factor from both sun basis axes.
	local upFactor = math.abs(up.z) + math.abs(right.z)
	local depthVar = upFactor * orthoHalfSize / fwdZ

	-- Height of eye above ground (world-Z trace, never touches skybox).
	-- If no ground found (player in open sky), treat h as 0 — depthVar alone
	-- still gives a reasonable estimate for the footprint size.
	local h = heightAboveGround(eyePos) or 0

	-- FarZ: depth to farthest footprint corner ground hit.
	local farZ = eyeDepth + (h / fwdZ) + depthVar + SLACK_FAR

	-- NearZ: depth to shallowest footprint corner (toward the sun, above ground level).
	local nearZ = math.max(1.0, eyeDepth - depthVar - SLACK_NEAR)

	return nearZ, farZ
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.Get(lampOrigin, eyePos, sunAngle, orthoSize)
	local now = RealTime()
	if (now - _cache.lastCalc) < CACHE_INTERVAL then
		return _cache.nearZ, _cache.farZ
	end

	_cache.lastCalc = now
	local n, f = calcRange(lampOrigin, eyePos, sunAngle, orthoSize)

	n = math.Clamp(n, 1.0, 32768.0)
	f = math.Clamp(f, n + 64, 131072.0)

	_cache.nearZ = n
	_cache.farZ  = f
	return n, f
end

-- Returns the last computed values (used by debug overlay).
function M.GetLast()
	return _cache.nearZ, _cache.farZ, _cache.lastCalc
end

function M.Invalidate()
	_cache.lastCalc = -999
end
