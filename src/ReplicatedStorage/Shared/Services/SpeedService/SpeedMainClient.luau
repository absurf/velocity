local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Main = {}
if RunService:IsServer() then return Main end

local Network = require(ReplicatedStorage.Shared.Packages.AbsurfNetworkHandler)
local Backend = require(script.Parent.SpeedServiceClient)
local Runners = require(script.Parent.SpeedRunnersClient)

local Lag = { Delay = 0, Jitter = 0, Loss = 0 }   -- one way: seconds, seconds, 0..1

local function Through(fn, ...)
	if Lag.Loss > 0 and math.random() < Lag.Loss then return end
	local delay = Lag.Delay
	if Lag.Jitter > 0 then delay += (math.random() * 2 - 1) * Lag.Jitter end
	if delay <= 0 then
		fn(...)
	else
		task.delay(delay, fn, ...)
	end
end

local function SendState(data: buffer)
	Network.Send(nil, "Speed_State", true, data)
end

Backend:SetCallbacks({
	State = function(data: buffer)
		Through(SendState, data)
	end,
	Lag = function(pingMs: number, jitterMs: number, lossPercent: number)
		Lag.Delay = pingMs / 2000
		Lag.Jitter = math.min(jitterMs / 1000, Lag.Delay)
		Lag.Loss = lossPercent / 100
	end,
	Request = function(action: string)
		Network.Send(nil, "Speed_Request", false, action)
	end,
})

-- // NETWORK LISTENERS //--

local function Snapshot(data)
	Runners:Snapshot(data)
end

Network.AddListener("Speed_Snap", function(_meta, data)
	Through(Snapshot, data)
end)

Network.AddListener("Speed_Place", function(_meta, position, why)
	Backend:Place(position, if type(why) == "string" then why else nil)
end)

Network.AddListener("Speed_Command", function(_meta, action, value)
	Backend:Command(action, if type(value) == "string" then value else nil)
end)

Network.AddListener("Speed_Results", function(_meta, json)
	if type(json) == "string" then require(script.Parent.SpeedRaceClient):Results(json) end
end)

return Main
