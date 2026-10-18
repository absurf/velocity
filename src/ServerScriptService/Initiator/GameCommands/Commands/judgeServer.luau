local ServerScriptService = game:GetService("ServerScriptService")
local SpeedMapServer = require(ServerScriptService.Initiator.Services.SpeedService.SpeedMapServer)

return function(_context, state: string?)
	local map = SpeedMapServer:Current()
	local now = if map then ("the map up now (%s) is %s"):format(map.Name, if map:GetAttribute("Judge") then "a judge map" else "a full map") else "no map up"
	local word = string.lower(state or "")
	if word == "" then
		return ("judge mode is %s; %s"):format(if SpeedMapServer:Judge() then "ON" else "OFF", now)
	end
	local on = word == "on" or word == "true" or word == "1"
	if not on and not (word == "off" or word == "false" or word == "0") then return ("judge: %q isn't on / off"):format(state) end
	SpeedMapServer:SetJudge(on)
	return ("judge mode %s: %s from the next race / map (%s)"):format(if on then "ON" else "OFF",
		if on then "half the traps, 30% fewer lucky blocks" else "the full traps + lucky blocks", now)
end
