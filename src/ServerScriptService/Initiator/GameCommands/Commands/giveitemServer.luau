local ServerScriptService = game:GetService("ServerScriptService")
local SpeedItemServer = require(ServerScriptService.Initiator.Services.SpeedService.SpeedItemServer)

return function(context, item: string, players: { Player }?)
	local list = players or { context.Executor }
	local given = {}
	for _, player in list do
		local why = SpeedItemServer:Give(player, item)
		if why then return "giveitem: " .. why end
		table.insert(given, player.Name)
	end
	return ("giveitem %s -> %s"):format(item, table.concat(given, ", "))
end
