hook.Add( "PlayerInitialSpawn", "FullLoadSetup", function( ply )
	hook.Add( "SetupMove", ply, function( self, ply, _, cmd )
		if self == ply and not cmd:IsForced() then
			hook.Run( "PlayerFullLoad", self )
			hook.Remove( "SetupMove", self )
            if (SERVER) then
                net.Start( "PlayerSpawnedFully" )
                net.Send( ply )	
            end
		end
	end )
end )