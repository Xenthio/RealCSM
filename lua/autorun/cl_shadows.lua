--[[
	ddd
ddd
sssssssssssss	dd
--]]

CreateClientConVar( "csm_skyboxfix", 1,  true, false )
CreateClientConVar( "csm_spawnalways", 0,  true, false )
CreateClientConVar( "csm_spawnwithlightenv", 0,  true, false )
CreateClientConVar( "csm_propradiosity", 4,  true, false )
CreateClientConVar( "csm_blobbyao", 0,  true, false )
CreateClientConVar( "csm_wakeprops", 1,  true, false )
CreateClientConVar(	"csm_spread", 0,  false, false)
CreateClientConVar(	"csm_spread_samples", 7,  true, false)
CreateClientConVar(	"csm_spread_radius", 0.5,  true, false)
CreateClientConVar(	"csm_spread_layers", 1,  true, false)
CreateClientConVar(	"csm_spread_layer_density", 0,  true, false)
CreateClientConVar(	"csm_localplayershadow", 0,  true, false)
CreateClientConVar(	"csm_localplayershadow_old", 0,  false, false)
CreateClientConVar(	"csm_further", 0,  true, false)
CreateClientConVar(	"csm_furthershadows", 1,  true, false)
CreateClientConVar(	"csm_farshadows", 1,  true, false)
CreateClientConVar(	"csm_sizescale", 1,  true, false)
CreateClientConVar(	"csm_perfmode", 0,  true, false)
CreateClientConVar(	"csm_redownloadonremove", 1,  true, false)
CreateClientConVar(	"csm_depthresasmultiple", 0,  false, false)
CreateClientConVar(	"csm_depthbias", 0.000002,  false, false)
CreateClientConVar(	"csm_slopescaledepthbias", 2,  false, false)

CreateClientConVar(	"csm_debug_cascade", 0,  false, false)
CreateClientConVar(	"csm_disable_warnings", 0,  false, false)

local ConVarsDefault = {
	csm_spawnalways = "0",
	csm_spawnwithlightenv = "0",
	csm_propradiosity = "4",
	csm_blobbyao = "0",
	csm_wakeprops = "1",
	csm_spread = "0",
	csm_spread_samples = "7",
	csm_spread_radius = "0.5",
	csm_localplayershadow = "0",
	csm_further = "0",
	csm_furthershadows = "1",
	csm_sizescale = "1",
	csm_perfmode = "0",
	csm_depthbias = "0.000002",
	csm_slopescaledepthbias = "2",
}

hook.Add( "PopulateToolMenu", "CSMClient", function()
	spawnmenu.AddToolMenuOption( "Utilities", "User", "CSM_Client", "#CSM", "", "", function( panel )
		panel:ClearControls()
		
		panel:ControlHelp( "Thanks for using Real CSM! In order to allow me to continue to fix and support this addon while keeping it free, it would be nice if you could PLEASE consider donating to my patreon!" )
		panel:ControlHelp("https://www.patreon.com/xenthio")

		panel:AddControl( "ComboBox", { MenuButton = 1, Folder = "presetCSM", Options = { [ "#preset.default" ] = ConVarsDefault }, CVars = table.GetKeys( ConVarsDefault ) } )

		panel:CheckBox( "CSM Enabled", "csm_enabled" )

		panel:CheckBox( "Performance mode.", "csm_perfmode")
		panel:ControlHelp( "Performance mode, when on CSM will only use 2 cascade rings, this will reduce perceived quality of nearby shadows." )

		panel:CheckBox( "Super performance mode", "csm_farshadows")
		panel:ControlHelp( "Disable shadows on the far cascade, for more performance.")

		qualityslider = panel:NumSlider( "Shadow Quality", "r_flashlightdepthres", 0, 16384, 0 )
		panel:ControlHelp( "Shadow map resolution." )
		qualityslider.OnValueChanged = function(self, value) 
			RunConsoleCommand("csm_depthresasmultiple", math.log (value) / math.log (2) - 6)
			RunConsoleCommand("r_flashlightdepthres", value)
		end
		
		multslider = panel:NumSlider( "Shadow Quality as Multiple", "csm_depthresasmultiple", 0, 8, 0 )
		panel:ControlHelp( "Shadow map resolution (as an exponential multipler)." )
		multslider.OnValueChanged = function(self, value)  

			if multslider:IsEditing() then RunConsoleCommand("r_flashlightdepthres", 2^math.floor(GetConVar("csm_depthresasmultiple"):GetFloat() + 6)) end
		end
		multslider:SetValue(math.log(qualityslider:GetValue()) / math.log (2) - 6)

		panel:NumSlider( "Shadow Filter", "r_projectedtexture_filter", 0, 10)
		panel:ControlHelp( "Default Source engine shadow filter, It's quite grainy, it's best you leave this at 0.10 unless you know what you're doing." )

		local combobox = panel:ComboBox( "Prop Radiosity", "csm_propradiosity" )
		combobox:AddChoice( "0: no radiosity", 0 )
		combobox:AddChoice( "1: radiosity with ambient cube (6 samples)", 1 )
		combobox:AddChoice( "2: radiosity with 162 samples", 2 )
		combobox:AddChoice( "3: 162 samples for static props, 6 samples for everything else (Garry's Mod Default)", 3 )
		combobox:AddChoice( "4: 162 samples for static props, leaf node for everything else (Real CSM Default)", 4 )
		panel:ControlHelp( "The radiosity for adding indirect lighting to the shading of props, this is what r_radiosity is set to when CSM is turned on." )
		panel:CheckBox( "Update and Wake Props", "csm_wakeprops" )
		panel:ControlHelp( "Wake up props after the radiosity setting changes.")

		panel:CheckBox( "Enable AO Like Blob Shadows", "csm_blobbyao" )
		panel:ControlHelp( "Enables blob shadows that are modified to look like AO." )



		panel:CheckBox( "Shadow Spread", "csm_spread" )
		panel:ControlHelp( "Simulates the penumbra of the sun, can also be used for multisampling on shadows." )
		panel:ControlHelp( "Notice: Enabling spread disables the near ring, shadows may look lower quality closer up." )
		panel:ControlHelp( "Notice: Spread is only on the second ring to avoid blowing up your computer." )
		panel:NumSlider( "Spread Radius", "csm_spread_radius", 0, 2)
		panel:ControlHelp( "Radius of the spread in degrees, real life value is 0.5, gm_construct uses an unrealistic value of 3, you should use 0.5." )

		panel:NumSlider( "Spread Samples", "csm_spread_samples", 2, 16, 0)
		panel:ControlHelp( "Alert! This doesn't work above 7 unless you launch gmod with extra shadow maps enabled!!!" )
		panel:ControlHelp( "Double Alert! Setting this too high may crash your game!" )

		panel:NumSlider( "Spread Circle Layers", "csm_spread_layers", 1, 6, 0)
		panel:ControlHelp( "Since circle packing in a circle is hard I settled on layers for circles to fill in the middle, 1 is softer but 2 is more accurate and might look harsher" )
		--panel:NumSlider( "Spread Circle Layer Density", "csm_spread_layer_density", 0, 1)
		--panel:ControlHelp( "How close each layer is, It's recommended to leave this at 0 but the option is here just in case" )

		panel:CheckBox( "Draw Firstperson Shadows (Experimental)", "csm_localplayershadow" )
		panel:ControlHelp( "See your own shadows in firstperson" )

		panel:NumSlider( "Size / Distance Scale", "csm_sizescale", 0, 5)
		panel:ControlHelp( "Cascade size multiplier to lower / raise view distance, this affects the perceived quality." )

		panel:CheckBox( "Enable further cascade for large maps", "csm_further")
		panel:ControlHelp( "Add a further cascade to increase shadow draw distance without sacrificing perceived quality" )
		panel:CheckBox( "Enable shadows on further cascade", "csm_furthershadows")
		panel:ControlHelp( "Enable shadows on the further cascade, ")
		

		panel:NumSlider( "Shadowmap Depth Bias", "csm_depthbias", -1, 1, 6)
		panel:ControlHelp( "The amount to bias the depth of the shadowmap by." )
		
		panel:NumSlider( "Shadowmap Slope Scale Depth Bias", "csm_slopescaledepthbias", 0, 6, 1)
		panel:ControlHelp( "The sloped scale of the amount the depth of the shadowmap is biased by." )

		panel:CheckBox( "Cascade Debug", "csm_debug_cascade")
		panel:ControlHelp( "Each cascade is drawn in a different colour, this is useful for debugging." )

		
		local resetbutton = panel:Button( "Open First-Time Setup" )
		resetbutton.DoClick = FirstTimeSetup

		-- Add stuff here
	end )
end )

if (CLIENT) then
	function firstTimeCheck()
		if !(file.Read( "realcsm.txt", "DATA" ) == "two" ) and (file.Read( "realcsm.txt", "DATA" ) != "one" ) then
		--if true then
			FirstTimeSetup()
		end
	end
	function FirstTimeSetup()
			--if not game.SinglePlayer() then return end
			--Derma_Message( "Hello! Welcome to the CSM addon! You should raise r_flashlightdepthres else the shadows will be blocky! Make sure you've read the FAQ for troubleshooting.", "CSM Alert!", "OK!" )
			local Frame = vgui.Create( "DFrame" )
			Frame:SetSize( 330, 290 )

			RunConsoleCommand("r_flashlightdepthres", "1024") -- set it to the lowest of the low to avoid crashes

			Frame:Center()
			Frame:SetTitle( "CSM First Time Load!" )
			Frame:SetVisible( true )
			Frame:SetDraggable( false )
			Frame:ShowCloseButton( true )
			Frame:MakePopup()
			local label1 = vgui.Create( "DLabel", Frame )
			label1:SetPos( 15, 40 )
			label1:SetSize(	300, 20)
			label1:SetText( "Thanks for using Real CSM!" )
			label1:SetTextColor( Color( 255, 255, 255) )

			
			local labelp1 = vgui.Create( "DLabel", Frame )
			labelp1:SetPos( 15, 55 )
			labelp1:SetSize(	300, 20)
			labelp1:SetText( "In order to allow me to support this addon and keep it free," )
			local labelp2 = vgui.Create( "DLabel", Frame )
			labelp2:SetPos( 15, 70 )
			labelp2:SetSize(	300, 20)
			labelp2:SetText( "it would be nice if you could consider donating to my patreon!" )
			local labelp3 = vgui.Create( "DLabel", Frame )
			labelp3:SetPos( 15, 85 )
			labelp3:SetSize(	300, 20)
			labelp3:SetText( "https://www.patreon.com/xenthio" )
			labelp3:SetTextColor( Color( 255, 255, 255) )

			
			local label2 = vgui.Create( "DLabel", Frame )
			label2:SetPos( 15, 110 )
			label2:SetSize(	300, 20)
			label2:SetText( "Refer to the F.A.Q for troubleshooting and help!" )
			local label3 = vgui.Create( "DLabel", Frame )
			label3:SetPos( 15, 125 )
			label3:SetSize(	300, 20)
			label3:SetText( "More quality settings will be shown when csm is next activated" )
			local label4 = vgui.Create( "DLabel", Frame )
			label4:SetPos( 15, 140 )
			label4:SetSize(	300, 20)
			label4:SetText( "After that they can be found in the spawnmenu's \"Utilities\" tab" )

			local DermaCheckbox2 = vgui.Create( "DCheckBoxLabel", Frame )
			DermaCheckbox2:SetText("Performance Mode")
			DermaCheckbox2:SetPos( 15, 165 )				-- Set the position
			DermaCheckbox2:SetSize( 300, 30 )			-- Set the size
			DermaCheckbox2:SetTextColor( Color( 255, 255, 255) )
			DermaCheckbox2:SetConVar( "csm_perfmode" )
			
			local label5 = vgui.Create( "DLabel", Frame )
			label5:SetPos( 39, 185 )
			label5:SetSize(	300, 20)
			label5:SetTextColor( Color( 180, 180, 180) )
			label5:SetText( "Use less shadow cascades for increased performance." )

			local DermaCheckbox = vgui.Create( "DCheckBoxLabel", Frame )
			DermaCheckbox:SetText("Spawn on load")
			DermaCheckbox:SetPos( 15, 200 )				-- Set the position
			DermaCheckbox:SetSize( 300, 30 )			-- Set the size
			DermaCheckbox:SetTextColor( Color( 255, 255, 255) )
			DermaCheckbox:SetConVar( "csm_spawnalways" )	-- Changes the ConVar when you slide

			local label6 = vgui.Create( "DLabel", Frame )
			label6:SetPos( 39, 220 )
			label6:SetSize(	300, 20)
			label6:SetTextColor( Color( 180, 180, 180) )
			label6:SetText( "Spawn Real CSM on map load, serverside only." )


			local Button = vgui.Create("DButton", Frame)
			Button:SetText( "Continue" )
			Button:SetPos( 133, 255 )
			Button.DoClick = function()
				file.Write( "realcsm.txt", "one" )
				if (GetConVar( "csm_spawnalways" ):GetInt() == 1) then
					RunConsoleCommand("gmod_admin_cleanup")
				end

				Frame:Close()
			end
	end
	
	--hook.Add( "PlayerFullLoad", "firstieCheck", firstTimeCheck)
	hook.Add( "InitPostEntity", "RealCSMReady", firstTimeCheck)
	--net.Receive( "PlayerSpawnedFully", firstTimeCheck())
end