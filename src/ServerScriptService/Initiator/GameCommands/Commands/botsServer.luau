local ServerScriptService = game:GetService("ServerScriptService")
local SpeedBotServer = require(ServerScriptService.Initiator.Services.SpeedService.SpeedBotServer)

local NAMES = { easy = "Easy", normal = "Normal", hard = "Hard" }

return function(_context, difficulty: string?, count: number?)
	local word = (difficulty or "normal"):lower()
	if word == "off" or word == "none" or word == "0" then
		SpeedBotServer:Clear()
		return "bots off"
	end
	local level = NAMES[word]
	if not level then return ("bots: %q isn't easy / normal / hard / off"):format(word) end
	local made, why = SpeedBotServer:Fill(level, count)
	if why then return ("bots %s: %s"):format(level, why) end
	local tiers = {}
	for _, bot in SpeedBotServer:List() do tiers[bot.Tier] = (tiers[bot.Tier] or 0) + 1 end
	return ("bots %s: %d (%d Pro, %d Racer, %d Rookie) lining up -- they launch in a moment"):format(level, made,
		tiers.Pro or 0, tiers.Racer or 0, tiers.Rookie or 0)
end
