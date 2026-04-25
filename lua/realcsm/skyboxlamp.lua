-- lua/realcsm/skyboxlamp.lua
-- Dedicated projected texture that lights the 3D skybox.
--
-- PERFORMANCE DESIGN:
--   • One persistent PT, created in M.On(), removed in M.Off().
--   • Parked (orthoSize=0.001) during main render — covers no geometry,
--     engine skips it in RenderFlashlights. Zero render cost.
--   • PreDrawSkyBox: expand sky lamp (1 Update). Normal lamp muting is
--     opt-in via csm_skyboxlamp_mutenormal (default OFF) because on most
--     maps the normal lamp world-space frustums don't reach skybox geometry.
--   • PostDrawSkyBox: re-park sky lamp (1 Update). No normal-lamp Updates
--     unless muting was enabled.
--   • Think(): pure cache-write, no Update calls.
--
--   Minimum cost per frame: 2 Update() calls (Pre + Post expand/park).
--   With mutenormal ON: 2 + N*2 Updates (N = cascade count).

RealCSM = RealCSM or {}
local M = {}
RealCSM.SkyboxLamp = M

local SKYBOX_SCALE = 1 / 16
local PARKED_SIZE  = 0.001

-- ── State ─────────────────────────────────────────────────────────────────────

local _ownerEnt        = nil
local _lampTable       = nil
local _hooks           = false
local _skyLamp         = nil
local _cachedOrthoSize = nil
local _cachedSunAngle  = nil
local _cachedSkyPos    = nil
local _cachedFarZ      = nil

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

-- ── Sky lamp lifecycle ────────────────────────────────────────────────────────

local function createSkyLamp()
	if IsValid(_skyLamp) then return end
	_skyLamp = ProjectedTexture()
	_skyLamp:SetTexture("csm/mask_center")
	_skyLamp:SetEnableShadows(false)
	_skyLamp:SetBrightness(0)
	_skyLamp:SetOrthographic(true, PARKED_SIZE, PARKED_SIZE, PARKED_SIZE, PARKED_SIZE)
	_skyLamp:SetNearZ(1)
	_skyLamp:SetFarZ(2)
	_skyLamp:SetQuadraticAttenuation(0)
	_skyLamp:SetLinearAttenuation(0)
	_skyLamp:SetConstantAttenuation(1)
	_skyLamp:Update()
end

-- ── Normal lamp park/restore (opt-in) ─────────────────────────────────────────

local _savedSizes = {}

local function parkNormalLamps()
	if not _lampTable then return end
	_savedSizes = {}
	for i, pt in pairs(_lampTable) do
		if IsValid(pt) then
			local _, l, r, t, b = pt:GetOrthographic()
			_savedSizes[i] = (l + r + t + b) / 4
			pt:SetOrthographic(true, PARKED_SIZE, PARKED_SIZE, PARKED_SIZE, PARKED_SIZE)
			pt:SetLightWorld(false)
			pt:Update()
		end
	end
end

local function restoreNormalLamps()
	if not _lampTable then return end
	for i, pt in pairs(_lampTable) do
		if IsValid(pt) then
			local s = _savedSizes[i] or PARKED_SIZE
			pt:SetOrthographic(true, s, s, s, s)
			pt:SetLightWorld(true)
			pt:Update()
		end
	end
	_savedSizes = {}
end

-- ── Hook callbacks ────────────────────────────────────────────────────────────

local function onPreDrawSkyBox()
	if not IsValid(_skyLamp) or not IsValid(_ownerEnt) then return end
	if not _cachedSunAngle or not _cachedSkyPos then return end

	if GetConVar("csm_skyboxlamp_mutenormal"):GetBool() then
		parkNormalLamps()
	end

	local hdr  = GetConVar("csm_hashdr"):GetInt() == 1
	local base = _ownerEnt:GetSunBrightness() / 400
	if not hdr then base = base * 0.2 end

	_skyLamp:SetLightWorld(true)
	_skyLamp:SetPos(_cachedSkyPos)
	_skyLamp:SetAngles(_cachedSunAngle)
	_skyLamp:SetOrthographic(true, _cachedOrthoSize, _cachedOrthoSize, _cachedOrthoSize, _cachedOrthoSize)
	_skyLamp:SetNearZ(1)
	_skyLamp:SetFarZ(_cachedFarZ)
	_skyLamp:SetBrightness(base)
	_skyLamp:SetColor(_ownerEnt:GetSunColour():ToColor())
	_skyLamp:SetQuadraticAttenuation(0)
	_skyLamp:SetLinearAttenuation(0)
	_skyLamp:SetConstantAttenuation(1)
	_skyLamp:Update()
end

local function onPostDrawSkyBox()
	-- Re-park the sky lamp.
	if IsValid(_skyLamp) then
		_skyLamp:SetOrthographic(true, PARKED_SIZE, PARKED_SIZE, PARKED_SIZE, PARKED_SIZE)
		_skyLamp:SetBrightness(0)
		_skyLamp:SetNearZ(1)
		_skyLamp:SetFarZ(2)
		_skyLamp:SetLightWorld(false)
		_skyLamp:Update()
	end

	if GetConVar("csm_skyboxlamp_mutenormal"):GetBool() then
		restoreNormalLamps()
	end
end

-- ── Think integration ─────────────────────────────────────────────────────────

function M.Think(sunAngle)
	_cachedSunAngle = sunAngle

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
	createSkyLamp()
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
	if IsValid(_skyLamp) then _skyLamp:Remove() end
	_skyLamp = nil
	if GetConVar("csm_skyboxlamp_mutenormal") and GetConVar("csm_skyboxlamp_mutenormal"):GetBool() then
		restoreNormalLamps()
	end
	_ownerEnt        = nil
	_lampTable       = nil
	_cachedOrthoSize = nil
	_cachedSunAngle  = nil
	_cachedSkyPos    = nil
	_cachedFarZ      = nil
	_savedSizes      = {}
end

function M.UpdateLamps(lampTable)
	_lampTable = lampTable
end
