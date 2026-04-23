-- lua/entities/edit_csm/shared.lua
-- Runs on BOTH client and server.
-- Handles: AddCSLuaFile, base/meta setup, SetupDataTables, UpdateTransmitState.

-- TODO: Use a single ProjectedTexture when r_flashlightdepthres is 0 (no shadows anyway).

AddCSLuaFile()

ENT.Type      = "anim"
ENT.Base      = "base_edit_csm"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.PrintName = "CSM Editor"
ENT.Category  = "Editors"

function ENT:SetupDataTables()
	self:NetworkVar("Vector", 0, "SunColour",      { KeyName = "Sun colour",          Edit = { type = "VectorColor", order = 2,  title = "Sun colour"              } })
	self:NetworkVar("Float",  0, "SunBrightness",  { KeyName = "Sun brightness",      Edit = { type = "Float",       order = 3,  min = 0,     max = 10000, title = "Sun brightness"       } })

	self:NetworkVar("Float",  1, "SizeNear",       { KeyName = "Size 1",              Edit = { type = "Float",       order = 4,  min = 0,     max = 32768, title = "Near cascade size"    } })
	self:NetworkVar("Float",  2, "SizeMid",        { KeyName = "Size 2",              Edit = { type = "Float",       order = 5,  min = 0,     max = 32768, title = "Middle cascade size"  } })
	self:NetworkVar("Float",  3, "SizeFar",        { KeyName = "Size 3",              Edit = { type = "Float",       order = 6,  min = 0,     max = 32768, title = "Far cascade size"     } })
	self:NetworkVar("Float",  4, "SizeFurther",    { KeyName = "Size 4",              Edit = { type = "Float",       order = 8,  min = 0,     max = 65536, title = "Further cascade size" } })

	self:NetworkVar("Float",  5, "Orientation",    { KeyName = "Orientation",         Edit = { type = "Float",       order = 10, min = 0,     max = 360,   title = "Sun orientation"      } })
	self:NetworkVar("Bool",   2, "UseMapSunAngles",{ KeyName = "Use Map Sun Angles",  Edit = { type = "Bool",        order = 11, title = "Use map sun angles"      } })
	self:NetworkVar("Bool",   3, "UseSkyFogEffects",{ KeyName = "Use Sky and Fog Effects", Edit = { type = "Bool",  order = 12, title = "Use sky and fog effects"  } })
	self:NetworkVar("Float",  6, "MaxAltitude",    { KeyName = "Maximum altitude",    Edit = { type = "Float",       order = 13, min = 0,     max = 90,    title = "Maximum altitude"     } })
	self:NetworkVar("Float",  7, "Time",           { KeyName = "Time",                Edit = { type = "Float",       order = 14, min = 0,     max = 1,     title = "Time of Day"          } })
	self:NetworkVar("Float",  9, "Height",         { KeyName = "Height",              Edit = { type = "Float",       order = 15, min = 0,     max = 50000, title = "Sun Height"           } })
	self:NetworkVar("Float", 10, "SunNearZ",       { KeyName = "NearZ",               Edit = { type = "Float",       order = 16, min = 0,     max = 32768, title = "Sun NearZ"            } })
	self:NetworkVar("Float", 11, "SunFarZ",        { KeyName = "FarZ",                Edit = { type = "Float",       order = 17, min = 0,     max = 50000, title = "Sun FarZ"             } })

	self:NetworkVar("Bool",   4, "RemoveStaticSun",{ KeyName = "Remove Vanilla Static Sun", Edit = { type = "Bool", order = 18, title = "Remove vanilla static sun" } })
	self:NetworkVar("Bool",   5, "HideRTTShadows", { KeyName = "Hide RTT Shadows",    Edit = { type = "Bool",        order = 19, title = "Hide RTT shadows"         } })

	self:NetworkVar("Bool",   6, "EnableOffsets",  { KeyName = "Enable Offsets",      Edit = { type = "Bool",        order = 21, title = "Enable angle offsets"     } })
	self:NetworkVar("Int",    0, "OffsetPitch",    { KeyName = "Pitch Offset",        Edit = { type = "Float",       order = 22, min = -180, max = 180, title = "Pitch Offset" } })
	self:NetworkVar("Int",    1, "OffsetYaw",      { KeyName = "Yaw Offset",          Edit = { type = "Float",       order = 23, min = -180, max = 180, title = "Yaw Offset"   } })
	self:NetworkVar("Int",    2, "OffsetRoll",     { KeyName = "Roll Offset",         Edit = { type = "Float",       order = 24, min = -180, max = 180, title = "Roll Offset"  } })
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end
