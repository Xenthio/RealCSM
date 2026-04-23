-- lua/realcsm/skyboxfix.lua
-- Skybox far-plane hack so the shadow projectors don't clip the skybox.
-- https://youtu.be/gTR2TVXbMGI?t=102  (fix for 1:48)

RealCSM = RealCSM or {}
local M = {}
RealCSM.SkyboxFix = M

function M.On()
	local fog = ents.FindByClass("env_fog_controller")[1]
	if fog then fog:SetKeyValue("farz", 80000) end
	RunConsoleCommand("r_farz", "80000")
end

function M.Off()
	local fog = ents.FindByClass("env_fog_controller")[1]
	if fog then fog:SetKeyValue("farz", -1) end
	RunConsoleCommand("r_farz", "-1")
end
