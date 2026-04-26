-- lua/realcsm/skyboxlamp.lua
-- Lights the 3D skybox by temporarily repositioning the main cascade lamps
-- into sky_camera space during the skybox render pass, then restoring them.
--
-- WHY REUSE INSTEAD OF A DEDICATED PT:
--   A dedicated PT costs 2 extra Update() calls per frame (park/expand) plus
--   one extra PT in the engine's flashlight enumeration list even when parked.
--   Reusing the main lamps costs the same 2N Updates but zero extra PTs.
--
-- SHADOW SAFETY:
--   Main lamp shadow maps are baked during the main world render (before
--   PreDrawSkyBox). Moving lamps to sky-space mid-frame would corrupt those
--   maps for subsequent frames. Fix: disable shadows in Pre, restore in Post.
--   The skybox doesn't need cascaded shadows anyway — geometry is simple.
--
-- UPDATE COUNT (N cascades, mutenormal irrelevant since we reuse):
--   PreDrawSkyBox:  N * (SetPos + SetAngles + SetOrthographic + SetEnableShadows
--                       + SetBrightness + SetNearZ + SetFarZ + Update) = N Updates
--   PostDrawSkyBox: N * (restore all fields + Update) = N Updates
--   Total: 2N Updates/frame. Zero extra PTs in flashlight list.

RealCSM = RealCSM or {}
local M = {}
RealCSM.SkyboxLamp = M

local SKYBOX_SCALE = 1 / 16
local PARKED_SIZE  = 0.001
local SKY_LAMP_IDX = 3   -- reuse far cascade; biggest ortho, fewest cascades active

-- ── State ─────────────────────────────────────────────────────────────────────

local _ownerEnt        = nil
local _lampTable       = nil
local _hooks           = false
local _cachedOrthoSize = nil
local _cachedSunAngle  = nil
local _cachedSkyPos    = nil
local _cachedFarZ      = nil
local _occluded        = false   -- set by SunOcclude to suppress skybox lamp during bake/occlusion

-- Saved lamp state for restore after skybox pass.
-- {[i] = {pos, angles, orthoSize, nearZ, farZ, brightness, shadows}}
local _savedState        = {}
local _savedOrthos       = {}
local _tex3              = "csm/mask_ring"

-- ── Skybox extent calculation (done once) ─────────────────────────────────────

local function calcOrthoSize(skyCamPos, sunAngle)
	local right     = sunAngle:Right()
	local up        = sunAngle:Up()
	local maxExtent = 0
	for _, dir in ipairs({
		 right,  -right,  up,  -up,
		( right + up):GetNormalized(),
		( right - up):GetNormalized(),
		(-right + up):GetNormalized(),
		(-right - up):GetNormalized(),
	}) do
		local tr = util.TraceLine({
			start  = skyCamPos,
			endpos = skyCamPos + dir * 65536,
			mask   = MASK_SOLID_BRUSHONLY,
		})
		local d = tr.Hit and (tr.Fraction * 65536) or 4096
		if d > maxExtent then maxExtent = d end
	end
	return math.Clamp(maxExtent * 1.25, 512, 32768)
end

-- ── Hook callbacks ────────────────────────────────────────────────────────────

local _hasSkipAPI = FindMetaTable("ProjectedTexture") and FindMetaTable("ProjectedTexture").SetSkipShadowUpdates ~= nil

local function onPreDrawSkyBox()
	if _occluded then return end
	if not IsValid(_ownerEnt) or not _lampTable then return end
	if not _cachedSunAngle or not _cachedSkyPos then return end

	-- PVS-gated optimisation: if the player's current BSP leaf can't see the
	-- 3D skybox at all, skip the entire skybox-lamp pass. Decoupled from
	-- csm_sunocclude so it works whenever NikNaks is installed.
	if NikNaks and NikNaks.CurrentMap and RealCSM.SunOcclude then
		local leaf = RealCSM.SunOcclude.GetEyeLeaf and RealCSM.SunOcclude.GetEyeLeaf()
		if leaf and not leaf:HasSkyboxInPVS() then return end
	end

	local pt = _lampTable[SKY_LAMP_IDX]
	if not IsValid(pt) then
		for _, v in pairs(_lampTable) do
			if IsValid(v) then pt = v break end
		end
	end
	if not IsValid(pt) then return end

	local hdr  = GetConVar("csm_hashdr"):GetInt() == 1
	-- Brightness: GetSunBrightness() stores raw _light intensity (e.g. 560 for gm_construct).
	-- Divisor 128 = 255 / OVERBRIGHT(2.0): matches VRAD's VectorScale(intensity, 1/255) export
	-- combined with the lightmap shader's 2.0 overbright multiplier (vrad/lightmap.cpp:1107).
	-- LDR multiplier 0.125 = flFlashlightScale_LDR(2.0) / flFlashlightScale_HDR(0.25) inverse
	-- (BaseVSShader.h:354 - shader hardcodes these to compensate for missing HDR tonemapper).
	local base = _ownerEnt:GetSunBrightness() / 128
	if not hdr then base = base * 0.125 end

	-- Optionally park other lamps (csm_skyboxlamp_mutenormal).
	-- OFF by default: Update() calls cost more than the extra render passes.
	-- ON: use when normal lamps visibly bleed into the skybox on specific maps.
	local muteNormal = GetConVar("csm_skyboxlamp_mutenormal"):GetBool()
	_savedOrthos = {}
	if muteNormal then
		for i, lpt in pairs(_lampTable) do
			if IsValid(lpt) and i ~= SKY_LAMP_IDX then
				local _, l, r, t, b = lpt:GetOrthographic()
				_savedOrthos[i] = (l + r + t + b) / 4
				lpt:SetOrthographic(true, 0.001, 0.001, 0.001, 0.001)
				lpt:Update()
			end
		end
	end

		-- Prefer the live texture over the static _tex3 string so that if
		-- frustum masks have set an RT on this PT, we restore the RT, not
		-- the stale static mask name (which would break the RT chain).
		-- FM.GetActiveRT(ent, idx) returns the RT if frustum masks are active.
		local fmRT = RealCSM.FrustumMasks and _ownerEnt
			and RealCSM.FrustumMasks._activeRTs
			and RealCSM.FrustumMasks._activeRTs[SKY_LAMP_IDX]
	-- Save lamp 3 state only.
	local _, l, r, t, b = pt:GetOrthographic()
	_savedState = {
		pt      = pt,
		pos     = pt:GetPos(),
		angles  = pt:GetAngles(),
		ortho   = (l + r + t + b) / 4,
		nearZ   = pt:GetNearZ(),
		farZ    = pt:GetFarZ(),
		bright  = pt:GetBrightness(),
		shadows = pt:GetEnableShadows(),
		col     = pt:GetColor(),
		tex     = fmRT or _tex3,
	}

	pt:SetPos(_cachedSkyPos)
	pt:SetAngles(_cachedSunAngle)
	pt:SetOrthographic(true, _cachedOrthoSize, _cachedOrthoSize, _cachedOrthoSize, _cachedOrthoSize)
	pt:SetNearZ(1)
	pt:SetFarZ(_cachedFarZ)
	pt:SetBrightness(base)
	pt:SetColor(_ownerEnt:GetSunColour():ToColor())
	pt:SetEnableShadows(false)
	pt:SetTexture("effects/flashlight/soft")
	if _hasSkipAPI then pt:SetSkipShadowUpdates(true) end
	pt:Update()
end

local function onPostDrawSkyBox()
	local s = _savedState
	if not s or not IsValid(s.pt) then return end

	s.pt:SetPos(s.pos)
	s.pt:SetAngles(s.angles)
	s.pt:SetOrthographic(true, s.ortho, s.ortho, s.ortho, s.ortho)
	s.pt:SetNearZ(s.nearZ)
	s.pt:SetFarZ(s.farZ)
	s.pt:SetBrightness(s.bright)
	s.pt:SetColor(s.col)
	s.pt:SetTexture(s.tex)
	s.pt:SetEnableShadows(s.shadows)
	if _hasSkipAPI then s.pt:SetSkipShadowUpdates(false) end
	s.pt:Update()

	_savedState = {}

	-- Restore parked lamps.
	if _savedOrthos then
		for i, s in pairs(_savedOrthos) do
			local lpt = _lampTable and _lampTable[i]
			if IsValid(lpt) then
				lpt:SetOrthographic(true, s, s, s, s)
				lpt:Update()
			end
		end
		_savedOrthos = {}
	end
end

-- ── Think integration ─────────────────────────────────────────────────────────

function M.Think(sunAngle, tex3)
	_cachedSunAngle = sunAngle
	if tex3 then _tex3 = tex3 end

	local skyCamPos = RealCSM.SkyCameraPos or Vector(0, 0, 0)

	if not _cachedOrthoSize then
		_cachedOrthoSize = calcOrthoSize(skyCamPos, sunAngle)
	end

	local fwdZ       = math.max(math.abs(sunAngle:Forward().z), 0.08)
	local lampOffset = _cachedOrthoSize / fwdZ
	_cachedSkyPos    = skyCamPos - sunAngle:Forward() * lampOffset
	_cachedFarZ      = lampOffset * 2 + 512
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.On(ent, lampTable)
	_ownerEnt  = ent
	_lampTable = lampTable
	if not _hooks then
		hook.Add("PreDrawSkyBox",  "RealCSM_SkyboxLamp", onPreDrawSkyBox)
		hook.Add("PostDrawSkyBox", "RealCSM_SkyboxLamp", onPostDrawSkyBox)
		_hooks = true
	end
end

function M.Off()
	hook.Remove("PreDrawSkyBox",  "RealCSM_SkyboxLamp")
	hook.Remove("PostDrawSkyBox", "RealCSM_SkyboxLamp")
	_hooks = false

	-- Restore if we were mid-pass when disabled.
	onPostDrawSkyBox()

	_ownerEnt        = nil
	_lampTable       = nil
	_cachedOrthoSize = nil
	_cachedSunAngle  = nil
	_cachedSkyPos    = nil
	_cachedFarZ      = nil
end

function M.UpdateLamps(lampTable)
	_lampTable = lampTable
end

-- Called by SunOcclude to suppress skybox lamp while player is indoors.
function M.SetOccluded(state)
	_occluded = state
end
