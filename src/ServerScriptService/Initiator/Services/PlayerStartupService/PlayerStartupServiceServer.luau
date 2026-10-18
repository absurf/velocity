local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.Initiator.DataStore.ProfileStore)
local Template = require(ServerScriptService.Initiator.DataStore.Template)
local Profiles = require(ServerScriptService.Initiator.DataStore.Profiles)

local PlayerStartupServiceServer = {}
type PlayerStartupServiceServer = typeof(PlayerStartupServiceServer)

local DataStore_Key = "SpeedTest1"
-- local DataStore_Key = "Production1"
local PlayerStore = ProfileStore.New(DataStore_Key, Template)

-- // PRIVATE //--

local function Loaded(player: Player)
	local profile = Profiles.Profiles[player]
	if profile == nil then return end
end

local function PlayerAdded(player: Player)
	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile ~= nil then
		profile:AddUserId(player.UserId) -- GDPR compliance
		profile:Reconcile() -- Fill in missing variables

		profile.OnSessionEnd:Connect(function()
			Profiles.Profiles[player] = nil
			player:Kick(`Data Error - Please rejoin!`)
		end)

		if player.Parent == Players then
			Profiles.Profiles[player] = profile
			print(`Profile loaded for {player.DisplayName}!`)
			Loaded(player)
		else
			-- Player left before session started
			profile:EndSession()
		end
	else
		-- Server shutting down
		player:Kick(`Profile load fail - Please rejoin`)
	end
end

-- // PUBLIC //--

function PlayerStartupServiceServer.Init(self: PlayerStartupServiceServer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerAdded, player)
	end
	Players.PlayerAdded:Connect(PlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = Profiles.Profiles[player]
		if profile ~= nil then
			profile:EndSession()
		end
	end)
end

return PlayerStartupServiceServer :: PlayerStartupServiceServer
