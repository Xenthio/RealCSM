-- lua/realcsm/rtt.lua
-- RTT (render-to-texture) shadow suppression helpers. CLIENT ONLY.
-- Patches meta:DrawShadow exactly once per session (guarded against hot-reload double-wrap).

RealCSM = RealCSM or {}
local M = {}
RealCSM.RTT = M

local rttEnabled = true

-- Patch meta:DrawShadow once so we can gate it.
local meta = FindMetaTable("Entity")
if not meta._realcsm_drawshadow_patched then
	meta._realcsm_drawshadow_patched = true
	local orig = meta.DrawShadow
	meta._realcsm_origDrawShadow = orig

	function meta:DrawShadow(val)
		if rttEnabled then
			self._realcsm_storedShadow = val
			orig(self, val)
		else
			orig(self, false)
		end
	end
end

local function applyToAll()
	for _, v in pairs(ents.GetAll()) do
		v:DrawShadow(v._realcsm_storedShadow or true)
	end
end

local function onEntityCreated(ent)
	ent:DrawShadow(ent._realcsm_storedShadow or true)
	-- Experimental: translucent entity shadow fix.
	if ent:GetRenderGroup() == RENDERGROUP_TRANSLUCENT
	   and RealCSM.CVar("csm_experimental_translucentshadows"):GetBool() then
		ent.RenderOverride = function(self2, flags)
			if self2:GetRenderMode() ~= RENDERMODE_NONE then
				self2:SetRenderMode(RENDERMODE_NONE)
			end
			self2:DrawModel(flags)
			render.OverrideDepthEnable(false, true)
		end
	end
end

function M.Disable()
	if not rttEnabled then return end
	rttEnabled = false
	print("[Real CSM] - Disabling RTT Shadows")
	RunConsoleCommand("r_shadows_gamecontrol", "0")
	hook.Add("OnEntityCreated", "RealCSMDisableRTTHook", onEntityCreated)
	applyToAll()
end

function M.Enable()
	if rttEnabled then return end
	rttEnabled = true
	print("[Real CSM] - Enabling RTT Shadows")
	RunConsoleCommand("r_shadows_gamecontrol", "1")
	hook.Remove("OnEntityCreated", "RealCSMDisableRTTHook")
	applyToAll()
end

function M.IsEnabled()
	return rttEnabled
end
