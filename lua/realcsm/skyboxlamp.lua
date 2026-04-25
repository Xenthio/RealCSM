-- lua/realcsm/skyboxlamp.lua
-- A single dedicated projected texture that lights the 3D skybox.
--
-- Problem: The normal CSM lamps are placed in world space (usually high above
-- the map). The 3D skybox is rendered from sky_camera at 1/16th scale at a
-- separate world origin, so a lamp positioned at e.g. (0, 0, 32768) in world
-- space may or may not happen to illuminate the skybox depending on whether
-- its frustum intersects the sky_camera zone.  This is the "only sometimes the
-- sky gets lit" behaviour.
--
-- Solution:
--   • On PreDrawSkyBox, disable the normal CSM lamps, enable a dedicated
--     sky-only lamp positioned correctly in sky_camera space.
--   • On PostDrawSkyBox, restore the normal lamps and kill the sky lamp.
--   • The sky lamp uses a full-center mask, no ring, with shadows OFF (skybox
--     geometry is usually simple enough and shadow maps in skybox cause artifacts).
--
-- Note on sky_camera scale:
--   The skybox world is 1/16th scale.  The sky_camera entity is at the world
--   position that maps to the skybox "centre".  We position our lamp at the
--   sky_camera position plus 1/16th of the normal lamp height offset, so it
--   matches the apparent sun position the player sees.

RealCSM = RealCSM or {}
local M = {}
RealCSM.SkyboxLamp = M

-- ── State ─────────────────────────────────────────────────────────────────────

local _skyLamp       = nil   -- the dedicated skybox ProjectedTexture
local _ownerEnt      = nil   -- the edit_csm entity that owns this system
local _hooksActive   = false
local _normalLamps   = nil   -- reference to the owner's ProjectedTextures table

-- ── Helper: find sky_camera ────────────────────────────────────────────────────

local function getSkyCamera()
	return ents.FindByClass("sky_camera")[1]
end

-- ── Lamp setup ─────────────────────────────────────────────────────────────────

local function createSkyLamp()
	if _skyLamp and _skyLamp:IsValid() then return end
	_skyLamp = ProjectedTexture()
	_skyLamp:SetTexture("csm/mask_center")
	_skyLamp:SetEnableShadows(false)
	_skyLamp:SetOrthographic(true, 512, 512, 512, 512)
	_skyLamp:SetQuadraticAttenuation(0)
	_skyLamp:SetLinearAttenuation(0)
	_skyLamp:SetConstantAttenuation(1)
end

local function removeSkyLamp()
	if _skyLamp and _skyLamp:IsValid() then
		_skyLamp:Remove()
	end
	_skyLamp = nil
end

-- ── Hook callbacks ────────────────────────────────────────────────────────────

local function onPreDrawSkyBox()
	if not IsValid(_ownerEnt) then return end
	if not _normalLamps then return end

	-- Disable normal lamps so they don't bleed into the skybox.
	for _, pt in pairs(_normalLamps) do
		if IsValid(pt) then
			pt:SetBrightness(0)
			pt:Update()
		end
	end

	-- Position the sky lamp.
	local skyCamera = getSkyCamera()
	if not IsValid(skyCamera) then return end

	createSkyLamp()
	if not IsValid(_skyLamp) then return end

	-- Sky space scale factor.
	local SKYBOX_SCALE = 1 / 16

	-- Sun direction from the owner entity (already computed in Think).
	-- We read the current angle from the first valid normal lamp rather than
	-- re-computing, since Think runs before the draw hooks.
	local sunAngle = angle_zero
	for _, pt in pairs(_normalLamps) do
		if IsValid(pt) then
			sunAngle = pt:GetAngles()
			break
		end
	end

	-- Offset from sky_camera in sky-scaled coordinates.
	local skyHeight  = _ownerEnt:GetHeight() * SKYBOX_SCALE
	local sunOffset  = Vector(0, 0, 1)
	sunOffset:Rotate(Angle(sunAngle.p - 90, sunAngle.y, sunAngle.r))

	local skyLampPos = skyCamera:GetPos() - sunOffset * skyHeight

	-- Ortho size: use the far cascade size, scaled down.
	local orthoSize = _ownerEnt:GetSizeFar() * SKYBOX_SCALE
	orthoSize = math.Clamp(orthoSize, 64, 4096)

	-- Brightness: match normal lamps.
	local sunBright = _ownerEnt:GetSunBrightness() / 400

	_skyLamp:SetPos(skyLampPos)
	_skyLamp:SetAngles(sunAngle)
	_skyLamp:SetOrthographic(true, orthoSize, orthoSize, orthoSize, orthoSize)
	_skyLamp:SetBrightness(sunBright)
	_skyLamp:SetColor(_ownerEnt:GetSunColour():ToColor())
	_skyLamp:SetNearZ(1.0)
	_skyLamp:SetFarZ(skyHeight * 2 + 256)
	_skyLamp:Update()
end

local function onPostDrawSkyBox()
	if not IsValid(_ownerEnt) then return end
	if not _normalLamps then return end

	-- Kill the sky lamp now that the skybox render is done.
	-- We do NOT remove it permanently — we'll recreate or update it next frame.
	if IsValid(_skyLamp) then
		_skyLamp:SetBrightness(0)
		_skyLamp:Update()
	end

	-- Restore normal lamp brightness.  The actual brightness value will be
	-- re-set correctly on the next Think(), but we need a non-zero value NOW
	-- so the main world render sees light again.  Use a sentinel; Think corrects it.
	local sunBright = IsValid(_ownerEnt) and (_ownerEnt:GetSunBrightness() / 400) or 1
	local spreadEnabled = GetConVar("csm_spread"):GetBool()
	local spreadSamples = GetConVar("csm_spread_samples"):GetInt()

	for i, pt in pairs(_normalLamps) do
		if IsValid(pt) then
			local br = sunBright
			if spreadEnabled then
				if i == 1 or i == 2 or i > 4 then
					br = br / spreadSamples
				end
			end
			pt:SetBrightness(br)
			pt:Update()
		end
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Call once when CSM entity spawns (or when the skybox-lamp setting changes to ON).
-- ent       : the edit_csm entity
-- lampTable : reference to ent.ProjectedTextures
function M.On(ent, lampTable)
	_ownerEnt    = ent
	_normalLamps = lampTable

	if not _hooksActive then
		hook.Add("PreDrawSkyBox",  "RealCSM_SkyboxLamp", onPreDrawSkyBox)
		hook.Add("PostDrawSkyBox", "RealCSM_SkyboxLamp", onPostDrawSkyBox)
		_hooksActive = true
	end
end

-- Call when CSM entity is removed or the skybox-lamp setting is turned OFF.
function M.Off()
	hook.Remove("PreDrawSkyBox",  "RealCSM_SkyboxLamp")
	hook.Remove("PostDrawSkyBox", "RealCSM_SkyboxLamp")
	_hooksActive = false

	removeSkyLamp()

	-- Restore normal lamp brightness (they may have been set to 0 mid-frame).
	if _normalLamps then
		local sunBright = IsValid(_ownerEnt) and (_ownerEnt:GetSunBrightness() / 400) or 1
		for _, pt in pairs(_normalLamps) do
			if IsValid(pt) then
				pt:SetBrightness(sunBright)
				pt:Update()
			end
		end
	end

	_ownerEnt    = nil
	_normalLamps = nil
end

-- Call when the lamp table is rebuilt (e.g. after cascade count change).
function M.UpdateLamps(lampTable)
	_normalLamps = lampTable
end
