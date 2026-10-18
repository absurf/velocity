local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpeedServiceServer = require(ServerScriptService.Initiator.Services.SpeedService.SpeedServiceServer)
local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)

return function(context, players: { Player }?)
	local count = SpeedConfig.Hud.Countdown
	local goAt = workspace:GetServerTimeNow() + count.Beats * count.Beat + count.Lead
	local names = {}
	for _, player in players or { context.Executor } do
		SpeedServiceServer:Command(player, "countdown", ("%.3f"):format(goAt))
		table.insert(names, player.Name)
	end
	return ("countdown -> %s (GO in %.2f s)"):format(table.concat(names, ", "), goAt - workspace:GetServerTimeNow())
end
