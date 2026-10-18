local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local SpeedService = ServerScriptService.Initiator.Services.SpeedService
local SpeedServiceServer = require(SpeedService.SpeedServiceServer)
local SpeedMapServer = require(SpeedService.SpeedMapServer)

return function(_context, seed: number?, pieces: string?)
	local model, data = SpeedMapServer:New(seed, pieces)
	for _, player in Players:GetPlayers() do

		SpeedServiceServer:Command(player, "course", model.Name .. " still")
	end
	local kinds = {}
	for _, piece in data.SetPieces or {} do kinds[piece.Kind] = (kinds[piece.Kind] or 0) + 1 end
	for _, trap in data.Traps or {} do kinds[trap.Kind] = (kinds[trap.Kind] or 0) + 1 end
	return ("map %d -> everyone: %d pieces, %.0f studs, %d laps, %d waypoints; %d gaps, %d island hops; traps: %d spinners, %d cages, %d lava, %d missile towers (%s)"):format(
		data.Seed, data.Pieces, data.Length, #data.Gates + 1, #data.Waypoints, kinds.Gap or 0, kinds.Hop or 0,
		kinds.Spinner or 0, kinds.Cage or 0, kinds.Lava or 0, kinds.Missile or 0, model.Name)
end
