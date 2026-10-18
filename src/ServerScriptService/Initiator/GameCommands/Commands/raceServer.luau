local ServerScriptService = game:GetService("ServerScriptService")
local SpeedRaceServer = require(ServerScriptService.Initiator.Services.SpeedService.SpeedRaceServer)

local NAMES = { easy = "Easy", normal = "Normal", hard = "Hard", off = "Off", none = "Off" }

return function(_context, seed: number?, bots: string?)
	local level = NAMES[(bots or "normal"):lower()]
	if not level then return ("race: %q isn't easy / normal / hard / off"):format(tostring(bots)) end
	local summary, err = SpeedRaceServer:Start(seed, level)
	return err and ("race: " .. err) or summary
end
