-- lua/realcsm/sunbake.lua
-- Direction-DEPENDENT two-pass bake.
--
-- Pass 1 — _isSunlit[L]:
--   For each leaf L, sample positions inside its AABB, trace toward the sun.
--   If any sample reaches sky → leaf is sunlit.
--
-- Pass 2 — _seesSunlit[L]:
--   For each leaf L, sample a position, cast view rays in a Fibonacci sphere.
--   For each ray that hits a surface, find the leaf containing the surface
--   (point just in front of the surface in air), and check pass-1's _isSunlit.
--   If any such hit-leaf is sunlit → leaf L "sees" sunlit geometry.
--
-- Player's current leaf gets queried via _seesSunlit. If false → cull lamps.
-- This bypasses PVS entirely (PVS is too leaky for our purpose).

RealCSM = RealCSM or {}
local M = {}
RealCSM.SunBake = M

local ANGLE_BUCKET     = 10
local PASS1_SAMPLES    = 4     -- sun-ray samples per leaf for "is sunlit"
local PASS2_RAYS       = 32    -- view-ray directions for "sees sunlit"
local SUN_RAY_LEN      = 32768
local VIEW_RAY_LEN     = 16384
local CHUNK_PASS1      = 64
local CHUNK_PASS2      = 8     -- leafs per frame in pass 2 (does PVS + raycasts)
local CONFIRM_SAMPLES  = 16     -- raycast pairs per (myLeaf, candidateLeaf) for visibility confirm

-- Fibonacci sphere directions (computed once).
local _sphereDirs = nil
local function buildSphereDirs()
	if _sphereDirs then return end
	_sphereDirs = {}
	local n = PASS2_RAYS
	local golden = math.pi * (3 - math.sqrt(5))
	for i = 0, n - 1 do
		local y = 1 - (i / (n - 1)) * 2
		local r = math.sqrt(1 - y * y)
		local theta = golden * i
		_sphereDirs[i + 1] = Vector(math.cos(theta) * r, math.sin(theta) * r, y)
	end
end

-- ── State ────────────────────────────────────────────────────────────────────
local _bsp        = nil
local _leafs      = nil
local _nodes      = nil

local _phase      = 0     -- 0=idle, 1=pass1, 2=pass2, 3=done
local _building   = false
local _idx        = 1
local _total      = 0
local _ready      = false

local _cacheKey   = nil
local _bakeMode   = 1   -- 1=PVS only, 2=PVS+confirm. Set by EnsureBake.
local _sunDirCache = nil

local _isSunlit       = {}   -- working set, pass 1
local _seesSunlit     = {}   -- working set, pass 2
local _ready_isSunlit  = {}  -- last completed
local _ready_seesSunlit = {} -- last completed

-- ── BSP point-in-leaf walk ───────────────────────────────────────────────────
local function pointInLeaf(pos)
	if not _nodes or not _leafs then return nil end
	local nodeIdx = 0
	while nodeIdx >= 0 do
		local node  = _nodes[nodeIdx]
		if not node then return nil end
		local plane = node.plane
		local dist
		local t = plane.type
		if     t == 0 then dist = pos.x - plane.dist
		elseif t == 1 then dist = pos.y - plane.dist
		elseif t == 2 then dist = pos.z - plane.dist
		else               dist = pos:Dot(plane.normal) - plane.dist
		end
		nodeIdx = dist >= 0 and node.children[1] or node.children[2]
	end
	return _leafs[-nodeIdx - 1], -nodeIdx
end

local function leafIndexOf(leaf)
	-- NikNaks BSPLeafObject has __id (1-based after offset) per source we read;
	-- GetIndex() exists too. Fall back to __id.
	if not leaf then return nil end
	if leaf.GetIndex then return leaf:GetIndex() end
	return leaf.__id
end

-- ── Sampling helpers ─────────────────────────────────────────────────────────
local function sampleInLeaf(leaf, n)
	local mins, maxs = leaf.mins, leaf.maxs
	if not mins or not maxs then return nil end
	if n == 1 then return (mins + maxs) * 0.5 end
	return Vector(
		math.Rand(mins.x, maxs.x),
		math.Rand(mins.y, maxs.y),
		math.Rand(mins.z, maxs.z)
	)
end

-- Pass 1: any sun ray from inside L hits sky?
local function leafIsSunlit(leaf, sunDir)
	if not leaf or not leaf.cluster or leaf.cluster < 0 then return false end
	for s = 1, PASS1_SAMPLES do
		local p = sampleInLeaf(leaf, s)
		if p then
			local tr = util.TraceLine({
				start  = p,
				endpos = p - sunDir * SUN_RAY_LEN,
				mask   = MASK_OPAQUE,
			})
			if tr.HitSky then return true end
		end
	end
	return false
end

-- Generate sample positions inside leaf AABB. Returns table of vectors.
-- index 1 is centre; rest are corner-lerps then random jitter.
local function leafSamples(leaf, n)
	local mins, maxs = leaf.mins, leaf.maxs
	if not mins or not maxs then return nil end
	local samples = {}
	local centre = (mins + maxs) * 0.5
	samples[1] = centre
	if n <= 1 then return samples end
	local corners = {
		Vector(mins.x, mins.y, mins.z), Vector(maxs.x, mins.y, mins.z),
		Vector(mins.x, maxs.y, mins.z), Vector(maxs.x, maxs.y, mins.z),
		Vector(mins.x, mins.y, maxs.z), Vector(maxs.x, mins.y, maxs.z),
		Vector(mins.x, maxs.y, maxs.z), Vector(maxs.x, maxs.y, maxs.z),
	}
	for i = 1, math.min(n - 1, #corners) do
		samples[i + 1] = LerpVector(0.4, centre, corners[i])
	end
	-- Beyond 9 samples, use deterministic jitter inside the AABB.
	local extra = n - 1 - #corners
	if extra > 0 then
		for i = 1, extra do
			-- Halton-ish hash per index keeps results stable across rebakes.
			local h1 = ((i * 0.61803398875) % 1)
			local h2 = ((i * 0.41421356237) % 1)
			local h3 = ((i * 0.31622776601) % 1)
			samples[#samples + 1] = Vector(
				mins.x + (maxs.x - mins.x) * h1,
				mins.y + (maxs.y - mins.y) * h2,
				mins.z + (maxs.z - mins.z) * h3
			)
		end
	end
	return samples
end

-- Pass 2 (mode 1): plain PVS + _isSunlit. Fast, leaky on big PVS sets.
local function leafSeesSunlit_PVS(leaf)
	if not leaf or not leaf.cluster or leaf.cluster < 0 then return false end
	if _isSunlit[leafIndexOf(leaf)] then return true end
	local pvs = leaf:CreatePVS()
	if not pvs then return true end
	for i = 1, #_leafs do
		local lf = _leafs[i]
		if lf and lf.cluster and lf.cluster >= 0 and pvs[lf.cluster] and _isSunlit[i] then
			return true
		end
	end
	return false
end

-- Pass 2 (mode 2): PVS + _isSunlit + ALL-PAIRS raycast confirm.
-- For each sample in A, trace toward every sample in B; first hit → visible.
local function leafSeesSunlit_Confirm(leaf)
	if not leaf or not leaf.cluster or leaf.cluster < 0 then return false end
	if _isSunlit[leafIndexOf(leaf)] then return true end

	local pvs = leaf:CreatePVS()
	if not pvs then return true end

	local mySamples = leafSamples(leaf, CONFIRM_SAMPLES)
	if not mySamples then return true end
	local nA = #mySamples

	for i = 1, #_leafs do
		local lf = _leafs[i]
		if lf and lf.cluster and lf.cluster >= 0
			and pvs[lf.cluster] and _isSunlit[i] then
			local candSamples = leafSamples(lf, CONFIRM_SAMPLES)
			if candSamples then
				local nB = #candSamples
				local found = false
				for a = 1, nA do
					local sa = mySamples[a]
					for b = 1, nB do
						local tr = util.TraceLine({
							start  = sa,
							endpos = candSamples[b],
							mask   = MASK_OPAQUE,
						})
						if not tr.Hit or tr.Fraction >= 0.999 then
							found = true
							break
						end
					end
					if found then break end
				end
				if found then return true end
			end
		end
	end
	return false
end

local function leafSeesSunlit(leaf)
	return leafSeesSunlit_PVS(leaf)
end

-- ── Async build driver ───────────────────────────────────────────────────────
local function startBake(sunAngle)
	_sunDirCache    = sunAngle:Forward()
	_isSunlit       = {}
	_seesSunlit     = {}
	_idx            = 1
	_total          = #_leafs
	_phase          = 1
	_building       = true
end

local function tickBuild()
	if not _building then return end

	if _phase == 1 then
		local stop = math.min(_idx + CHUNK_PASS1 - 1, _total)
		for i = _idx, stop do
			local lf = _leafs[i]
			_isSunlit[i] = lf and leafIsSunlit(lf, _sunDirCache) or false
		end
		_idx = stop + 1
		if _idx > _total then
			_phase = 2
			_idx   = 1
		end

	elseif _phase == 2 then
		local stop = math.min(_idx + CHUNK_PASS2 - 1, _total)
		for i = _idx, stop do
			local lf = _leafs[i]
			_seesSunlit[i] = lf and leafSeesSunlit(lf) or false
		end
		_idx = stop + 1
		if _idx > _total then
			_phase    = 3
			_building = false
			_ready    = true
			_ready_isSunlit   = _isSunlit
			_ready_seesSunlit = _seesSunlit
		end
	end
end

hook.Add("Think", "RealCSM_SunBake_Build", tickBuild)

-- ── Public API ───────────────────────────────────────────────────────────────
local function bucketAngle(ang)
	local b = ANGLE_BUCKET
	return string.format("%d_%d",
		math.Round(ang.p / b) * b,
		math.Round(ang.y / b) * b)
end

function M.Init(bsp)
	if not bsp then return end
	buildSphereDirs()
	_bsp   = bsp
	_leafs = bsp:GetLeafs()
	_nodes = bsp:GetNodes()
end

function M.IsReady()    return _ready and not _building end
function M.IsBuilding() return _building end
function M.GetPhase()   return _phase end

-- Expose sunlit set + leafs for mode 3 (runtime eye-based check).
function M.GetSunlitTable() return _ready_isSunlit end
function M.GetLeafs()       return _leafs end
function M.IsLeafSunlit(idx) return _ready_isSunlit[idx] == true end
function M.Progress()
	if _ready and not _building then return 1 end
	if _total == 0 then return 0 end
	-- Rough progress: phase 1 is 0..0.4, phase 2 is 0.4..1
	local frac = (_idx - 1) / _total
	if _phase == 1 then return frac * 0.4 end
	if _phase == 2 then return 0.4 + frac * 0.6 end
	return 0
end

function M.EnsureBake(sunAngle, mode)
	if not _leafs or #_leafs == 0 then return end
	if not sunAngle then return end

	mode = mode or 1
	local key = bucketAngle(sunAngle) .. "_m" .. mode
	if key == _cacheKey then return end

	_cacheKey = key
	_bakeMode = mode
	startBake(sunAngle)
end

-- "Does this leaf see any sunlit leaf?" — runtime cull query.
function M.LeafSeesSun(leaf, sunAngle, mode)
	M.EnsureBake(sunAngle, mode)
	if not leaf then return true end
	if not _ready then
		-- Pre-bake: don't false-cull.
		return RealCSM.SkyVis and RealCSM.SkyVis.LeafSeesSky(leaf) or true
	end
	local idx = leafIndexOf(leaf)
	local v = _ready_seesSunlit[idx]
	if v == nil then return true end
	return v
end

-- Debug
function M.GetLeafIsSunlit(leaf)
	if not leaf or not _ready then return nil end
	return _ready_isSunlit[leafIndexOf(leaf)]
end
function M.GetLeafSeesSunlit(leaf)
	if not leaf or not _ready then return nil end
	return _ready_seesSunlit[leafIndexOf(leaf)]
end
function M.GetCacheKey() return _cacheKey end

function M.Reset()
	_bsp        = nil
	_leafs      = nil
	_nodes      = nil
	_phase      = 0
	_building   = false
	_idx        = 1
	_total      = 0
	_ready      = false
	_cacheKey   = nil
	_sunDirCache = nil
	_isSunlit       = {}
	_seesSunlit     = {}
	_ready_isSunlit  = {}
	_ready_seesSunlit = {}
end

hook.Add("OnReloaded", "RealCSM_SunBake_Reset", function() M.Reset() end)
