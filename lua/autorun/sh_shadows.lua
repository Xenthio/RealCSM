hook.Add( "PlayerInitialSpawn", "FullLoadSetup", function( ply )
	hook.Add( "SetupMove", ply, function( self, mvply, _, cmd )
		if self == mvply and not cmd:IsForced() then
			hook.Run( "PlayerFullLoad", self )
			hook.Remove( "SetupMove", self )
			if (SERVER) then
				net.Start( "PlayerSpawnedFully" )
				net.Send( mvply )
			end
		end
	end )
end )