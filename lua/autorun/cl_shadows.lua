--[[
	ddd
ddd
sssssssssssss	dd
--]]

CreateClientConVar( "csm_spawnalways", 0,  true, false )
CreateClientConVar( "csm_blobbyao", 0,  true, false )
CreateClientConVar(	 "csm_spread", 0,  true, false)
CreateClientConVar(	 "csm_spread_samples", 7,  true, false)
CreateClientConVar(	 "csm_spread_radius", 0.5,  true, false)

hook.Add( "PopulateToolMenu", "CSMClient", function()
	spawnmenu.AddToolMenuOption( "Utilities", "User", "CSM_Client", "#CSM", "", "", function( panel )
		panel:ClearControls()
		panel:CheckBox( "CSM Enabled", "csm_enabled" )
		
		panel:NumSlider( "Shadow Quality", "r_flashlightdepthres", 0, 8192 )
		panel:ControlHelp( "Shadow map resolution." )
		panel:NumSlider( "Shadow Filter", "r_projectedtexture_filter", 0, 10)
		panel:ControlHelp( "Default Source engine shadow filter, It's quite grainy, it's best you leave this at 0.10 unless you know what you're doing." )

		panel:CheckBox( "Enable AO Like Blob Shadows", "csm_blobbyao" )
		panel:ControlHelp( "Enables blob shadows that are modified to look like AO." )


		panel:CheckBox( "Shadow Spread", "csm_spread" )
		panel:ControlHelp( "Simulates the penumbra of the sun, can also be used for multisampling on shadows." )
		panel:ControlHelp( "Notice: Enabling spread disables the near ring, shadows may look lower quality closer up." )
		panel:NumSlider( "Spread Radius", "csm_spread_radius", 0, 2)
		panel:ControlHelp( "Radius of the spread in degrees, real life value is 0.5, gm_construct uses an unrealistic value of 3, you should use 0.5." )
		
		panel:NumSlider( "Spread Samples", "csm_spread_samples", 2, 16, 0)
		panel:ControlHelp( "Alert! This doesn't work above 7 unless you launch gmod with extra shadow maps enabled!!!" )

		-- Add stuff here
	end )
end )

if (CLIENT) then
	function firstTimeCheck()
		if (file.Read( "csm.txt", "DATA" ) == "two" ) then

		elseif (file.Read( "csm.txt", "DATA" ) != "one" ) then
			--if not game.SinglePlayer() then return end
			--Derma_Message( "Hello! Welcome to the CSM addon! You should raise r_flashlightdepthres else the shadows will be blocky! Make sure you've read the FAQ for troubleshooting.", "CSM Alert!", "OK!" )
			local Frame = vgui.Create( "DFrame" )
			Frame:SetSize( 310, 200 ) 
			
			RunConsoleCommand("r_flashlightdepthres", "512") -- set it to the lowest of the low to avoid crashes
	
			Frame:Center()
			Frame:SetTitle( "CSM First Time Load!" ) 
			Frame:SetVisible( true ) 
			Frame:SetDraggable( false ) 
			Frame:ShowCloseButton( true ) 
			Frame:MakePopup()
			local label1 = vgui.Create( "DLabel", Frame )
			label1:SetPos( 15, 40 )
			label1:SetSize(	300, 20)
			label1:SetText( "Thanks for using Real CSM" )
			local label2 = vgui.Create( "DLabel", Frame )
			label2:SetPos( 15, 55 )
			label2:SetSize(	300, 20)
			label2:SetText( "would you like Real CSM to spawn when you load the game?" )
			local label3 = vgui.Create( "DLabel", Frame )
			label3:SetPos( 15, 70 )
			label3:SetSize(	300, 20)
			label3:SetText( "Refer to the F.A.Q for troubleshooting and help!" )
	
			local DermaCheckbox = vgui.Create( "DCheckBoxLabel", Frame )
			DermaCheckbox:SetText("Spawn on load")
			DermaCheckbox:SetPos( 8, 120 )				-- Set the position
			DermaCheckbox:SetSize( 300, 30 )			-- Set the size
			
			DermaCheckbox:SetConVar( "csm_spawnalways" )	-- Changes the ConVar when you slide
	
			local Button = vgui.Create("DButton", Frame)
			Button:SetText( "Continue" )
			Button:SetPos( 120, 155 )
			Button.DoClick = function()
				file.Write( "csm.txt", "one" )
				if (GetConVar( "csm_spawnalways" ):GetInt() == 1) then
					RunConsoleCommand("gmod_admin_cleanup")
				end

				Frame:Close()
			end
		end
	end
	
	--hook.Add( "PlayerFullLoad", "firstieCheck", firstTimeCheck)
	hook.Add( "InitPostEntity", "Ready", firstTimeCheck)
	--net.Receive( "PlayerSpawnedFully", firstTimeCheck())
end