local ServerScriptService = game:GetService("ServerScriptService")
local SpeedRaceServer = require(ServerScriptService.Initiator.Services.SpeedService.SpeedRaceServer)

return function(context, state: string, players: { Player }?)
	local word = string.lower(state or "")
	local on = word == "on" or word == "true" or word == "1"
	if not on and not (word == "off" or word == "false" or word == "0") then return ("autoplay: %q isn't on / off"):format(state) end
	local list = players or { context.Executor }
	SpeedRaceServer:SetAutoplay(list, on)
	local names = {}
	for _, player in list do table.insert(names, player.Name) end
	return ("autoplay %s -> %s%s"):format(if on then "on" else "off", table.concat(names, ", "),
		if on then " (races loop by themselves, 10 s apart)" else "")
end
