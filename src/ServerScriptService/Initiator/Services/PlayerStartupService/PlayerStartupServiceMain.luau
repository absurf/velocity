local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkHandler = require(ReplicatedStorage.Shared.Packages.AbsurfNetworkHandler)

local PlayerStartupServiceMain = {}
type PlayerStartupServiceMain = typeof(PlayerStartupServiceMain)

-- // NETWORK LISTENERS //--

NetworkHandler.AddListener("PlayerStartupServiceServer_ClientReady", function(meta)
	if meta.Player then
		meta.Player:SetAttribute("Client_Ready", true)
	end
end)

NetworkHandler.Activate(script)

return PlayerStartupServiceMain :: PlayerStartupServiceMain
