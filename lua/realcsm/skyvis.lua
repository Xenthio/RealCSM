-- lua/realcsm/skyvis.lua
-- Direction-independent "can the sun reach me" check, powered by NikNaks PVS.
--
-- Source maps precompute, per BSP leaf, a "skybox is in PVS" flag (vvis sets
-- LEAF_FLAGS_SKY = 0x1). NikNaks exposes this as VisLeaf:HasSkyboxInPVS().
--
-- "Can my current location see any sunlit geometry, ignoring sun direction?"
--    ≡ "is there any leaf L in MY PVS such that L:HasSkyboxInPVS()?"
--
-- We precompute, per leaf, a single bool: `_seesSky[leafIndex]`.
-- Build cost is async (spread over multiple frames) so map load doesn't stall.
--
-- Public API:
--   RealCSM.SkyVis.Init(bsp)                — kick off the async build
--   RealCSM.SkyVis.IsReady()                — bake complete?
--   RealCSM.SkyVis.Progress()               — 0..1
--   RealCSM.SkyVis.LeafSeesSky(leaf)        — direction-independent test
--   RealCSM.SkyVis.LeafHasSkyDirect(leaf)   — leaf:HasSkyboxInPVS() shortcut
--   RealCSM.SkyVis.Reset()

RealCSM = RealCSM or {}
local M = {}
RealCSM.SkyVis = M

local _bsp           = nil
local _leafs         = nil
local _skyClusters   = nil   -- set: {[clusterId] = true} for sky-flagged leaves
local _seesSky       = nil   -- array: _seesSky[leafIndex] = bool
local _ready         = false
local _building      = false
local _buildIdx      = 1
local _buildTotal    = 0

local CHUNK_PER_FRAME = 64    -- leafs processed per Think tick during build

-- ── Build state ───────────────────────────────────────────────────────────────

local function buildSkyClusters()
	_skyClusters = {}
	for i = 1, #_leafs do
		local lf = _leafs[i]
		if lf and lf.cluster and lf.cluster >= 0 and lf:HasSkyboxInPVS() then
			_skyClusters[lf.cluster] = true
		end
	end
end

local function processLeaf(leaf)
	if not leaf or not leaf.cluster or leaf.cluster < 0 then return false end

	-- Short-circuit: if our own leaf already sees the skybox, trivially true.
	if leaf:HasSkyboxInPVS() then return true end

	-- Build PVS for this leaf and see if any visible cluster is sky-flagged.
	local pvs = leaf:CreatePVS()
	if not pvs then return false end
	for cluster in pairs(pvs) do
		if cluster ~= "__map" and _skyClusters[cluster] then
			return true
		end
	end
	return false
end

local function tickBuild()
	if not _building then return end

	local stop = math.min(_buildIdx + CHUNK_PER_FRAME - 1, _buildTotal)
	for i = _buildIdx, stop do
		local lf = _leafs[i]
		_seesSky[i] = lf and processLeaf(lf) or false
	end
	_buildIdx = stop + 1

	if _buildIdx > _buildTotal then
		_building = false
		_ready    = true
	end
end

hook.Add("Think", "RealCSM_SkyVis_Build", tickBuild)

-- ── Public API ────────────────────────────────────────────────────────────────

function M.Init(bsp)
	if _ready or _building then return end
	if not bsp then return end

	_bsp      = bsp
	_leafs    = bsp:GetLeafs()
	if not _leafs then return end

	buildSkyClusters()

	_seesSky    = {}
	_buildIdx   = 1
	_buildTotal = #_leafs
	_building   = true
end

function M.IsReady() return _ready end

function M.Progress()
	if _ready then return 1 end
	if not _building then return 0 end
	if _buildTotal == 0 then return 0 end
	return (_buildIdx - 1) / _buildTotal
end

-- Direction-independent: does ANY leaf in this leaf's PVS see the skybox?
function M.LeafSeesSky(leaf)
	if not leaf then return true end
	if not _ready then
		-- Pre-bake fallback: use the cheap direct flag (less accurate, won't false-cull).
		return leaf:HasSkyboxInPVS()
	end
	local idx = leaf:GetIndex()
	local v = _seesSky[idx]
	if v == nil then return true end
	return v
end

-- Cheap direct: does THIS leaf see the skybox? (For skybox-lamp gating.)
function M.LeafHasSkyDirect(leaf)
	if not leaf then return true end
	return leaf:HasSkyboxInPVS()
end

function M.Reset()
	_bsp         = nil
	_leafs       = nil
	_skyClusters = nil
	_seesSky     = nil
	_ready       = false
	_building    = false
	_buildIdx    = 1
	_buildTotal  = 0
end

-- Reset on map cleanup so a new map re-bakes.
hook.Add("OnReloaded", "RealCSM_SkyVis_Reset", function() M.Reset() end)
