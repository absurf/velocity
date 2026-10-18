local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Shared.Packages.AbsurfNetworkHandler)
local SpeedServiceServer = require(script.Parent.SpeedServiceServer)
local SpeedRaceServer = require(script.Parent.SpeedRaceServer)
local SpeedItemServer = require(script.Parent.SpeedItemServer)

local SpeedServiceMain = {}
type SpeedServiceMain = typeof(SpeedServiceMain)

SpeedServiceServer:SetCallbacks({
	Command = function(player: Player, action: string, value: string?)
		Network.Send(player, "Speed_Command", false, action, value)
	end,
	Snap = function(data: buffer)
		Network.SendToAll("Speed_Snap", true, data)
	end,
	Place = function(player: Player, position: Vector3, why: string)
		Network.Send(player, "Speed_Place", false, position, why)
	end,
	Results = function(json: string)
		Network.SendToAll("Speed_Results", false, json)
	end,
})

-- // NETWORK LISTENERS //--

Network.AddListener("Speed_State", function(meta, data)
	local player = meta and meta.Player
	if player then SpeedServiceServer:State(player, data) end
end)

Network.AddListener("Speed_Request", function(meta, action)
	local player = meta and meta.Player
	if player and type(action) == "string" and not SpeedItemServer:Request(player, action) then SpeedRaceServer:Request(player, action) end
end)

return SpeedServiceMain :: SpeedServiceMain
