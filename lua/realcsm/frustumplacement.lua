-- lua/realcsm/frustumplacement.lua
-- Optimal per-cascade projected-texture placement matched to the view frustum.
--
-- For each cascade slab [near_i .. far_i]:
--   1. Compute view-frustum corners in world space.
--   2. Project into light-space 2D (perpendicular to sun direction).
--   3. AABB of projected corners → tight cascade coverage box.
--   4. Lift along -sunFwd by sunHeight (lamp position).
--   5. Round half-extent up to pow2 (square shadowmap-friendly).
--   6. Optional forward-bias: shift slack in front of camera (csm_shift_forward).
--   7. Snap to a grid that satisfies BOTH the depth texel AND the cutout-mask
--      pixel grid (when CascadeMasks is in use), so shadow snapping is stable
--      AND carve boundaries are pixel-perfect.
--   8. Apply pt:SetOrthographic / SetPos / SetAngles.
--   9. (Optional) Hand the result to CascadeMasks.Refresh to paint masks.
--
-- This module only handles POSITIONING. Mask painting is in cascademasks.lua.
-- Gate convar:
--   csm_frustum_placement - enable runtime frustum-matched placement
-- When CascadeMasks is also enabled (csm_cascade_masks=1) this module's
-- snap pass honors its grid for pixel-perfect carve alignment, and the
-- final pass hands the positioned cascades off to CascadeMasks.Refresh.

RealCSM = RealCSM or {}
local FP = {}
RealCSM.FrustumPlacement = FP

-- ── Convars (placement only) ────────────────────────────────────────────────

local cvRollStep    = CreateClientConVar("csm_roll_step", "360", true, false,
	"Quantize lamp roll alignment to this many degrees (0 = continuous w/ shimmer, 360 = disabled)")
local cvShiftFwd    = CreateClientConVar("csm_shift_forward", "1", true, false,
	"Shift symmetric square cascade boxes along camera-forward so slack is in front, not behind the player (0-1)")
local cvFarFovScale = CreateClientConVar("csm_far_fov_scale", "1.0", true, false,
	"Scale the effective FOV for the outermost cascade (0.3-1.0). Smaller = tighter far cascade, more distance, less peripheral far-shadow coverage.")
local cvAsymOrtho   = CreateClientConVar("csm_asymmetric_ortho", "0", true, false,
	"Use asymmetric ortho (hx != hy) for cascade boxes. Tighter fit but shadow texels are anisotropic.")

-- ── Frustum corners at cumulative depth ─────────────────────────────────────

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

local function projectAABB_abs(corners, sunRight, sunUp)
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	for i = 1, #corners do
		local x = corners[i]:Dot(sunRight)
		local y = corners[i]:Dot(sunUp)
		if x < minX then minX = x end
		if x > maxX then maxX = x end
		if y < minY then minY = y end
		if y > maxY then maxY = y end
	end
	return minX, minY, maxX, maxY
end

-- ── HUD viz: top-down minimap of cascade coverage ───────────────────────────

FP._lastCascades = nil

local CASCADE_COLORS = {
	Color(230, 50,  50,  200),
	Color(60,  190, 90,  200),
	Color(70,  100, 220, 200),
	Color(230, 200, 60,  200),
}

local HUD_SIZE   = 256
local HUD_MARGIN = 16

function FP.DrawHUDViz()
	local cv = GetConVar("csm_frustum_viz")
	if not (cv and cv:GetBool()) then return end

	local sw = ScrW()
	local x0 = sw - HUD_SIZE - HUD_MARGIN
	local y0 = HUD_MARGIN
	local hcx = x0 + HUD_SIZE * 0.5
	local hcy = y0 + HUD_SIZE * 0.5

	surface.SetDrawColor(20, 20, 20, 200)
	surface.DrawRect(x0, y0, HUD_SIZE, HUD_SIZE)
	surface.SetDrawColor(80, 80, 80, 255)
	surface.DrawOutlinedRect(x0, y0, HUD_SIZE, HUD_SIZE)

	local cascades = FP._lastCascades
	if not cascades then
		draw.SimpleText("_lastCascades is nil", "DermaDefault",
			x0 + 6, y0 + 6, Color(255, 100, 100), 0, 0)
		return
	end
	if #cascades == 0 then
		draw.SimpleText("#cascades == 0", "DermaDefault",
			x0 + 6, y0 + 6, Color(255, 100, 100), 0, 0)
		return
	end

	local camPos   = cascades.camPos
	local sunRight = cascades.sunRight
	local sunUp    = cascades.sunUp
	local camFwd   = cascades.camFwd

	local camCx = camPos:Dot(sunRight)
	local camCy = camPos:Dot(sunUp)

	local fx = camFwd:Dot(sunRight)
	local fy = camFwd:Dot(sunUp)
	local fmag = math.sqrt(fx*fx + fy*fy)
	if fmag < 1e-4 then
		draw.SimpleText("sun is parallel to camera", "DermaDefault",
			x0 + 6, y0 + 6, Color(255, 200, 100), 0, 0)
		return
	end
	fx, fy = fx / fmag, fy / fmag

	local maxExt = 1
	if cascades[#cascades] and cascades[#cascades].half then
		maxExt = cascades[#cascades].half * 1.2
	end
	local rects = {}
	for i, c in ipairs(cascades) do
		local asym = cvAsymOrtho:GetBool()
		local hx = asym and (c.hx or c.half) or (c.half or math.max(c.maxX - c.minX, c.maxY - c.minY) * 0.5)
		local hy = asym and (c.hy or c.half) or (c.half or math.max(c.maxX - c.minX, c.maxY - c.minY) * 0.5)
		local bxMin = c.cx - hx
		local bxMax = c.cx + hx
		local byMin = c.cy - hy
		local byMax = c.cy + hy
		local corners = {
			{ bxMin - camCx, byMax - camCy },
			{ bxMax - camCx, byMax - camCy },
			{ bxMax - camCx, byMin - camCy },
			{ bxMin - camCx, byMin - camCy },
		}
		local rotated = {}
		for k = 1, 4 do
			local rx, ry = corners[k][1], corners[k][2]
			local nx = fy * rx + fx * ry
			local ny = -fx * rx + fy * ry
			rotated[k] = { nx, ny }
		end
		rects[i] = rotated
	end

	local scale = (HUD_SIZE * 0.45) / maxExt

	if GetConVar("csm_frustum_debug") and GetConVar("csm_frustum_debug"):GetBool() then
		print(string.format("[HUD] n=%d maxExt=%.1f scale=%.4f fx=%.2f fy=%.2f camCx=%.1f camCy=%.1f",
			#cascades, maxExt, scale, fx, fy, camCx, camCy))
		for i, c in ipairs(cascades) do
			print(string.format("  c%d cx=%.1f cy=%.1f half=%.1f",
				i, c.cx, c.cy, c.half or -1))
		end
	end

	for i = #cascades, 1, -1 do
		local col = CASCADE_COLORS[i] or color_white
		local r = rects[i]
		local pts = {}
		for k = 1, 4 do
			pts[k] = {
				x = hcx + r[k][1] * scale,
				y = hcy - r[k][2] * scale,
				u = 0, v = 0,
			}
		end
		draw.NoTexture()
		surface.SetDrawColor(col)
		surface.DrawPoly(pts)
		surface.SetDrawColor(col.r, col.g, col.b, 255)
		for k = 1, 4 do
			local a = pts[k]
			local b = pts[(k % 4) + 1]
			surface.DrawLine(a.x, a.y, b.x, b.y)
		end
	end

	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawPoly({
		{ x = hcx,     y = hcy - 7, u = 0, v = 0 },
		{ x = hcx - 5, y = hcy + 5, u = 0, v = 0 },
		{ x = hcx + 5, y = hcy + 5, u = 0, v = 0 },
	})

	draw.SimpleText(
		string.format("cascades (ext=%.0f)", maxExt),
		"DermaDefault",
		x0 + 6, y0 + 4,
		Color(220, 220, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP
	)
	for i, col in ipairs(CASCADE_COLORS) do
		if cascades[i] then
			draw.SimpleText(
				"C" .. i, "DermaDefault",
				x0 + 6 + (i - 1) * 28, y0 + HUD_SIZE - 16,
				col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP
			)
		end
	end
end

hook.Add("HUDPaint", "RealCSMFrustumViz", FP.DrawHUDViz)

-- ── Main: position cascades + (optionally) refresh masks ────────────────────

function FP.UpdatePlacement(ent, sunAngle, sunHeight, splitDistances, cascades, camPos, camAng, fovV)
	if not GetConVar("csm_frustum_placement"):GetBool() then return false end

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

	-- Roll the light-space basis so sunRight aligns with camera forward
	-- projected onto the sun-perpendicular plane. Tighter axis-aligned AABB.
	do
		local camFwd = camAng:Forward()
		local dotF   = camFwd:Dot(sunFwd)
		local proj   = Vector(
			camFwd.x - sunFwd.x * dotF,
			camFwd.y - sunFwd.y * dotF,
			camFwd.z - sunFwd.z * dotF
		)
		local len = proj:Length()
		if len > 0.01 then
			local nRight = proj / len
			local nUp    = sunFwd:Cross(nRight); nUp:Normalize()
			local cosR = sunRight:Dot(nRight)
			local sinR = sunUp:Dot(nRight)
			local roll = math.deg(math.atan2(sinR, cosR))
			-- Quantize roll → discrete steps so the texel grid only jumps
			-- occasionally rather than rotating continuously with camera yaw.
			local step = cvRollStep:GetFloat()
			if step > 0 then
				roll = math.floor(roll / step + 0.5) * step
			end
			sunAngle   = Angle(sunAngle.p, sunAngle.y, sunAngle.r + roll)
			sunFwd     = sunAngle:Forward()
			sunRight   = sunAngle:Right()
			sunUp      = sunAngle:Up()
		end
	end

	-- Pass 0: compute each cascade's absolute light-space AABB.
	-- PSSM slabs (cascade i covers split[i-1] → split[i]) for tight outers.
	local perCascade = {}
	for i, casc in ipairs(cascades) do
		if not IsValid(casc.pt) then break end
		local farZ  = splitDistances[i]
		if not farZ then break end
		local slabNear = (i == 1) and nearZ or splitDistances[i-1]

		-- Outermost cascade may use a narrower FOV to trim peripheral coverage.
		local effFov, effAspect = fovV, aspect
		if i == #cascades then
			local scale = math.Clamp(cvFarFovScale:GetFloat(), 0.3, 1.0)
			effFov = fovV * scale
		end

		local corners = getFrustumCorners(camPos, camAng, effFov, effAspect, slabNear, farZ)
		local minX, minY, maxX, maxY = projectAABB_abs(corners, sunRight, sunUp)

		local cx = (minX + maxX) * 0.5
		local cy = (minY + maxY) * 0.5
		local camCx = camPos:Dot(sunRight)
		local camCy = camPos:Dot(sunUp)
		local lampWorld = camPos
			+ sunRight * (cx - camCx)
			+ sunUp    * (cy - camCy)
			- sunFwd   * sunHeight

		perCascade[i] = {
			pt = casc.pt,
			ptPos = lampWorld,
			hx = (maxX - minX) * 0.5,
			hy = (maxY - minY) * 0.5,
			minX = minX, minY = minY, maxX = maxX, maxY = maxY,
			cx = cx, cy = cy,
		}
	end

	-- Cache for HUD viz (must be set before any early return below).
	perCascade.sunRight = sunRight
	perCascade.sunUp    = sunUp
	perCascade.sunFwd   = sunFwd
	perCascade.camPos   = camPos
	perCascade.camRight = camAng:Right()
	perCascade.camFwd   = camAng:Forward()
	FP._lastCascades    = perCascade

	-- Pass 1: stable pow2 half per cascade.
	for _, info in ipairs(perCascade) do
		local rawHalf = math.max(info.hx, info.hy)
		local h = 1
		while h < rawHalf do h = h * 2 end
		info.half = h
	end

	-- Pass 1.5: forward-bias each cascade by its own slack (slack = pow2 half
	-- minus AABB half). Keeps slack in front of the camera, not behind.
	local shiftFrac = math.Clamp(cvShiftFwd:GetFloat(), 0, 1)
	if shiftFrac > 0 and #perCascade > 0 then
		local camFwd = camAng:Forward()
		local fwdX   = camFwd:Dot(sunRight)
		local fwdY   = camFwd:Dot(sunUp)
		local fmag   = math.sqrt(fwdX*fwdX + fwdY*fwdY)
		if fmag > 1e-4 then
			fwdX, fwdY = fwdX / fmag, fwdY / fmag
			local edgeUV = RealCSM.CascadeMasks and RealCSM.CascadeMasks.GetEdgeUV() or 0.10
			for _, info in ipairs(perCascade) do
				local backFade = 2 * edgeUV * info.half
				local shiftX = math.max(0, (info.half - info.hx) - backFade) * shiftFrac
				local shiftY = math.max(0, (info.half - info.hy) - backFade) * shiftFrac
				info.cx = info.cx + shiftX * fwdX
				info.cy = info.cy + shiftY * fwdY
			end
		end
	end

	-- Pass 2: snap cx/cy to the COARSEST relevant grid:
	--   - own depth-texel grid (= 2*half / r_flashlightdepthres)  → stable shadows
	--   - cutout-mask pixel grid (from CascadeMasks.SuggestGrid)  → carve alignment
	-- Use math.max so both constraints are simultaneously satisfied.
	-- (At depthRes > 1024, depthTexel < maskPixel, which is exactly when
	--  the old per-cascade-only grid broke at higher shadowmap resolutions.)
	local depthRes = GetConVar("r_flashlightdepthres") and GetConVar("r_flashlightdepthres"):GetInt() or 512
	local maskGrid = (RealCSM.CascadeMasks and RealCSM.CascadeMasks.SuggestGrid(perCascade)) or 0
	for _, info in ipairs(perCascade) do
		local h = info.half
		local depthTexel = (2 * h) / depthRes
		local grid = math.max(depthTexel, maskGrid)
		local snappedCx = math.floor(info.cx / grid + 0.5) * grid
		local snappedCy = math.floor(info.cy / grid + 0.5) * grid
		local camCxLS = camPos:Dot(sunRight)
		local camCyLS = camPos:Dot(sunUp)
		local snappedLampWorld = camPos
			+ sunRight * (snappedCx - camCxLS)
			+ sunUp    * (snappedCy - camCyLS)
			- sunFwd   * sunHeight
		info.cx    = snappedCx
		info.cy    = snappedCy
		info.ptPos = snappedLampWorld
		if cvAsymOrtho:GetBool() then
			info.pt:SetOrthographic(true, info.hx, info.hy, info.hx, info.hy)
		else
			info.pt:SetOrthographic(true, h, h, h, h)
		end
		info.pt:SetPos(snappedLampWorld)
		info.pt:SetAngles(sunAngle)
	end

	if GetConVar("csm_frustum_debug") and GetConVar("csm_frustum_debug"):GetBool() then
		for i, info in ipairs(perCascade) do
			local relLampX = info.ptPos:Dot(sunRight) - camPos:Dot(sunRight)
			local relLampY = info.ptPos:Dot(sunUp)    - camPos:Dot(sunUp)
			Msg(string.format(
				"[FP] c%d hx=%.1f hy=%.1f lampLS=(%.1f,%.1f) minX=%.1f maxX=%.1f minY=%.1f maxY=%.1f\n",
				i, info.hx, info.hy, relLampX, relLampY,
				info.minX - camPos:Dot(sunRight),
				info.maxX - camPos:Dot(sunRight),
				info.minY - camPos:Dot(sunUp),
				info.maxY - camPos:Dot(sunUp)
			))
		end
	end

	-- Pass 3: hand off to CascadeMasks for mask painting + binding.
	if GetConVar("csm_cascade_masks"):GetBool() and RealCSM.CascadeMasks then
		RealCSM.CascadeMasks.Refresh(ent, perCascade)
	end

	return true
end

-- ── Cascade split helpers ───────────────────────────────────────────────────
-- PSSM split: blend log + linear distribution by lambda.

function FP.ComputeSplits(near, far, n, lambda)
	lambda = lambda or 0.8
	local splits = {}
	for i = 1, n do
		local si = i / n
		local logSplit = near * (far / near) ^ si
		local linSplit = near + (far - near) * si
		splits[i] = lambda * logSplit + (1 - lambda) * linSplit
	end
	return splits
end
