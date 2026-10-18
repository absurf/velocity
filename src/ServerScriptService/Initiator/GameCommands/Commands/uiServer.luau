local ServerScriptService = game:GetService("ServerScriptService")
local SpeedServiceServer = require(ServerScriptService.Initiator.Services.SpeedService.SpeedServiceServer)

return function(context, mode: string, players: { Player }?)
	local names = {}
	for _, player in players or { context.Executor } do
		SpeedServiceServer:Command(player, "ui", mode)
		table.insert(names, player.Name)
	end
	return ("ui %s -> %s"):format(mode, table.concat(names, ", "))
end
