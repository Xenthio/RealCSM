


hook.Add( "PopulateToolMenu", "CSMClient", function()
	spawnmenu.AddToolMenuOption( "Utilities", "User", "CSM_Client", "#CSM", "", "", function( panel )
		panel:ClearControls()
		panel:CheckBox( "CSM Enabled", "csm_enabled" )
		
		panel:NumSlider( "Shadow Quality", "r_flashlightdepthres", 0, 8192 )
		panel:NumSlider( "Shadow Filter", "r_projectedtexture_filter", 0, 10)

		-- Add stuff here
	end )
end )

if (CLIENT) then
	hook.Add( "InitPostEntity", "Ready", function()
		net.Start( "cool_addon_client_ready" )
		net.SendToServer()
	end )
end