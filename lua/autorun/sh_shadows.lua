hook.Add( "PlayerInitialSpawn", "RealCSMFullLoadSetup", function( ply )
	hook.Add( "SetupMove", ply, function( self, mvply, _, cmd )
		if self == mvply and not cmd:IsForced() then
			hook.Run( "RealCSMPlayerFullLoad", self )
			hook.Remove( "SetupMove", self )
			if (SERVER) then
				net.Start( "RealCSMPlayerSpawnedFully" )
				net.Send( mvply )
			end
		end
	end )
end )