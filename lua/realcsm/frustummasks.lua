-- lua/realcsm/frustummasks.lua
-- "Proper" frustum cascade placement + runtime cutout masks.
--
-- For each cascade:
--   1. Compute camera view-frustum slice corners at cumulative depth
--      (nearZ → cascade_far)
--   2. Project corners into light space (2D plane perpendicular to sun dir)
--   3. AABB those projected points → that's the ortho box for this cascade
--   4. Place the PT at AABB center, pushed UP along sun direction
--   5. Paint a render-target mask = white AABB minus inner cascade's AABB
--      (reprojected into this cascade's UV frame) so cascades tile without
--      overlap. Mask also handles the cutout.
--
-- Gate convar: csm_frustum_masks (0/1)

RealCSM = RealCSM or {}
local FM = {}
RealCSM.FrustumMasks = FM

local MASK_SIZE = 128

-- ── RT pool ──────────────────────────────────────────────────────────────────

function FM.GetRT(ent, i)
	ent._fmRTs = ent._fmRTs or {}
	if not ent._fmRTs[i] then
		local name = "csm_mask_rt_" .. ent:EntIndex() .. "_" .. i
		ent._fmRTs[i] = GetRenderTargetEx(
			name,
			MASK_SIZE, MASK_SIZE,
			RT_SIZE_LITERAL,
			MATERIAL_RT_DEPTH_NONE,
			0, 0,
			IMAGE_FORMAT_RGBA8888
		)
	end
	return ent._fmRTs[i]
end

-- ── Frustum corners at cumulative depth ──────────────────────────────────────

local function getFrustumCorners(pos, ang, fovV_deg, aspect, nearZ, farZ)
	local fwd, right, up = ang:Forward(), ang:Right(), ang:Up()
	local tanV = math.tan(math.rad(fovV_deg) * 0.5)
	local tanH = tanV * aspect

	local out = {}
	for _, d in ipairs({ nearZ, farZ }) do
		local hv = tanV * d
		local hh = tanH * d
		local c  = pos + fwd * d
		out[#out + 1] = c + right * hh + up * hv
		out[#out + 1] = c + right * hh - up * hv
		out[#out + 1] = c - right * hh + up * hv
		out[#out + 1] = c - right * hh - up * hv
	end
	return out
end

-- ── Project world points to light-space 2D (ptRight, ptUp) ───────────────────
-- Returns AABB in LIGHT-SPACE WORLD UNITS (not UV).
--   minX, minY, maxX, maxY  (along ptRight, ptUp respectively)
-- lightSpaceRef is any anchor point; we dot relative positions.

local function projectAABB(corners, lightSpaceRef, ptRight, ptUp)
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	for i = 1, #corners do
		local rel = corners[i] - lightSpaceRef
		local x = rel:Dot(ptRight)
		local y = rel:Dot(ptUp)
		if x < minX then minX = x end
		if x > maxX then maxX = x end
		if y < minY then minY = y end
		if y > maxY then maxY = y end
	end
	return minX, minY, maxX, maxY
end

-- ── Paint mask: white outer rect minus black inner rect in this cascade's UV ─
-- outerBounds = {minX, minY, maxX, maxY} in THIS cascade's local ortho space,
--               centered at 0 (so minX = -halfW, maxX = +halfW, etc.)
-- innerBounds = same but for the inner cascade's rect reprojected into THIS
--               cascade's coordinate system. Can be nil for the innermost.
-- halfSize = this cascade's half-width (for mapping to UV)

local function paintMask(rt, innerInThisUV)
	render.PushRenderTarget(rt)
	render.Clear(255, 255, 255, 255, false, false) -- full white = full coverage

	if innerInThisUV then
		cam.Start2D()
			surface.SetDrawColor(0, 0, 0, 255)
			-- innerInThisUV = {minU, minV, maxU, maxV} in [0..1]
			-- Convert to pixel coords. V is flipped for screen-space (cam.Start2D y-down).
			local x1 = innerInThisUV[1] * MASK_SIZE
			local x2 = innerInThisUV[3] * MASK_SIZE
			local y1 = (1 - innerInThisUV[4]) * MASK_SIZE
			local y2 = (1 - innerInThisUV[2]) * MASK_SIZE
			surface.DrawRect(x1, y1, x2 - x1, y2 - y1)
		cam.End2D()
	end

	render.PopRenderTarget()
end

-- ── Main: compute per-cascade placement + masks ─────────────────────────────
--
-- cascades: array in order near→far. Input just needs { pt = ProjectedTexture }
-- sunAngle: PT angle (down the sun direction)
-- sunHeight: how far to push the lamp back along sun direction (far above)
-- splitDistances: array of cumulative far depths, same length as cascades
--                 e.g. {300, 1500, 8000} = near ends at 300, mid ends at 1500, etc.
-- nearZ: camera near plane (7 is Source default)
--
-- Returns true if we handled placement (skip the base Think's SetPos/SetOrtho).

function FM.UpdatePlacement(ent, sunAngle, sunHeight, splitDistances, cascades, camPos, camAng, fovV)
	if not GetConVar("csm_frustum_masks"):GetBool() then return false end

	local lp = LocalPlayer()
	if not IsValid(lp) then return false end

	camPos = camPos or EyePos()
	camAng = camAng or EyeAngles()
	fovV   = fovV or lp:GetFOV()
	local aspect = ScrW() / ScrH()
	local nearZ  = 7

	local sunFwd   = sunAngle:Forward()
	local sunRight = sunAngle:Right()
	local sunUp    = sunAngle:Up()

	-- Degenerate: viewing straight along the sun. Fall back to base system.
	local viewDot = math.abs(camAng:Forward():Dot(sunFwd))
	if viewDot > 0.97 then return false end

	-- Step 1: for each cascade, compute cumulative frustum AABB in light-space
	-- world units. Use camPos as our light-space reference (any fixed ref works).
	local perCascade = {}
	for i, casc in ipairs(cascades) do
		if not IsValid(casc.pt) then break end
		local farZ = splitDistances[i]
		if not farZ then break end

		local corners = getFrustumCorners(camPos, camAng, fovV, aspect, nearZ, farZ)
		local minX, minY, maxX, maxY = projectAABB(corners, camPos, sunRight, sunUp)

		-- Center of AABB in light-space 2D (relative to camPos)
		local cx = (minX + maxX) * 0.5
		local cy = (minY + maxY) * 0.5
		-- Half-extents
		local hx = (maxX - minX) * 0.5
		local hy = (maxY - minY) * 0.5

		-- Square up: ortho boxes need square for texel snap / shadow resolution.
		-- Take the larger half-extent.
		local half = math.max(hx, hy)

		-- World-space lamp position:
		--   start at camPos, offset by (cx, cy) in light-space basis,
		--   then push UP along -sunFwd (sun comes from sunFwd direction, so
		--   the lamp lives OPPOSITE of the sun's forward direction — i.e., up
		--   along -sunFwd = the direction the sun shines FROM).
		-- Actually sunAngle:Forward() is the direction light travels (downward).
		-- The lamp should be in the OPPOSITE direction from its target.
		-- RealCSM uses offset = Vector(0,0,1) rotated by (pitch,yaw,roll) to
		-- place the lamp ABOVE; the lamp's angle points from there toward ground.
		-- So we want to lift along -sunFwd: lamp = target + (-sunFwd)*height.
		local lightSpaceCenter = camPos + sunRight * cx + sunUp * cy
		local ptPos = lightSpaceCenter - sunFwd * sunHeight

		perCascade[i] = {
			pt = casc.pt,
			ptPos = ptPos,
			half = half,
			-- Store AABB in light-space ABSOLUTE coords for cutout calculation:
			minX = camPos:Dot(sunRight) + cx - half,
			minY = camPos:Dot(sunUp)    + cy - half,
			maxX = camPos:Dot(sunRight) + cx + half,
			maxY = camPos:Dot(sunUp)    + cy + half,
			center = lightSpaceCenter,
		}
	end

	-- Step 2: apply placement + ortho
	for i, info in ipairs(perCascade) do
		info.pt:SetOrthographic(true, info.half, info.half, info.half, info.half)
		info.pt:SetPos(info.ptPos)
		info.pt:SetAngles(sunAngle)
	end

	-- Debug print (gate on a convar so we can see what's happening).
	if GetConVar("csm_frustum_debug") and GetConVar("csm_frustum_debug"):GetBool() then
		for i, info in ipairs(perCascade) do
			Msg(string.format(
				"[FM] cascade %d half=%.1f ptPos=%s (camPos=%s)\n",
				i, info.half, tostring(info.ptPos), tostring(camPos)
			))
		end
	end

	-- Step 3: paint masks. Each cascade's mask = full white, with a black
	-- rect carved for the previous cascade's AABB reprojected into this
	-- cascade's UV space.
	for i, info in ipairs(perCascade) do
		local rt = FM.GetRT(ent, i)
		if not rt then break end

		local innerUV = nil
		if i > 1 and perCascade[i - 1] then
			local prev = perCascade[i - 1]
			-- Convert prev AABB (light-space absolute) into THIS cascade's UV [0..1]
			-- UV maps [center - half, center + half] → [0, 1]
			local thisMinX = info.center:Dot(sunRight) - info.half
			local thisMinY = info.center:Dot(sunUp)    - info.half
			local inv2h    = 0.5 / info.half

			local uMin = (prev.minX - thisMinX) * inv2h * 0.5 / 0.5  -- = (prev.minX - thisMinX) / (2*info.half)
			-- Simplify:
			uMin = (prev.minX - (info.center:Dot(sunRight) - info.half)) / (2 * info.half)
			local uMax = (prev.maxX - (info.center:Dot(sunRight) - info.half)) / (2 * info.half)
			local vMin = (prev.minY - (info.center:Dot(sunUp)    - info.half)) / (2 * info.half)
			local vMax = (prev.maxY - (info.center:Dot(sunUp)    - info.half)) / (2 * info.half)

			-- Clamp
			if uMin < 0 then uMin = 0 end
			if uMax > 1 then uMax = 1 end
			if vMin < 0 then vMin = 0 end
			if vMax > 1 then vMax = 1 end

			if uMax > uMin and vMax > vMin then
				innerUV = { uMin, vMin, uMax, vMax }
			end
		end

		paintMask(rt, innerUV)
		info.pt:SetTexture(rt)
	end

	return true
end
