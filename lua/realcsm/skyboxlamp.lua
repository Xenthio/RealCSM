-- lua/realcsm/skyboxlamp.lua
-- Dedicated projected texture that lights the 3D skybox.
--
-- PERFORMANCE APPROACH:
--   The sky PT is CREATED in PreDrawSkyBox and REMOVED in PostDrawSkyBox.
--   This means it does NOT exist during the main world render, so it costs
--   zero additional render.RenderFlashlights passes on the main scene.
--   It only exists for the duration of the skybox render pass.
--
--   PreDrawSkyBox fires after the main world has been rendered and before
--   the skybox render begins, so Update() there is in time for the skybox.
--
--   Normal lamps are zeroed during skybox render and restored after, so
--   they don't bleed into the skybox.

RealCSM = RealCSM or {}
local M = {}
RealCSM.SkyboxLamp = M

local SKYBOX_SCALE = 1 / 16

-- ── State ─────────────────────────────────────────────────────────────────────

local _ownerEnt       = nil
local _lampTable      = nil
local _hooks          = false
local _skyLamp        = nil   -- only valid between Pre/PostDrawSkyBox
local _cachedOrthoSize = nil
local _cachedSunAngle  = nil  -- last sunAngle from Think(), used in hook

-- ── Brightness helpers ────────────────────────────────────────────────────────

local function calcNormalBrightness(i)
	if not IsValid(_ownerEnt) then return 1 end
	local hdr     = GetConVar("csm_hashdr"):GetInt() == 1
	local spread  = GetConVar("csm_spread"):GetBool()
	local samples = GetConVar("csm_spread_samples"):GetInt()
	local base    = _ownerEnt:GetSunBrightness() / 400
	if not hdr then base = base * 0.2 end
	if spread and (i == 1 or i == 2 or i > 4) then
		base = base / samples
	end
	return base
end

local function setNormalLampsEnabled(on)
	if not _lampTable then return end
	for i, pt in pairs(_lampTable) do
		if IsValid(pt) then
			pt:SetBrightness(on and calcNormalBrightness(i) or 0)
			pt:Update()
		end
	end
end

-- ── Skybox extent cache ───────────────────────────────────────────────────────

local function calcOrthoSize(skyCamPos, sunAngle)
	-- Sample in 8 lateral directions to cover irregularly-shaped skybox rooms.
	local right = sunAngle:Right()
	local up    = sunAngle:Up()
	local maxExtent = 0
	for _, dir in ipairs({
		 right,  -right,  up,  -up,
		(right + up):GetNormalized(),
		(right - up):GetNormalized(),
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

local function onPreDrawSkyBox()
	if not IsValid(_ownerEnt) or not _lampTable then return end

	-- Zero normal lamps so they don't bleed into the skybox.
	setNormalLampsEnabled(false)

	local sunAngle  = _cachedSunAngle
	if not sunAngle then return end

	local skyCamPos = RealCSM.SkyCameraPos or Vector(0, 0, 0)
	local fwdZ      = math.max(math.abs(sunAngle:Forward().z), 0.08)

	-- Compute ortho size once (cached per sky_camera pos).
	if not _cachedOrthoSize then
		_cachedOrthoSize = calcOrthoSize(skyCamPos, sunAngle)
	end
	local orthoSize = _cachedOrthoSize

	-- Position: place the lamp orthogonally above sky_camera along the sun's
	-- vertical component so the frustum covers the full room on all sides.
	-- farZ = 2 * room_height / sin(pitch) ensures the frustum reaches the floor.
	local roomHeight = orthoSize  -- conservative estimate; sun pitch adjusts coverage
	local lampOffset = roomHeight / fwdZ
	local skyPos     = skyCamPos - sunAngle:Forward() * lampOffset
	local farZ       = lampOffset * 2 + 512

	-- Create the sky lamp fresh each frame — it won't cost anything during
	-- the main world render because it doesn't exist yet at that point.
	if IsValid(_skyLamp) then _skyLamp:Remove() end
	_skyLamp = ProjectedTexture()
	_skyLamp:SetTexture("csm/mask_center")
	_skyLamp:SetEnableShadows(false)
	_skyLamp:SetPos(skyPos)
	_skyLamp:SetAngles(sunAngle)
	_skyLamp:SetOrthographic(true, orthoSize, orthoSize, orthoSize, orthoSize)
	_skyLamp:SetNearZ(1)
	_skyLamp:SetFarZ(farZ)

	local hdr  = GetConVar("csm_hashdr"):GetInt() == 1
	local base = _ownerEnt:GetSunBrightness() / 400
	if not hdr then base = base * 0.2 end
	_skyLamp:SetBrightness(base)
	_skyLamp:SetColor(_ownerEnt:GetSunColour():ToColor())
	_skyLamp:SetQuadraticAttenuation(0)
	_skyLamp:SetLinearAttenuation(0)
	_skyLamp:SetConstantAttenuation(1)
	_skyLamp:Update()
end

local function onPostDrawSkyBox()
	-- Remove sky lamp — it must not exist during next frame's main render.
	if IsValid(_skyLamp) then
		_skyLamp:Remove()
		_skyLamp = nil
	end

	-- Restore normal lamps.
	setNormalLampsEnabled(true)
end

-- ── Think integration (cache sunAngle for use in the hook) ────────────────────

-- Called every frame from entity Think AFTER sunAngle is computed.
-- Does NOT create a PT — just caches the angle so the hook can use it.
function M.Think(sunAngle)
	_cachedSunAngle = sunAngle
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

	if IsValid(_skyLamp) then _skyLamp:Remove() end
	_skyLamp = nil

	setNormalLampsEnabled(true)

	_ownerEnt        = nil
	_lampTable       = nil
	_cachedOrthoSize = nil
	_cachedSunAngle  = nil
end

function M.UpdateLamps(lampTable)
	_lampTable = lampTable
end
