CreateConVar( "csm_spawnalways", 0,  true, false )
CreateConVar( "csm_spawnwithlightenv", 0,  true, false )
CreateConVar( "csm_allowwakeprops", 1,  true, false )
CreateConVar( "csm_allowfpshadows_old", 0,  true, false )
hook.Add( "PopulateToolMenu", "CSMServer", function()
	spawnmenu.AddToolMenuOption( "Utilities", "Admin", "CSM_Server", "#CSM", "", "", function( panel )
		panel:ClearControls()

		panel:CheckBox( "CSM Spawn on load (Experimental)", "csm_spawnalways" )

		panel:CheckBox( "Spawn if light_environment exists (Experimental)", "csm_spawnwithlightenv" )

		panel:CheckBox( "Allow clients to wake up all props.", "csm_allowwakeprops" )
		-- Add stuff here
		panel:CheckBox( "Allow clients to use legacy firstperson shadow method", "csm_allowfpshadows_old" )
	end )
end )
if (SERVER) then
	util.AddNetworkString( "PlayerSpawnedFully" )
	function actualSpawn()
		local csm_ent = ents.Create( "edit_csm" )
		csm_ent:SetPos( Vector( 0, 0, -10000 ) )
		csm_ent:Spawn()
	end

	function spawnCSM() -- TODO: find out why the spawn with lightenv convar resets every game reload (not cleanup) ~starundrscre
		local spawnEnabled = GetConVar( "csm_spawnalways" )
		local envCheckToggle = GetConVar( "csm_spawnwithlightenv" )
		local lightEnvExists

		if (table.Count(ents.FindByClass("light_environment")) > 0) then
			RunConsoleCommand("csm_haslightenv", "1")
			lightEnvExists = true
		else
			RunConsoleCommand("csm_haslightenv", "0")
			lightEnvExists = false
		end

		if spawnEnabled:GetBool() == true and (FindEntity("edit_csm") == nil) then
			if envCheckToggle:GetBool() == true then
				if lightEnvExists == true then
					actualSpawn()
				end
			elseif envCheckToggle:GetBool() == false then
				actualSpawn()
			end
		end

		if (GetConVar( "csm_stormfoxsupport" ):GetBool() == true) and (spawnEnabled:GetBool() == false) then
			for k, v in ipairs(ents.FindByClass( "light_environment" )) do
				v:Fire("turnon")
			end
		end
	end
	util.AddNetworkString( "cool_addon_client_ready" )

	hook.Add( "PostCleanupMap", "cleanupcsm", spawnCSM)
	hook.Add( "PlayerFullLoad", "autospawn", spawnCSM)

	hook.Add("stormfox2.postinit", "csmstormfoxsupporthook", function()
		RunConsoleCommand("csm_stormfoxsupport", "1")
		StormFox2.Setting.Set("maplight_dynamic", false)
		StormFox2.Setting.Set("maplight_lightstyle", false)
		StormFox2.Setting.Set("maplight_lightenv", false)
		for k, v in ipairs(ents.FindByClass( "light_environment" )) do
			v:Fire("turnoff")
		end
	end)

end