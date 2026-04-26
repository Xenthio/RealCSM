-- lua/realcsm/frustummasks.lua
-- Runtime frustum-matched cascade placement + cutout masks.
--
-- Per cascade:
--   1. View-frustum corners at cumulative depth (nearZ → splits[i])
--   2. Project into light-space 2D (perpendicular to sun direction)
--   3. AABB of projected corners → light-space coverage box
--   4. Lamp at AABB center, lifted along -sunFwd by sunHeight
--   5. ortho = SetOrthographic(true, h, h, h, h) for the actual PT call
--      (or hx/hy if asymmetric ortho experiment is enabled)
--   6. Paint RT mask: soft-edge white rect (this cascade's full bounds)
--      minus soft-edge black rect (inner cascade's bounds reprojected
--      into this cascade's UV frame). Prevents double-coverage.
--
-- Gate convar: csm_frustum_masks (0/1)

RealCSM = RealCSM or {}
local FM = {}
RealCSM.FrustumMasks = FM

local MASK_SIZE = 1024

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

-- ── Project world points into absolute light-space 2D coords ─────────────────

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

-- ── Soft-edge mask paint ─────────────────────────────────────────────────────
-- Paints a white rect with a soft alpha falloff near edges, and if innerUV is
-- given, paints a black rect (also soft-edged) over it to carve the cutout.
-- All coords in [0..1] UV space. V axis is flipped (cam.Start2D is y-down).
--
-- Soft edge is done by painting several concentric rects with increasing alpha
-- toward the center. Crude but cheap and matches the soft mask VTF vibe.

-- Softness band controls. Exposed as convars so you can tune live.
local cvEdgeUV    = CreateClientConVar("csm_edge_uv",    "0.10", true, false,
	"Fraction of each cascade mask's UV used for the soft-edge band")
local cvEdgeRings = CreateClientConVar("csm_edge_rings", "64",  true, false,
	"Number of discrete rings used to render the soft edge")
local cvRollStep  = CreateClientConVar("csm_roll_step", "360", true, false,
	"Quantize lamp roll alignment to this many degrees (0 = continuous w/ shimmer, 360 = disabled)")
local cvShiftFwd  = CreateClientConVar("csm_shift_forward", "1", true, false,
	"Shift symmetric square cascade boxes along camera-forward so slack is in front, not behind the player (0-1)")
local cvFarFovScale = CreateClientConVar("csm_far_fov_scale", "1.0", true, false,
	"Scale the effective FOV for the outermost cascade (0.3-1.0). Smaller = tighter far cascade, more distance, less peripheral far-shadow coverage.")
local cvAsymOrtho = CreateClientConVar("csm_asymmetric_ortho", "0", true, false,
	"Use asymmetric ortho (hx != hy) for cascade boxes. Tighter fit but shadow texels are anisotropic.")

local function getEdgeRings() return math.Clamp(cvEdgeRings:GetInt(), 1, 256) end
local function getEdgeUV()    return math.Clamp(cvEdgeUV:GetFloat(), 0.0, 0.499) end

local function rectUVtoPx(u0, v0, u1, v1)
	return u0 * MASK_SIZE, (1 - v1) * MASK_SIZE,
	       (u1 - u0) * MASK_SIZE, (v1 - v0) * MASK_SIZE
end

-- Mask RTs are drawn as white with soft ALPHA edges. The PT engine samples
-- the mask texture and the alpha falloff feathers the shadow boundary.
-- Inner cascades carve into outer cascades by drawing the inner's RT on
-- top with black tint and alpha blend — inner's alpha determines carve
-- intensity and the carve inherits the same softness automatically.

-- Cached RT for the procedurally-generated soft mask template.
-- Generated ONCE (or when convars change) using smoothstep math.
local _softRT    = nil
local _softMat   = nil
local _softRTKey = ""

local function getSoftRT()
	if not _softRT then
		_softRT = GetRenderTargetEx(
			"csm_soft_template",
			MASK_SIZE, MASK_SIZE,
			RT_SIZE_LITERAL,
			MATERIAL_RT_DEPTH_NONE,
			0, 0,
			IMAGE_FORMAT_RGBA8888
		)
	end
	return _softRT
end

local function getSoftMat()
	if not _softMat then
		_softMat = CreateMaterial("csm_soft_template_mat", "UnlitGeneric", {
			["$basetexture"] = "csm_soft_template",
			["$translucent"] = 1,
			["$vertexalpha"] = 1,
			["$vertexcolor"] = 1,
		})
	end
	_softMat:SetTexture("$basetexture", getSoftRT())
	return _softMat
end

local function rebuildSoftRT()
	local uv = getEdgeUV()
	local N  = math.max(getEdgeRings(), 2)
	local key = uv .. "|" .. N
	if key == _softRTKey then return end
	_softRTKey = key

	local rt = getSoftRT()
	render.PushRenderTarget(rt)
	render.Clear(255, 255, 255, 0, false, false)
	cam.Start2D()
		-- Draw N outline rings (4-sided border) from outside-in, each at the
		-- exact smoothstep alpha for its position. Each pixel is covered by
		-- exactly ONE ring → final alpha = smoothstep(t). No drift, no leakage.
		for k = 0, N do
			local t    = 1 - k / N
			local s    = t * t * (3 - 2 * t)        -- smoothstep
			local a    = math.floor(s * 255 + 0.5)
			local outer_inset = (N - k) * (uv / N)  -- inset at this ring
			local inner_inset = (N - k + 1) * (uv / N)  -- inset at next ring
			-- Draw only the OUTLINE BAND for this ring (4 rects forming a border).
			-- Each pixel is covered by exactly ONE ring → its alpha IS smoothstep(t).
			-- No cumulative drift, no leakage.
			local x0, y0, x1, y1 = 
				math.floor(outer_inset * MASK_SIZE + 0.5),
				math.floor(outer_inset * MASK_SIZE + 0.5),
				math.floor((1 - outer_inset) * MASK_SIZE + 0.5),
				math.floor((1 - outer_inset) * MASK_SIZE + 0.5)
			local ix0, iy0, ix1, iy1 =
				math.floor(inner_inset * MASK_SIZE + 0.5),
				math.floor(inner_inset * MASK_SIZE + 0.5),
				math.floor((1 - inner_inset) * MASK_SIZE + 0.5),
				math.floor((1 - inner_inset) * MASK_SIZE + 0.5)
			surface.SetDrawColor(255, 255, 255, a)
			-- Top strip
			if iy0 > y0 and x1 > x0 then surface.DrawRect(x0, y0, x1-x0, iy0-y0) end
			-- Bottom strip
			if y1 > iy1 and x1 > x0 then surface.DrawRect(x0, iy1, x1-x0, y1-iy1) end
			-- Left strip (between top and bottom strips)
			if ix0 > x0 and iy1 > iy0 then surface.DrawRect(x0, iy0, ix0-x0, iy1-iy0) end
			-- Right strip
			if x1 > ix1 and iy1 > iy0 then surface.DrawRect(ix1, iy0, x1-ix1, iy1-iy0) end
		end
		-- Solid white fill for the interior (inside inset=uv).
		local cx = math.floor(uv * MASK_SIZE + 0.5)
		local cy = cx
		local cw = MASK_SIZE - cx * 2
		local ch = cw
		if cw > 0 and ch > 0 then
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawRect(cx, cy, cw, ch)
		end
	cam.End2D()
	render.PopRenderTarget()
end

cvars.AddChangeCallback("csm_edge_uv",    function() _softRTKey = "" end, "csm_soft_rt")
cvars.AddChangeCallback("csm_edge_rings", function() _softRTKey = "" end, "csm_soft_rt")

local function paintSoftBorderedWhite()
	rebuildSoftRT()
	surface.SetMaterial(getSoftMat())
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRect(0, 0, MASK_SIZE, MASK_SIZE)
end


-- Material cache for drawing an inner cascade's mask RT into an outer
-- cascade's mask. Standard alpha blend: we draw inner's RT at innerUV
-- with color=BLACK so where inner's mask is opaque we paint black on
-- outer (carve), where inner's mask is transparent outer is unchanged.
local subtractMats = {}
local function getSubtractMatForRT(rt)
	local name = rt:GetName()
	local m = subtractMats[name]
	if not m then
		m = CreateMaterial("csm_carve_" .. name, "UnlitGeneric", {
			["$basetexture"] = name,
			["$translucent"] = 1,
			["$vertexalpha"] = 1,
			["$vertexcolor"] = 1,
			["$color"]       = "[0 0 0]",
		})
		subtractMats[name] = m
	end
	return m
end

local function paintMask(rt, innerRT, innerUV, isOutermost)
	render.PushRenderTarget(rt)
	-- Transparent-black clear: we'll paint white where the mask should be
	-- opaque. Alpha = coverage for the projected texture's soft falloff.
	render.Clear(0, 0, 0, 0, false, false)
	cam.Start2D()
		if isOutermost then
			-- Outermost cascade: no outer fade (nothing to blend into past the
			-- edge). Paint solid white edge-to-edge so distant geometry still
			-- gets full shadow coverage instead of fading out into ambient.
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawRect(0, 0, MASK_SIZE, MASK_SIZE)
		else
			paintSoftBorderedWhite()
		end

		if innerRT and innerUV then
			-- Draw inner's mask TEXTURE with black tint and normal alpha blend.
			-- The mask's alpha channel (from paintSoftBorderedWhite: white
			-- opaque center, fading transparent at borders) IS our carve
			-- shape. Black tint + standard alpha blend = paint black where
			-- inner's mask is opaque, partial black in the fade band.
			local mat = getSubtractMatForRT(innerRT)
			local x, y, w, h = rectUVtoPx(innerUV[1], innerUV[2], innerUV[3], innerUV[4])
			surface.SetMaterial(mat)
			surface.SetDrawColor(0, 0, 0, 255)
			surface.DrawTexturedRect(x, y, w, h)
		end
	cam.End2D()
	render.PopRenderTarget()
end

-- ── HUD viz: top-down minimap of cascade coverage in view-space ──────────────
-- Draws each cascade's AABB projected onto the ground, then reprojected into
-- view-space (right/forward of the camera), normalized into a square panel
-- in the top-right corner. Matches user's mockup: nested rects centered on
-- the player marker, outer = far cascade, inner = near cascade.

FM._lastCascades = nil

local CASCADE_COLORS = {
	Color(230, 50,  50,  200),
	Color(60,  190, 90,  200),
	Color(70,  100, 220, 200),
	Color(230, 200, 60,  200),
}

local HUD_SIZE   = 256
local HUD_MARGIN = 16

function FM.DrawHUDViz()
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

	local cascades = FM._lastCascades
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
	local camRight = cascades.camRight
	local camFwd   = cascades.camFwd

	-- Simple approach: draw cascade AABBs directly in sun-space (sunRight=X,
	-- sunUp=Y), centered on the camera's sun-space position. This is a
	-- TOP-DOWN sun-space minimap. For overhead sun it's basically a world XY
	-- minimap, which is what the user wants to see.
	--
	-- We rotate the whole thing so the CAMERA FORWARD direction points UP.
	-- Camera forward projected into (sunRight, sunUp) = (camFwd:Dot(sunRight), camFwd:Dot(sunUp)).
	-- This vector is our 'up' on the minimap; we rotate so it aligns with +Y.

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
	-- Rotation matrix: we want (fx, fy) → (0, 1). That's the rotation by
	-- angle whose cos=fy, sin=-fx. Apply to each point:
	--   x' = fy*x - (-fx)*y = fy*x + fx*y
	--   y' = (-fx)*x + fy*y = -fx*x + fy*y  → but we want +Y up in screen
	--   minus Y because screen Y is down; flip at end.

	local maxExt = 1
	-- Scale based on the OUTERMOST cascade's half-extent (its ortho range).
	-- The auto-fit based on corners was dominated by odd projection artifacts.
	if cascades[#cascades] and cascades[#cascades].half then
		maxExt = cascades[#cascades].half * 1.2
	end
	local rects = {}
	for i, c in ipairs(cascades) do
		-- Draw the actual ortho box — square when symmetric, rect when asymmetric.
		local asym = cvAsymOrtho:GetBool()
		local hx = asym and (c.hx or c.half) or (c.half or math.max(c.maxX - c.minX, c.maxY - c.minY) * 0.5)
		local hy = asym and (c.hy or c.half) or (c.half or math.max(c.maxX - c.minX, c.maxY - c.minY) * 0.5)
		local bxMin = c.cx - hx
		local bxMax = c.cx + hx
		local byMin = c.cy - hy
		local byMax = c.cy + hy
		local corners = {
			-- Wound CCW so that after the Y-flip (screen Y points down) the
			-- surface.DrawPoly winding is correct.
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

	if GetConVar("csm_frustum_debug"):GetBool() then
		print(string.format("[HUD] n=%d maxExt=%.1f scale=%.4f fx=%.2f fy=%.2f camCx=%.1f camCy=%.1f",
			#cascades, maxExt, scale, fx, fy, camCx, camCy))
		for i, c in ipairs(cascades) do
			print(string.format("  c%d cx=%.1f cy=%.1f half=%.1f",
				i, c.cx, c.cy, c.half or -1))
		end
	end

	-- Draw outer-first
	for i = #cascades, 1, -1 do
		local col = CASCADE_COLORS[i] or color_white
		local r = rects[i]
		local pts = {}
		for k = 1, 4 do
			pts[k] = {
				x = hcx + r[k][1] * scale,
				-- Flip Y so +forward = up on screen.
				y = hcy - r[k][2] * scale,
				u = 0, v = 0,
			}
		end
		draw.NoTexture()
		surface.SetDrawColor(col)
		surface.DrawPoly(pts)
		-- Outline for visibility
		surface.SetDrawColor(col.r, col.g, col.b, 255)
		for k = 1, 4 do
			local a = pts[k]
			local b = pts[(k % 4) + 1]
			surface.DrawLine(a.x, a.y, b.x, b.y)
		end
	end

	-- Player marker at center (triangle pointing UP = camera forward)
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

hook.Add("HUDPaint", "RealCSMFrustumViz", FM.DrawHUDViz)

-- ── Main: compute per-cascade placement + masks ─────────────────────────────

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

	-- Roll the light-space basis so sunRight aligns with camera forward
	-- projected onto the sun-perpendicular plane. This keeps the ortho box's
	-- long axis pointing where the frustum extends, making the axis-aligned
	-- bounding box much tighter than if we used an arbitrary sunAngle roll.
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
			-- Compute roll: signed angle from sunAngle:Right() to nRight around sunFwd.
			local cosR = sunRight:Dot(nRight)
			local sinR = sunUp:Dot(nRight)
			local roll = math.deg(math.atan2(sinR, cosR))
			-- Quantize roll to discrete steps so texel grid only jumps occasionally
			-- rather than rotating continuously with camera yaw. Trades a bit of
			-- coverage for stability — no shimmer except at the boundary crossings.
			local step = GetConVar("csm_roll_step") and GetConVar("csm_roll_step"):GetFloat() or 30
			if step > 0 then
				roll = math.floor(roll / step + 0.5) * step
			end
			sunAngle   = Angle(sunAngle.p, sunAngle.y, sunAngle.r + roll)
			sunFwd     = sunAngle:Forward()
			sunRight   = sunAngle:Right()
			sunUp      = sunAngle:Up()
		end
	end

	-- Used to bail here when camera looked along sun direction; turns out
	-- that's not actually degenerate (sun-perp plane is well-defined), and
	-- bailing left PTs holding stale frustum-mask RTs from earlier frames.
	-- Just proceed — projectAABB_abs handles any camera angle.

	-- Compute each cascade's absolute light-space AABB.
	-- Use PSSM slabs (cascade i covers view distances split[i-1] → split[i])
	-- rather than cumulative frustums [nearZ, split[i]]. Then union with the
	-- previous cascade's AABB so inner ⊂ outer (required for carve math).
	-- Net effect: outer cascades are tighter than naive cumulative because
	-- distant slabs don't include the wide near-camera region.
	local perCascade = {}
	for i, casc in ipairs(cascades) do
		if not IsValid(casc.pt) then break end
		local farZ  = splitDistances[i]
		if not farZ then break end
		local slabNear = (i == 1) and nearZ or splitDistances[i-1]

		-- Outermost cascade can optionally use a narrower effective FOV to
		-- trim peripheral far-shadow coverage in exchange for more forward
		-- distance packed into the same shadowmap resolution.
		local effFov, effAspect = fovV, aspect
		if i == #cascades then
			local scale = math.Clamp(cvFarFovScale:GetFloat(), 0.3, 1.0)
			effFov = fovV * scale
			-- keep aspect the same so we shrink symmetrically on both axes
		end

		local corners = getFrustumCorners(camPos, camAng, effFov, effAspect, slabNear, farZ)
		local minX, minY, maxX, maxY = projectAABB_abs(corners, sunRight, sunUp)

		-- Option B: do NOT union with the previous cascade's AABB.
		-- Let inner/mid cascades overhang naturally instead of forcing nesting
		-- via recentering/enlargement at the geometry stage.

		-- Lamp position: AABB center in light-space, lifted along -sunFwd.
		-- We can't just add sunRight*cx + sunUp*cy because that ignores the
		-- sunFwd component — the lamp needs to be at a world point whose
		-- (sunRight, sunUp) projection is exactly (cx, cy). Solve:
		--   lampWorld = cx*sunRight + cy*sunUp + k*sunFwd
		-- for any k (we use k = -sunHeight, putting lamp far "above" sun-wise).
		-- Lamp position: a world point whose (sunRight, sunUp) projection is
		-- exactly (cx, cy). Simplest: start at camPos, shift by the DELTA in
		-- light-space to reach (cx, cy), then push back along -sunFwd.
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
			-- Asymmetric half-extents
			hx = (maxX - minX) * 0.5,
			hy = (maxY - minY) * 0.5,
			-- Absolute light-space AABB (for cutout + HUD viz)
			minX = minX, minY = minY, maxX = maxX, maxY = maxY,
			cx = cx, cy = cy,
		}
	end

	-- Store for HUD viz
	perCascade.sunRight = sunRight
	perCascade.sunUp    = sunUp
	perCascade.sunFwd   = sunFwd
	perCascade.camPos   = camPos
	perCascade.camRight = camAng:Right()
	perCascade.camFwd   = camAng:Forward()
	FM._lastCascades    = perCascade

	-- Apply placement with ASYMMETRIC ortho:
	-- SetOrthographic(true, left, top, right, bottom) where:
	--   left/right  = distances along pt:GetRight()  (= sunAngle:Right())
	--   top/bottom  = distances along pt:GetUp()     (= sunAngle:Up())
	-- The lamp is at (cx, cy) in light-space, and the AABB extends from
	-- (minX, minY) to (maxX, maxY). So:
	--   left   = cx - minX   = hx
	--   right  = maxX - cx   = hx
	--   top    = maxY - cy   = hy     (UP direction)
	--   bottom = cy - minY   = hy
	-- These are all positive and symmetric since we placed at center. But
	-- the asymmetry we DO want is hx != hy — different sizes on each axis.
	-- Apply placement with SYMMETRIC ortho. Yes, we waste some shadowmap
	-- space on the non-dominant axis, but Source's shadow depth RT is square
	-- so using asymmetric ortho would stretch pixels badly. Use half = max
	-- of both axes. Stored hx/hy as-is for cutout math; use h (squared up)
	-- only for the actual SetOrthographic call.
	-- Pass 1: compute stable pow2 half for each cascade.
	for i, info in ipairs(perCascade) do
		local rawHalf = math.max(info.hx, info.hy)
		local h = 1
		while h < rawHalf do h = h * 2 end
		info.half = h
	end

	-- Pass 1.5: forward-bias each cascade by its own slack, with fade padding.
	-- No AABB union, no inner clamp chain: cascades are allowed to overhang.
	local shiftFrac = math.Clamp(cvShiftFwd:GetFloat(), 0, 1)
	if shiftFrac > 0 and #perCascade > 0 then
		local camFwd = camAng:Forward()
		local fwdX   = camFwd:Dot(sunRight)
		local fwdY   = camFwd:Dot(sunUp)
		local fmag   = math.sqrt(fwdX*fwdX + fwdY*fwdY)
		if fmag > 1e-4 then
			fwdX, fwdY = fwdX / fmag, fwdY / fmag
			local edgeUV = getEdgeUV()
			for _, info in ipairs(perCascade) do
				local backFade = 2 * edgeUV * info.half
				local shiftX = math.max(0, (info.half - info.hx) - backFade) * shiftFrac
				local shiftY = math.max(0, (info.half - info.hy) - backFade) * shiftFrac
				info.cx = info.cx + shiftX * fwdX
				info.cy = info.cy + shiftY * fwdY
			end
		end
	end

	-- Pass 2: snap positions to the COARSEST grid this cascade appears in.
	-- Cascade i appears in its OWN shadow-depth RT (texel = 2*half_i/depthRes)
	-- AND in the outer cascade's MASK RT (pixel = 2*half_{i+1}/MASK_SIZE).
	-- Snap to whichever is larger so alignment is pixel-perfect in both.
	local depthRes = GetConVar("r_flashlightdepthres") and GetConVar("r_flashlightdepthres"):GetInt() or 512
	for i, info in ipairs(perCascade) do
		local h = info.half
		local depthTexel = (2 * h) / depthRes
		local maskPixel = 0
		if perCascade[i + 1] then
			maskPixel = (2 * perCascade[i + 1].half) / MASK_SIZE
		end
		local grid = math.max(depthTexel, maskPixel)
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

	-- Debug print
	if GetConVar("csm_frustum_debug") and GetConVar("csm_frustum_debug"):GetBool() then
		for i, info in ipairs(perCascade) do
			local relLampX = info.ptPos:Dot(sunRight) - camPos:Dot(sunRight)
			local relLampY = info.ptPos:Dot(sunUp)    - camPos:Dot(sunUp)
			Msg(string.format(
				"[FM] c%d hx=%.1f hy=%.1f lampLS=(%.1f,%.1f) minX=%.1f maxX=%.1f minY=%.1f maxY=%.1f\n",
				i, info.hx, info.hy, relLampX, relLampY,
				info.minX - camPos:Dot(sunRight),
				info.maxX - camPos:Dot(sunRight),
				info.minY - camPos:Dot(sunUp),
				info.maxY - camPos:Dot(sunUp)
			))
		end
	end

	-- Paint masks: each cascade's mask carves out the inner cascade's region
	-- by inverse-stamping the inner cascade's actual mask (same softness).
	for i, info in ipairs(perCascade) do
		local rt = FM.GetRT(ent, i)
		if not rt then break end

		local innerRT = nil
		local innerUV = nil
		if i > 1 and perCascade[i - 1] then
			local prev = perCascade[i - 1]
			-- Stamp region = PREV cascade's full ortho box mapped into THIS
			-- cascade's UV. Softness matches automatically because we're
			-- sampling the prev cascade's mask texture itself.
			local asym = cvAsymOrtho:GetBool()
			local h_x  = asym and info.hx or info.half
			local h_y  = asym and info.hy or info.half
			local ph_x = asym and prev.hx or prev.half
			local ph_y = asym and prev.hy or prev.half
			local thisMinX = info.cx - h_x
			local thisMinY = info.cy - h_y
			local invW    = 1 / (2 * h_x)
			local invH    = 1 / (2 * h_y)
			local uMin = ((prev.cx - ph_x) - thisMinX) * invW
			local uMax = ((prev.cx + ph_x) - thisMinX) * invW
			local vMin = ((prev.cy - ph_y) - thisMinY) * invH
			local vMax = ((prev.cy + ph_y) - thisMinY) * invH

			-- Clamp to [0..1]
			if uMin < 0 then uMin = 0 end
			if uMax > 1 then uMax = 1 end
			if vMin < 0 then vMin = 0 end
			if vMax > 1 then vMax = 1 end

			if uMax > uMin and vMax > vMin then
				innerRT = FM.GetRT(ent, i - 1)
				innerUV = { uMin, vMin, uMax, vMax }
			end
		end

		local isOutermost = (i == #perCascade)
		paintMask(rt, innerRT, innerUV, isOutermost)
		info.pt:SetTexture(rt)
		-- Track active RTs by cascade index so SkyboxLamp can restore them
		-- after its pre/post skybox save-restore cycle.
		FM._activeRTs = FM._activeRTs or {}
		FM._activeRTs[i] = rt
	end

	return true
end

-- ── Cascade split helpers ────────────────────────────────────────────────────
-- PSSM split: blend log + linear distribution by lambda.
-- near/far = view-space distance range to cover with cascades.
-- n = number of cascades. Returns cumulative far distances per cascade.

function FM.ComputeSplits(near, far, n, lambda)
	lambda = lambda or 0.8  -- favor log (tight near cascade)
	local splits = {}
	for i = 1, n do
		local si = i / n
		local logSplit = near * (far / near) ^ si
		local linSplit = near + (far - near) * si
		splits[i] = lambda * logSplit + (1 - lambda) * linSplit
	end
	return splits
end
