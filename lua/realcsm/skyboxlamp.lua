-- lua/realcsm/skyboxlamp.lua
-- Dedicated projected texture that lights the 3D skybox.
--
-- APPROACH:
--   The sky lamp is updated every frame in Think() (same as normal lamps) so
--   the engine sees it before the render pass begins.  PreDrawSkyBox /
--   PostDrawSkyBox only toggle brightness so the sky lamp is bright during
--   the skybox render and dark during the main world render.
--
--   The lamp is positioned in sky_camera-space (1/16th world scale), so its
--   orthographic frustum doesn't significantly overlap main world geometry.
--
-- WHY NOT UPDATE IN PreDrawSkyBox:
--   By the time PreDrawSkyBox fires the engine has already gathered all active
--   PTs for the current render pass.  Calling Update() there only takes effect
--   on the NEXT frame — too late to light the skybox in the current frame.
--   r_flashlightdrawfrustum confirmed: lamps updated in the hook never appear.

RealCSM = RealCSM or {}
local M = {}
RealCSM.SkyboxLamp = M

local SKYBOX_SCALE = 1 / 16

-- ── State ─────────────────────────────────────────────────────────────────────

local _skyLamp   = nil
local _ownerEnt  = nil
local _lampTable = nil
local _hooks     = false
local _cachedOrthoSize = nil  -- cached skybox extent (recomputed when sky_camera pos changes)
local _cachedSkyCamPos = nil

-- ── Lamp lifecycle ────────────────────────────────────────────────────────────

local function ensureSkyLamp()
	if IsValid(_skyLamp) then return end
	_skyLamp = ProjectedTexture()
	_skyLamp:SetTexture("csm/mask_center")
	_skyLamp:SetEnableShadows(false)
	_skyLamp:SetBrightness(0)
	_skyLamp:SetOrthographic(true, 512, 512, 512, 512)
	_skyLamp:SetQuadraticAttenuation(0)
	_skyLamp:SetLinearAttenuation(0)
	_skyLamp:SetConstantAttenuation(1)
	_skyLamp:Update()
end

local function destroySkyLamp()
	if IsValid(_skyLamp) then _skyLamp:Remove() end
	_skyLamp = nil
end

-- ── Brightness helpers ────────────────────────────────────────────────────────

local function calcNormalBrightness(i)
	if not IsValid(_ownerEnt) then return 1 end
	local hdr    = GetConVar("csm_hashdr"):GetInt() == 1
	local spread = GetConVar("csm_spread"):GetBool()
	local samples = GetConVar("csm_spread_samples"):GetInt()
	local base   = _ownerEnt:GetSunBrightness() / 400
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

-- ── Think integration (call every frame from entity Think) ────────────────────

-- Think integration (call every frame from entity Think, AFTER normal lamps updated)
-- sunAngle: the already-computed sun angle from the entity Think
function M.Think(sunAngle)
	if not IsValid(_ownerEnt) or not _lampTable then return end
	ensureSkyLamp()
	if not IsValid(_skyLamp) then return end

	local skyCamPos = RealCSM.SkyCameraPos or Vector(0, 0, 0)

	local height = _ownerEnt:GetHeight() * SKYBOX_SCALE
	local skyPos = skyCamPos - sunAngle:Forward() * height

	-- Calculate ortho size to cover the full skybox room.
	-- Cache this per sky_camera position (it never changes at runtime).
	if _cachedOrthoSize == nil or _cachedSkyCamPos ~= skyCamPos then
		local function traceExtent(dir)
			local tr = util.TraceLine({
				start  = skyCamPos,
				endpos = skyCamPos + dir * 65536,
				mask   = MASK_SOLID_BRUSHONLY,
			})
			if tr.Hit then return tr.Fraction * 65536 end
			return 4096
		end
		local right = sunAngle:Right()
		local up    = sunAngle:Up()
		local extentR = math.max(traceExtent(right), traceExtent(-right))
		local extentU = math.max(traceExtent(up),    traceExtent(-up))
		_cachedOrthoSize = math.Clamp(math.max(extentR, extentU) * 1.2, 512, 16384)
		_cachedSkyCamPos = skyCamPos
	end
	local orthoSize = _cachedOrthoSize

	_skyLamp:SetPos(skyPos)
	_skyLamp:SetAngles(sunAngle)
	_skyLamp:SetOrthographic(true, orthoSize, orthoSize, orthoSize, orthoSize)
	_skyLamp:SetColor(_ownerEnt:GetSunColour():ToColor())
	_skyLamp:SetNearZ(1)
	_skyLamp:SetFarZ(height * 2 + 512)
	_skyLamp:SetQuadraticAttenuation(0)
	_skyLamp:SetLinearAttenuation(0)
	_skyLamp:SetConstantAttenuation(1)
	-- Brightness is managed by the Pre/PostDrawSkyBox hooks; don't override here.
	_skyLamp:Update()
end

-- ── Hook callbacks (brightness toggle only) ───────────────────────────────────

local function onPreDrawSkyBox()
	if not IsValid(_ownerEnt) or not _lampTable then return end

	-- Dim normal lamps for the skybox render pass.
	setNormalLampsEnabled(false)

	-- Brighten the sky lamp for the skybox render pass.
	if IsValid(_skyLamp) then
		local hdr  = GetConVar("csm_hashdr"):GetInt() == 1
		local base = _ownerEnt:GetSunBrightness() / 400
		if not hdr then base = base * 0.2 end
		_skyLamp:SetBrightness(base)
		_skyLamp:Update()
	end
end

local function onPostDrawSkyBox()
	-- Restore normal lamps.
	setNormalLampsEnabled(true)

	-- Kill sky lamp brightness for main world render.
	if IsValid(_skyLamp) then
		_skyLamp:SetBrightness(0)
		_skyLamp:Update()
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.On(ent, lampTable)
	_ownerEnt  = ent
	_lampTable = lampTable

	ensureSkyLamp()

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

	destroySkyLamp()
	setNormalLampsEnabled(true)

	_ownerEnt  = nil
	_lampTable = nil
	_cachedOrthoSize = nil
	_cachedSkyCamPos = nil
end

function M.UpdateLamps(lampTable)
	_lampTable = lampTable
end
