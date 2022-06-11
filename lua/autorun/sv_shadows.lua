

CreateConVar( "csm_spawnalways", 0,  true, false )

hook.Add( "PopulateToolMenu", "CSMServer", function()
	spawnmenu.AddToolMenuOption( "Utilities", "Admin", "CSM_Server", "#CSM", "", "", function( panel )
		panel:ClearControls()

		panel:CheckBox( "CSM Spawn on load (Experimental)", "csm_spawnalways" )

		-- Add stuff here
	end )
end )

if (SERVER) then

    util.AddNetworkString( "PlayerSpawnedFully" )
    function spawnCSM() 
        
        if (GetConVar( "csm_spawnalways" ):GetInt() == 1) then
            if (FindEntity("edit_csm") == nil) then
                if (table.Count(ents.FindByClass("light_environment")) > 0) then
                    RunConsoleCommand("csm_haslightenv", "1")
                else
                    RunConsoleCommand("csm_haslightenv", "0")
                    --self:SetRemoveStaticSun(false)
                end
                --timer.Create( "reload", 0.1, 1, function()
                    
                local poop = ents.Create( "edit_csm" )
                poop:SetPos( Vector( 0, 0, -10000 ) )
                poop:Spawn()

               
                --end)
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