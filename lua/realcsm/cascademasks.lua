-- lua/realcsm/cascademasks.lua
-- Soft cutout masks for nested projected-texture cascades.
--
-- Each outer cascade gets an RT mask whose alpha = projected-texture coverage:
--   - white (alpha=1) inside the cascade's box, with a soft alpha falloff at
--     the outer edge (controlled by csm_edge_uv / csm_edge_rings).
--   - carved black where the inner cascade's mask is opaque, so adjacent
--     cascades don't double up on the same pixel.
--
-- This module is INDEPENDENT of how cascades are positioned. Anything can
-- compute cx/cy/half for each cascade and call:
--   CascadeMasks.Refresh(ent, cascades)    -- paint + bind masks to PTs
--   CascadeMasks.SuggestGrid(cascades)     -- per-cascade snap grid for
--                                          -- pixel-perfect carve alignment
--
-- `cascades` is a list of tables shaped like:
--   { pt = ProjectedTexture, cx, cy, half [, hx, hy] }
-- Indexed inner→outer (cascade 1 = innermost, #cascades = outermost).

RealCSM = RealCSM or {}
local CM = {}
RealCSM.CascadeMasks = CM

local MASK_SIZE = 1024
CM.MASK_SIZE    = MASK_SIZE

-- ── Convars (mask painting only) ────────────────────────────────────────────

local cvEdgeUV    = CreateClientConVar("csm_edge_uv",    "0.10", true, false,
	"Fraction of each cascade mask's UV used for the soft-edge band")
local cvEdgeRings = CreateClientConVar("csm_edge_rings", "64",  true, false,
	"Number of discrete rings used to render the soft edge")

local function getEdgeRings() return math.Clamp(cvEdgeRings:GetInt(), 1, 256) end
local function getEdgeUV()    return math.Clamp(cvEdgeUV:GetFloat(), 0.0, 0.499) end
CM.GetEdgeUV = getEdgeUV
CM.GetEdgeRings = getEdgeRings

-- ── RT pool ─────────────────────────────────────────────────────────────────

function CM.GetRT(ent, i)
	ent._cmRTs = ent._cmRTs or {}
	if not ent._cmRTs[i] then
		local name = "csm_mask_rt_" .. ent:EntIndex() .. "_" .. i
		ent._cmRTs[i] = GetRenderTargetEx(
			name,
			MASK_SIZE, MASK_SIZE,
			RT_SIZE_LITERAL,
			MATERIAL_RT_DEPTH_NONE,
			0, 0,
			IMAGE_FORMAT_RGBA8888
		)
	end
	return ent._cmRTs[i]
end

-- ── Soft mask template (cached) ─────────────────────────────────────────────

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
			local s    = t * t * (3 - 2 * t)
			local a    = math.floor(s * 255 + 0.5)
			local outer_inset = (N - k) * (uv / N)
			local inner_inset = (N - k + 1) * (uv / N)
			local x0 = math.floor(outer_inset * MASK_SIZE + 0.5)
			local y0 = x0
			local x1 = math.floor((1 - outer_inset) * MASK_SIZE + 0.5)
			local y1 = x1
			local ix0 = math.floor(inner_inset * MASK_SIZE + 0.5)
			local iy0 = ix0
			local ix1 = math.floor((1 - inner_inset) * MASK_SIZE + 0.5)
			local iy1 = ix1
			surface.SetDrawColor(255, 255, 255, a)
			if iy0 > y0 and x1 > x0 then surface.DrawRect(x0, y0, x1-x0, iy0-y0) end
			if y1 > iy1 and x1 > x0 then surface.DrawRect(x0, iy1, x1-x0, y1-iy1) end
			if ix0 > x0 and iy1 > iy0 then surface.DrawRect(x0, iy0, ix0-x0, iy1-iy0) end
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

-- ── Subtract material cache ─────────────────────────────────────────────────

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

-- ── UV / paint helpers ──────────────────────────────────────────────────────

local function rectUVtoPx(u0, v0, u1, v1)
	return u0 * MASK_SIZE, (1 - v1) * MASK_SIZE,
	       (u1 - u0) * MASK_SIZE, (v1 - v0) * MASK_SIZE
end

local function paintMask(rt, innerRT, innerUV, isOutermost)
	render.PushRenderTarget(rt)
	render.Clear(0, 0, 0, 0, false, false)
	cam.Start2D()
		if isOutermost then
			-- Outermost cascade: no outer fade (nothing to blend into past
			-- the edge). Paint solid white so distant geometry still gets
			-- full shadow coverage.
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawRect(0, 0, MASK_SIZE, MASK_SIZE)
		else
			paintSoftBorderedWhite()
		end

		if innerRT and innerUV then
			-- Carve: draw inner's mask TEXTURE with black tint and standard
			-- alpha blend. The inner mask's alpha IS our carve shape, so the
			-- carve inherits the same softness automatically.
			local mat = getSubtractMatForRT(innerRT)
			local x, y, w, h = rectUVtoPx(innerUV[1], innerUV[2], innerUV[3], innerUV[4])
			surface.SetMaterial(mat)
			surface.SetDrawColor(0, 0, 0, 255)
			surface.DrawTexturedRect(x, y, w, h)
		end
	cam.End2D()
	render.PopRenderTarget()
end

-- ── Public: SuggestGrid ─────────────────────────────────────────────────────
-- Returns a single grid spacing (in light-space units) that ALL cascades
-- should snap their cx/cy to for pixel-perfect carve alignment in every
-- outer cascade's mask. The caller is expected to ALSO honor its own
-- shadow-depth texel grid (typically `2*half / r_flashlightdepthres`),
-- snapping to math.max(maskGrid, depthTexel).
--
-- Required field per cascade: `half` (pow2 symmetric half-extent).
function CM.SuggestGrid(cascades)
	local outermost = cascades[#cascades]
	if not outermost or not outermost.half then return 0 end
	-- Outermost mask covers [cx-half .. cx+half]; one pixel = 2*half/MASK_SIZE.
	-- All inner cascades' AABB edges land on this grid → exact pixel boundaries.
	return (2 * outermost.half) / MASK_SIZE
end

-- ── Public: Refresh ─────────────────────────────────────────────────────────
-- Repaint mask RTs for `cascades` and bind them to each cascade's PT via
-- pt:SetTexture. `cascades` indexed inner→outer; cascade table needs:
--   pt   - ProjectedTexture
--   cx   - lamp center in light-space X (= 0.5*(left+right) of ortho box)
--   cy   - lamp center in light-space Y (= 0.5*(top+bottom) of ortho box)
--   half - symmetric half-extent of the ortho box (UV space spans cx ± half)
-- Optional: hx, hy if asymmetric ortho is in use (but the mask UV uses `half`
-- since the PT samples the mask over its full ortho square).
--
-- Returns true on success and stores active RTs in CM._activeRTs[i] so
-- SkyboxLamp can restore them after its save/restore cycle.
function CM.Refresh(ent, cascades)
	if not IsValid(ent) then return false end
	for i, info in ipairs(cascades) do
		local rt = CM.GetRT(ent, i)
		if not rt then break end

		local innerRT, innerUV = nil, nil
		if i > 1 and cascades[i - 1] then
			local prev = cascades[i - 1]
			-- Map prev cascade's full ortho box into THIS cascade's UV space.
			-- This cascade's UV space spans [cx-half .. cx+half] (light-space).
			local h_x = info.half
			local h_y = info.half
			local ph_x = prev.half
			local ph_y = prev.half
			local thisMinX = info.cx - h_x
			local thisMinY = info.cy - h_y
			local invW = 1 / (2 * h_x)
			local invH = 1 / (2 * h_y)
			local uMin = ((prev.cx - ph_x) - thisMinX) * invW
			local uMax = ((prev.cx + ph_x) - thisMinX) * invW
			local vMin = ((prev.cy - ph_y) - thisMinY) * invH
			local vMax = ((prev.cy + ph_y) - thisMinY) * invH
			if uMin < 0 then uMin = 0 end
			if uMax > 1 then uMax = 1 end
			if vMin < 0 then vMin = 0 end
			if vMax > 1 then vMax = 1 end
			if uMax > uMin and vMax > vMin then
				innerRT = CM.GetRT(ent, i - 1)
				innerUV = { uMin, vMin, uMax, vMax }
			end
		end

		local isOutermost = (i == #cascades)
		paintMask(rt, innerRT, innerUV, isOutermost)
		if IsValid(info.pt) then
			info.pt:SetTexture(rt)
		end
		CM._activeRTs = CM._activeRTs or {}
		CM._activeRTs[i] = rt
	end
	return true
end

-- ── Public: ClearActive ────────────────────────────────────────────────────
-- Called by callers when they want to hand back texture ownership (e.g. when
-- the masking feature is being toggled off and original textures restored).
function CM.ClearActive()
	CM._activeRTs = {}
end
