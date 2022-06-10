
CreateClientConVar(	 "csm_spawnalways", 0,  true, false)

hook.Add( "PopulateToolMenu", "CustomMenuSettings", function()
	spawnmenu.AddToolMenuOption( "Utilities", "User", "CSM", "#CSM", "", "", function( panel )
		panel:ClearControls()
		panel:CheckBox( "CSM Enabled", "csm_enabled" )
		
		panel:NumSlider( "Shadow Quality", "r_flashlightdepthres", 0, 8192 )
		panel:NumSlider( "Shadow Filter", "r_projectedtexture_filter", 0, 10)

		panel:CheckBox( "CSM Spawn on load (Experimental)", "csm_spawnalways" )

		-- Add stuff here
	end )
end )