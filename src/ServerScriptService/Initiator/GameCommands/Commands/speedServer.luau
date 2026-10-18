local ServerScriptService = game:GetService("ServerScriptService")
local SpeedServiceServer = require(ServerScriptService.Initiator.Services.SpeedService.SpeedServiceServer)

return function(context, action: string, value: string?, players: { Player }?)
	local names = {}
	for _, player in players or { context.Executor } do
		SpeedServiceServer:Command(player, action, value)
		table.insert(names, player.Name)
	end
	return ("speed %s%s -> %s"):format(action, if value then " " .. value else "", table.concat(names, ", "))
end
