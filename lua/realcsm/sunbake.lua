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
local CHUNK_PASS1      = 64    -- leafs per frame in pass 1
local CHUNK_PASS2      = 64    -- leafs per frame in pass 2 (PVS-only, fast)

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
				mask   = MASK_SOLID_BRUSHONLY,
			})
			if tr.HitSky then return true end
		end
	end
	return false
end

-- Pass 2: any leaf in this leaf's PVS is _isSunlit?
-- Uses PVS (leaky but conservative — false positive is fine, false negative is not).
-- The accuracy improvement vs mode 0 comes from the sunlit set itself: pass 1
-- raycast-tested every leaf, replacing the noisy compile-time HasSkyboxInPVS flag.
local function leafSeesSunlit(leaf)
	if not leaf or not leaf.cluster or leaf.cluster < 0 then return false end

	-- Trivial: this leaf itself is sunlit.
	if _isSunlit[leafIndexOf(leaf)] then return true end

	local pvs = leaf:CreatePVS()
	if not pvs then return true end   -- can't compute → conservative true

	for i = 1, #_leafs do
		local lf = _leafs[i]
		if lf and lf.cluster and lf.cluster >= 0 and pvs[lf.cluster] and _isSunlit[i] then
			return true
		end
	end
	return false
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
function M.Progress()
	if _ready and not _building then return 1 end
	if _total == 0 then return 0 end
	-- Rough progress: phase 1 is 0..0.4, phase 2 is 0.4..1
	local frac = (_idx - 1) / _total
	if _phase == 1 then return frac * 0.4 end
	if _phase == 2 then return 0.4 + frac * 0.6 end
	return 0
end

function M.EnsureBake(sunAngle)
	if not _leafs or #_leafs == 0 then return end
	if not sunAngle then return end

	local key = bucketAngle(sunAngle)
	if key == _cacheKey then return end

	_cacheKey = key
	startBake(sunAngle)
end

-- "Does this leaf see any sunlit leaf?" — runtime cull query.
function M.LeafSeesSun(leaf, sunAngle)
	M.EnsureBake(sunAngle)
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
