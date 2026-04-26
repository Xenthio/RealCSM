-- lua/realcsm/sunocclude.lua
-- Sun occlusion via NikNaks BSP leaf flags.
--
-- Uses NikNaks to walk the BSP tree and find the player's current leaf,
-- then reads the leaf's precompiled LEAF_FLAGS_SKY bit (set by vvis).
-- If the bit is clear, no sky is visible from this leaf → park lamps.
--
-- O(log N) per frame (BSP tree depth), zero raycasts, zero baking.
--
-- REQUIRES: NikNaks addon (workshop: 1835812634).
-- Without NikNaks, a warning is shown (only when csm_sunocclude is on)
-- and no culling occurs.

RealCSM = RealCSM or {}
local M = {}
RealCSM.SunOcclude = M

-- ── State ─────────────────────────────────────────────────────────────────────
local _nodes        = nil   -- cached BSP nodes array
local _leafs        = nil   -- cached BSP leafs array
local _ready        = false
local _noNikNaks    = false

local _lastLeaf     = nil   -- last BSP leaf we were in (cached)
local _occluded     = false
local _lastCanSeeSky = true
local _savedOrthos  = {}

-- Hysteresis: require this many consecutive "occluded" frames before parking.
-- Eliminates single-frame flickers when crossing leaf boundaries mid-jump.
local HYSTERESIS    = 3
local _occCounter   = 0   -- frames in current occluded state
local _visCounter   = 0   -- frames in current visible state

-- ── BSP tree walk: point → leaf ───────────────────────────────────────────────
-- Standard Source BSP traversal. Children are node indices (≥0) or
-- -(leafIndex+1) for leaf nodes.
local _dot = function(a, b) return a:Dot(b) end

local function pointInLeaf(pos)
	local nodes = _nodes
	local leafs  = _leafs
	local nodeIdx = 0

	while nodeIdx >= 0 do
		local node  = nodes[nodeIdx]
		local plane = node.plane
		local dist
		local t = plane.type
		if     t == 0 then dist = pos.x - plane.dist
		elseif t == 1 then dist = pos.y - plane.dist
		elseif t == 2 then dist = pos.z - plane.dist
		else               dist = _dot(pos, plane.normal) - plane.dist
		end
		nodeIdx = dist >= 0 and node.children[1] or node.children[2]
	end

	return leafs[-nodeIdx - 1]
end

-- ── Initialisation ────────────────────────────────────────────────────────────
local function tryInit()
	if _ready or _noNikNaks then return end

	if not NikNaks then
		if file.Exists("includes/modules/niknaks.lua", "LUA") then
			require("niknaks")
		end
	end
	if not NikNaks then
		_noNikNaks = true
		return
	end

	local bsp = NikNaks.CurrentMap
	if not bsp then return end  -- not ready yet, retry next tick

	-- Pre-fetch and cache node/leaf tables (NikNaks caches them internally too).
	_nodes = bsp:GetNodes()
	_leafs = bsp:GetLeafs()

	if not _nodes or not _leafs then return end

	-- Kick off the direction-independent SkyVis bake (PVS-of-PVS sky reachability).
	if RealCSM.SkyVis  then RealCSM.SkyVis.Init(bsp)  end
	if RealCSM.SunBake then RealCSM.SunBake.Init(bsp) end

	_ready = true
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.GetEyeLeaf()
	tryInit()
	if not _ready then return nil end
	local viewEnt = GetViewEntity and GetViewEntity() or LocalPlayer()
	local eyePos
	if IsValid(viewEnt) and viewEnt.EyePos then
		eyePos = viewEnt:EyePos()
	else
		eyePos = EyePos()
	end
	if not eyePos then return nil end
	return pointInLeaf(eyePos)
end

-- Mode 2: PVS-filtered sunlit candidates + view-frustum AABB test.
-- No per-frame raycasts — just bake-driven PVS ∩ _isSunlit, and a quick
-- AABB-vs-frustum test against the padded camera frustum. Cheap.
local _mode2_lastLeafIdx = nil
local _mode2_candidates  = nil

-- Build six frustum planes from view origin/angles/fov.
-- Plane format: { normal, dist } with point-inside test n·p ≥ dist.
local function buildFrustum(eyePos, eyeAng, fovDeg, aspect, nearD, farD)
	local fwd   = eyeAng:Forward()
	local right = eyeAng:Right()
	local up    = eyeAng:Up()

	local fovRad = math.rad(fovDeg)
	local tanH = math.tan(fovRad * 0.5)
	local tanV = tanH / aspect

	local planes = {}
	planes[1] = { fwd, fwd:Dot(eyePos + fwd * nearD) }
	local nF = -fwd
	planes[2] = { nF, nF:Dot(eyePos + fwd * farD) }

	local eR = (fwd + right * tanH); eR:Normalize()
	local eL = (fwd - right * tanH); eL:Normalize()
	local eT = (fwd + up    * tanV); eT:Normalize()
	local eB = (fwd - up    * tanV); eB:Normalize()

	local pR = up:Cross(eR);    pR:Normalize()
	local pL = eL:Cross(up);    pL:Normalize()
	local pT = eT:Cross(right); pT:Normalize()
	local pB = right:Cross(eB); pB:Normalize()

	planes[3] = { pR, pR:Dot(eyePos) }
	planes[4] = { pL, pL:Dot(eyePos) }
	planes[5] = { pT, pT:Dot(eyePos) }
	planes[6] = { pB, pB:Dot(eyePos) }
	return planes
end

local function aabbInFrustum(mins, maxs, planes)
	for i = 1, #planes do
		local n, d = planes[i][1], planes[i][2]
		local vx = (n.x >= 0) and maxs.x or mins.x
		local vy = (n.y >= 0) and maxs.y or mins.y
		local vz = (n.z >= 0) and maxs.z or mins.z
		if (n.x*vx + n.y*vy + n.z*vz) < d then
			return false
		end
	end
	return true
end

-- Cache for frustum candidate lists, keyed by (leaf idx, source kind, bake key).
local _frustum_lastLeafIdx = nil
local _frustum_lastKind    = nil
local _frustum_lastBakeKey = nil
local _frustum_candidates  = nil

-- Apply view-frustum cull to a candidate set of leafs.
-- isInteresting(leaf, idx) decides which leafs in PVS qualify (sunlit, has-sky, etc).
-- Returns true if any qualifying leaf's AABB intersects the padded camera frustum.
local function frustumCullCheck(playerLeaf, eyePos, kind, isInteresting)
	local idx = playerLeaf and playerLeaf.__id or nil
	if not idx then return true end

	local bakeKey = (RealCSM.SunBake and RealCSM.SunBake.GetCacheKey)
		and RealCSM.SunBake.GetCacheKey() or nil

	-- (Re)build candidate list when leaf, kind, or bake key changes.
	if idx ~= _frustum_lastLeafIdx
		or kind ~= _frustum_lastKind
		or bakeKey ~= _frustum_lastBakeKey then
		_frustum_lastLeafIdx = idx
		_frustum_lastKind    = kind
		_frustum_lastBakeKey = bakeKey
		_frustum_candidates  = {}
		local pvs = playerLeaf:CreatePVS()
		if pvs and _leafs then
			for i = 1, #_leafs do
				local lf = _leafs[i]
				if lf and lf.cluster and lf.cluster >= 0
					and pvs[lf.cluster]
					and isInteresting(lf, i) then
					_frustum_candidates[#_frustum_candidates + 1] = lf
				end
			end
		end
	end

	if #_frustum_candidates == 0 then return false end

	-- Build padded frustum from current view.
	local viewEnt = GetViewEntity and GetViewEntity() or LocalPlayer()
	local eyeAng  = (IsValid(viewEnt) and viewEnt.EyeAngles) and viewEnt:EyeAngles() or EyeAngles()
	local fov     = (IsValid(LocalPlayer()) and LocalPlayer():GetFOV()) or 75
	local sw, sh  = ScrW(), ScrH()
	local aspect  = (sh > 0) and (sw / sh) or (16/9)
	local paddedFov = math.min(170, fov * 1.30)
	local planes  = buildFrustum(eyePos, eyeAng, paddedFov, aspect, 1, 65536)

	for i = 1, #_frustum_candidates do
		local lf = _frustum_candidates[i]
		if lf and lf.mins and lf.maxs and aabbInFrustum(lf.mins, lf.maxs, planes) then
			return true
		end
	end
	return false
end

-- Frustum check using SunBake _isSunlit set (mode 1 + frustum).
local function isSunlitPredicate(lf, i)
	return RealCSM.SunBake and RealCSM.SunBake.IsLeafSunlit(i)
end

-- Frustum check using sky-in-PVS (mode 0 + frustum). Direction-independent.
local function hasSkyboxPredicate(lf, _i)
	return lf.HasSkyboxInPVS and lf:HasSkyboxInPVS()
end

function M.SeesSunFrustum_Mode1(leaf, eyePos, sunAngle)
	if not RealCSM.SunBake then return true end
	-- Always call EnsureBake — it cheap-returns if cache key matches, else
	-- triggers a rebake when the sun angle has changed by >10°.
	RealCSM.SunBake.EnsureBake(sunAngle, 1)
	if not RealCSM.SunBake.IsReady() then
		return true   -- safe default while baking
	end
	local idx = leaf and leaf.__id
	if idx and RealCSM.SunBake.IsLeafSunlit(idx) then return true end
	return frustumCullCheck(leaf, eyePos, "sunlit", isSunlitPredicate)
end

function M.SeesSunFrustum_Mode0(leaf, eyePos)
	if leaf and leaf.HasSkyboxInPVS and leaf:HasSkyboxInPVS() then return true end
	return frustumCullCheck(leaf, eyePos, "sky", hasSkyboxPredicate)
end

-- Back-compat alias for old callers.
function M.EyeSeesSunFrustum(leaf, eyePos, sunAngle)
	return M.SeesSunFrustum_Mode1(leaf, eyePos, sunAngle)
end

function M.Think(_ignoredViewPos, sunAngle, lampTable)
	-- Always sample the real eye/camera position, not the entity origin (feet).
	local viewEnt = GetViewEntity and GetViewEntity() or LocalPlayer()
	local eyePos
	if IsValid(viewEnt) and viewEnt.EyePos then
		eyePos = viewEnt:EyePos()
	else
		eyePos = EyePos()
	end
	if not eyePos then eyePos = _ignoredViewPos end
	if not GetConVar("csm_sunocclude"):GetBool() then
		if _occluded then M.Restore(lampTable); _occluded = false end
		if RealCSM.SkyboxLamp then RealCSM.SkyboxLamp.SetOccluded(false) end
		_occCounter = 0; _visCounter = 0
		return false
	end

	tryInit()

	if not _ready then
		-- Not ready: don't cull, restore if we were occluded.
		if _occluded then M.Restore(lampTable); _occluded = false end
		return false
	end

	-- BSP leaf lookup using the camera/eye position (NOT player feet).
	local leaf = pointInLeaf(eyePos)

	local mode    = GetConVar("csm_sunocclude_mode"):GetInt()
	local frustum = GetConVar("csm_sunocclude_frustum"):GetBool()
	local canSeeSky
	if leaf == nil then
		canSeeSky = true   -- outside map / lookup failed → safe default
	elseif mode == 1 and RealCSM.SunBake then
		if frustum then
			canSeeSky = M.SeesSunFrustum_Mode1(leaf, eyePos, sunAngle)
		else
			canSeeSky = RealCSM.SunBake.LeafSeesSun(leaf, sunAngle, 1)
		end
	else
		-- Mode 0: direction-independent "can any leaf in my PVS see the skybox?"
		if frustum then
			canSeeSky = M.SeesSunFrustum_Mode0(leaf, eyePos)
		else
			canSeeSky = RealCSM.SkyVis and RealCSM.SkyVis.LeafSeesSky(leaf) or leaf:HasSkyboxInPVS()
		end
	end
	_lastCanSeeSky = canSeeSky
	local wantOcclude = not canSeeSky

	-- Hysteresis: only switch state after N consecutive frames in new state.
	-- Prevents single-frame flickers when crossing leaf boundaries.
	if wantOcclude then
		_occCounter = _occCounter + 1
		_visCounter = 0
	else
		_visCounter = _visCounter + 1
		_occCounter = 0
	end

	local shouldOcclude
	if _occluded then
		-- Currently parked: un-park after HYSTERESIS visible frames.
		shouldOcclude = _visCounter < HYSTERESIS
	else
		-- Currently visible: park after HYSTERESIS occluded frames.
		shouldOcclude = _occCounter >= HYSTERESIS
	end

	_lastLeaf = leaf

	if shouldOcclude then
		if not _occluded then
			-- Transition: visible → occluded. Park lamps.
			for i, pt in pairs(lampTable) do
				if IsValid(pt) then
					if not _savedOrthos[i] then
						local _, l, r, t, b = pt:GetOrthographic()
						_savedOrthos[i] = (l + r + t + b) / 4
					end
					pt:SetOrthographic(true, 0.001, 0.001, 0.001, 0.001)
					pt:Update()
				end
			end
			if RealCSM.SkyboxLamp then RealCSM.SkyboxLamp.SetOccluded(true) end
			_occluded = true
		end
		return true
	else
		if _occluded then
			-- Transition: occluded → visible. Restore lamps.
			M.Restore(lampTable)
			if RealCSM.SkyboxLamp then RealCSM.SkyboxLamp.SetOccluded(false) end
			_occluded = false
		end
		return false
	end
end

function M.Restore(lampTable)
	if not lampTable then return end
	for i, pt in pairs(lampTable) do
		if IsValid(pt) and _savedOrthos[i] then
			local s = _savedOrthos[i]
			pt:SetOrthographic(true, s, s, s, s)
			pt:Update()
			_savedOrthos[i] = nil
		end
	end
end

function M.Reset()
	_ready       = false
	_noSkybox    = false
	_nodes       = nil
	_leafs       = nil
	_lastLeaf    = nil
	_occluded    = false
	_savedOrthos = {}
	_occCounter  = 0
	_visCounter  = 0
	if RealCSM.SkyboxLamp then RealCSM.SkyboxLamp.SetOccluded(false) end
	-- Don't reset _noNikNaks.
end

-- ── Public query API for external addons ─────────────────────────────────────
-- RealCSM.SunOcclude.IsOccluded()   → true if lamps are currently parked
-- RealCSM.SunOcclude.IsReady()      → true if the backing bake/vis is usable
-- RealCSM.SunOcclude.GetMode()      → 0 = PVS-only, 1 = directional bake
-- On RealCSM global: RealCSM.IsPlayerOutdoors() convenience wrapper.

function M.IsOccluded() return _occluded end
function M.IsReady()    return _ready end
function M.GetMode()    return GetConVar("csm_sunocclude_mode") and GetConVar("csm_sunocclude_mode"):GetInt() or 0 end

-- Convenience: true when the player is considered outdoors (sun visible).
-- Returns nil when occlusion culling is disabled (no opinion either way).
function RealCSM.IsPlayerOutdoors()
	if not (GetConVar("csm_sunocclude") and GetConVar("csm_sunocclude"):GetBool()) then
		return nil  -- culling off, unknown
	end
	return not _occluded
end

-- ── HUD ───────────────────────────────────────────────────────────────────────
local _warnTimer = 0

hook.Add("HUDPaint", "SunOcclude_HUD", function()
	local enabled = GetConVar("csm_sunocclude") and GetConVar("csm_sunocclude"):GetBool()
	local dbgOn   = GetConVar("csm_occlude_debug") and GetConVar("csm_occlude_debug"):GetBool()

	-- Only show the NikNaks warning when the feature is actually enabled.
	if enabled and _noNikNaks then
		_warnTimer = _warnTimer + FrameTime()
		if _warnTimer < 10 then
			local SW, SH = ScrW(), ScrH()
			local boxW, boxH = 480, 64
			local bx = (SW - boxW) / 2
			local by = SH * 0.35
			draw.RoundedBox(6, bx - 2, by - 2, boxW + 4, boxH + 4, Color(180, 0, 0, 200))
			draw.RoundedBox(6, bx, by, boxW, boxH, Color(30, 0, 0, 230))
			draw.SimpleText("RealCSM: csm_sunocclude requires NikNaks",
				"DermaDefaultBold", SW / 2, by + 16,
				Color(255, 80, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText("Install NikNaks from the Steam Workshop (ID: 1835812634)",
				"DermaDefault", SW / 2, by + 40,
				Color(220, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	if not dbgOn then return end

	local leaf      = _lastLeaf
	local hasSkyDir = leaf and leaf:HasSkyboxInPVS()
	local hasSkyPVS = leaf and RealCSM.SkyVis and RealCSM.SkyVis.LeafSeesSky(leaf)

	local y = 200
	local function ln(txt, col)
		draw.SimpleText(txt, "DermaDefault", 10, y, col or color_white, TEXT_ALIGN_LEFT)
		y = y + 16
	end

	if not _ready then
		ln("[SunOcclude] " .. (
			_noNikNaks and "NO NIKNAKS" or
			"Initialising…"), Color(255, 120, 0))
	else
		ln("[SunOcclude] BSP PVS ready", Color(0, 255, 0))
	end
	ln(string.format("  Leaf: %s  skyDirect: %s  skyPVS: %s",
		leaf and tostring(leaf:GetIndex()) or "nil",
		tostring(hasSkyDir),
		tostring(hasSkyPVS)),
		hasSkyPVS and color_white or Color(160, 160, 160))

	if RealCSM.SkyVis then
		local p = RealCSM.SkyVis.Progress()
		ln(string.format("  SkyVis bake: %s (%.0f%%)",
			RealCSM.SkyVis.IsReady() and "READY" or "baking", p * 100),
			RealCSM.SkyVis.IsReady() and Color(0, 255, 0) or Color(255, 200, 0))
	end

	if RealCSM.SunBake then
		local p   = RealCSM.SunBake.Progress()
		local isS = RealCSM.SunBake.GetLeafIsSunlit(leaf)
		local seS = RealCSM.SunBake.GetLeafSeesSunlit(leaf)
		local key = RealCSM.SunBake.GetCacheKey()
		local phase = RealCSM.SunBake.GetPhase()
		ln(string.format("  SunBake: %s phase=%d (%.0f%%)  key=%s",
			RealCSM.SunBake.IsReady() and "READY" or (RealCSM.SunBake.IsBuilding() and "baking" or "idle"),
			phase, p * 100, tostring(key)),
			RealCSM.SunBake.IsReady() and Color(0, 255, 0) or Color(255, 200, 0))
		ln(string.format("  leaf isSunlit:    %s", tostring(isS)),
			isS == true and Color(255, 230, 100)
			or isS == false and Color(120, 120, 200)
			or Color(160, 160, 160))
		ln(string.format("  leaf seesSunlit:  %s", tostring(seS)),
			seS == true and Color(255, 200, 100)
			or seS == false and Color(120, 120, 200)
			or Color(160, 160, 160))
	end

	local mode = GetConVar("csm_sunocclude_mode"):GetInt()
	local frustum = GetConVar("csm_sunocclude_frustum"):GetBool()
	ln(string.format("  Mode: %d (%s)%s  decision: canSeeSky=%s",
		mode,
		mode == 1 and "directional" or "omni",
		frustum and " +frustum" or "",
		tostring(_lastCanSeeSky)),
		_lastCanSeeSky and color_white or Color(160, 160, 160))

	ln(string.format("  Occluded: %s  occF:%d visF:%d",
		tostring(_occluded), _occCounter, _visCounter),
		_occluded and Color(160, 160, 160) or color_white)
end)
