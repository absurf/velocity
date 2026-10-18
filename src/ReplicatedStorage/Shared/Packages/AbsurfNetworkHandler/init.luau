-- [ TYPES ]--
export type NetworkMeta = {
	Player: Player?,
	Timestamp: number?,
}

-- [ SERVICES ]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunSerivce = game:GetService("RunService")
local Players_Service = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local ByteNet = require(script.net)
local space = require(script.space)

-- [ UTILITY MODULES ]--
local AbsurfUtility = require(ReplicatedStorage.Shared.Packages.AbsurfUtility)
local TaskScheduler = require(ReplicatedStorage.Shared.Packages.AbsurfTaskScheduler)

-- [ VARIABLES ]--
local Remotes_Folder = ReplicatedStorage.Remotes
local Bindable_Event = Remotes_Folder.Event
local Bindable_Function = Remotes_Folder.Function

local Player = Players_Service.LocalPlayer

local Queue_Mode = true
local SuccessfullyLoaded = false

local module = {

	["Cache"] = {},
	["Queue"] = {},
	["UsesNetworkHandler"] = {},
}

local SendQueue = {
	["TaskID"] = nil,
	["Queue"] = {},

}

local NIL_MARK = { AbsurfNil = true }
local function PackWire(...)
	local count = select("#", ...)
	local args = table.pack(...)
	local packed = table.create(count + 1)
	packed[1] = count
	for i = 1, count do
		local value = args[i]
		packed[i + 1] = if value == nil then NIL_MARK else value
	end
	return packed
end
local function UnpackWire(packed: any)
	if type(packed) ~= "table" then return end
	local count = packed[1]
	if type(count) ~= "number" then return table.unpack(packed, 1, packed.n) end
	local values = table.create(count)
	for i = 1, count do
		local value = packed[i + 1]
		if type(value) == "table" and value.AbsurfNil == true then value = nil end
		values[i] = value
	end
	return table.unpack(values, 1, count)
end

local function CreateSendQueue(DataFormat, Player : Player, Unreliable : boolean)

	if SendQueue.Queue[Player] == nil then
		SendQueue.Queue[Player] = {
			["Variables"] = {
				["Cleaned"]  = false,
			},
			["Connections"] = {
				["AncestryChanged"] = Player.AncestryChanged:Connect(function(child, par)
					if par == nil then
						SendQueue.Queue[Player].Cleanup()
					end
				end),
			},
			["Cleanup"] = function()
				if SendQueue.Queue[Player].Variables.Cleaned == false then
					SendQueue.Queue[Player].Variables.Cleaned = true

					for i,v in pairs(SendQueue.Queue[Player].Connections) do
						v:Disconnect()
					end

					SendQueue.Queue[Player] = nil

				end
			end,

			["Tbl_Data"] = {},

		}
	end

	table.insert(SendQueue.Queue[Player]["Tbl_Data"], {
		["Data"] = DataFormat,
		["Player"] = Player,
		["Unreliable"] = Unreliable,
		["Server_Delay"] = game.Workspace:GetServerTimeNow(),
	})

	if SendQueue.TaskID == nil then
		SendQueue.TaskID = TaskScheduler.Add(function(dt)

			local exist = false

			for plr_Object : Player, info in pairs(SendQueue.Queue) do

				exist = true

				if plr_Object:GetAttribute("Client_Ready") ~= nil and plr_Object:GetAttribute("Client_Ready") == true then

					for index, SendInfo in ipairs(info.Tbl_Data) do

						SendInfo.Data.Timestamp = SendInfo.Server_Delay
						if SendInfo.Unreliable then
							space.packets.unrely.sendTo(SendInfo.Data, plr_Object)
						else
							space.packets.rely.sendTo(SendInfo.Data, plr_Object)
						end
					end

					SendQueue.Queue[plr_Object].Cleanup()
				end
			end

			if exist == false then
				TaskScheduler.RemoveTask(SendQueue.TaskID)
				SendQueue.TaskID = nil
			end

		end)
	end

end

local _Perf
local function TimedListener(MethodName : string, callback, ...)

	local source = nil
	if type(callback) == "table" then
		source   = callback.Source
		callback = callback.Callback
	end
	if _Perf == nil then
		local ok, mod = pcall(function()
			return require(game:GetService("ReplicatedStorage").Shared.Modules.Core.Perf)
		end)
		_Perf = ok and mod or false
	end
	if _Perf then
		return _Perf.Time("listener " .. MethodName .. (source and (" @ " .. source) or ""), callback, ...)
	end
	return callback(...)
end

module.CallListener = function(MethodName : string, Player : Player, Is_Bound : boolean, Timestamp : number?, ...)

	if module.Cache[MethodName] ~= nil then

		if SuccessfullyLoaded == false then
			print(`Waiting for successfull loading!`)
			while SuccessfullyLoaded == false do
				task.wait()
			end
		end

		for Tag_ID,info in pairs(module.Cache[MethodName]) do

			local callback = info.Callback
			local Only_Bound = info.Only_Bound

			if Only_Bound == false then

				local meta = {
					["Player"] = Player,
					["Timestamp"] = Timestamp,
				}

				task.spawn(TimedListener, MethodName, { Callback = callback, Source = info.Source }, meta, ...)

			elseif Only_Bound == true and Is_Bound == true then

				task.spawn(TimedListener, MethodName, { Callback = callback, Source = info.Source }, ...)

			end

		end

	else

		if Queue_Mode == true then
			warn(`Entering {MethodName} into queue! Queue Mode is Active`)

			if module.Queue[MethodName] == nil then
				module.Queue[MethodName] = {
					["Requests"] = {},
				}
			end

			local RepeatLimit = 20

			local RequestFormat
			RequestFormat = {
				["MethodName"] = MethodName,
				["Player"] = Player,
				["Is_Bound"] = Is_Bound,
				["Timestamp"] = Timestamp,
				["Info"] = table.pack(...),
				["SelfID"] = AbsurfUtility.GenerateID(),
				["ID"] = TaskScheduler.Repeat(0.25, RepeatLimit, 1, function(Repeat_Amount : number)

					if module.Cache[MethodName] ~= nil then
						TaskScheduler.RemoveTask(RequestFormat.ID)
						task.spawn(function()
							module.CallListener(RequestFormat.MethodName, RequestFormat.Player, RequestFormat.Is_Bound, RequestFormat.Timestamp, table.unpack(RequestFormat.Info, 1, RequestFormat.Info.n))
						end)

						for i = #module.Queue[MethodName].Requests, 1, -1  do

							local CertainTable = module.Queue[MethodName].Requests[i]

							if CertainTable.SelfID == RequestFormat.SelfID then

								if #module.Queue[MethodName].Requests == 0 then
									module.Queue[MethodName] = nil
								end

								break
							end

						end

					end

					if Repeat_Amount == 0 then
						warn(`{MethodName} was not able to find method name while in Queue! Removing.`)

						for i = #module.Queue[MethodName].Requests, 1, -1  do

							local CertainTable = module.Queue[MethodName].Requests[i]

							if CertainTable.SelfID == RequestFormat.SelfID then

								module.Queue[MethodName].Requests[i] = nil

								if #module.Queue[MethodName].Requests == 0 then
									module.Queue[MethodName] = nil
								end

								break
							end

						end

					end

				end)
			}

			table.insert(module.Queue[MethodName].Requests, RequestFormat)

		else
			error(`{MethodName} does not exist!`)

		end

	end

end

module.AddListener = function(MethodName : string, Callback : (meta: { Player: Player?, Timestamp: number? }, ...any) -> (), Only_Bound : boolean)

	if typeof(Callback) ~= "function" then
		return error("Need to insert function!")
	end

	if module.Cache[MethodName] == nil then
		module.Cache[MethodName] = {}
	end

	local ID = AbsurfUtility.GenerateID()

	local source = debug.info(2, "s")
	if type(source) == "string" then source = source:match("[^%.]+$") or source end
	module.Cache[MethodName][ID] = {
		["Callback"] = Callback,
		["Only_Bound"] = if Only_Bound == nil then false else Only_Bound,
		["Source"] = source,
	}

	return ID
end

module.RemoveListener = function(MethodName : string, Unique_ID : string, Activate_Callback : boolean)
	if MethodName == nil and Unique_ID == nil then return end

	if MethodName ~= nil then

		if module.Cache[MethodName] then

			if Activate_Callback == true then
				for i,Active_Function in pairs(module.Cache[MethodName]) do
					Active_Function()
				end
			end

			module.Cache[MethodName] = nil

		else
			warn(`{MethodName} does not exist!`)
		end

	else

		local CapturedID = false

		for Method_Name,info in pairs(module.Cache) do

			if info[Unique_ID] ~= nil then
				CapturedID = true

				if Activate_Callback == true then
					info[Unique_ID].Callback()
				end

				module.Cache[Method_Name][Unique_ID] = nil

				local Empty = true

				for i,v in pairs(module.Cache[Method_Name]) do
					if i then
						Empty = false
					end
				end

				if Empty == true then
					module.Cache[Method_Name] = nil
				end

				break
			end

		end

		if CapturedID == false then
			warn(`{Unique_ID} is not in any methods!`)
		end

	end

end

module.Send = function(Player : Player, Method_Name : string, UnReliable : boolean, ...)
	if Method_Name == nil then return warn(`Method name was not given`) end

	if RunSerivce:IsServer() then
		if Player == nil then return warn(`Player was not given. Method Name: {Method_Name}`) end

		local DataFormat = {
			["Method"] = Method_Name,
			["Info"] = PackWire(...),
			["Timestamp"] = game.Workspace:GetServerTimeNow(),
		}

		if Player:GetAttribute("Client_Ready") == nil or Player:GetAttribute("Client_Ready") == false then
			CreateSendQueue(DataFormat, Player, UnReliable)
		else
			if UnReliable == true then
				space.packets.unrely.sendTo(DataFormat, Player)
			else
				space.packets.rely.sendTo(DataFormat, Player)
			end
		end

	else

		local DataFormat = {
			["Method"] = Method_Name,
			["Info"] = PackWire(...),
			["Timestamp"] = game.Workspace:GetServerTimeNow(),
		}

		if UnReliable == true then
			space.packets.unrely.send(DataFormat)
		else
			space.packets.rely.send(DataFormat)
		end

	end

end

module.SendToAll = function(Method_Name : string, UnReliable : boolean, ...)
	if Method_Name == nil then return warn(`Method name was not given`) end

	if RunSerivce:IsServer() then

		local DataFormat = {
			["Method"] = Method_Name,
			["Info"] = PackWire(...),
			["Timestamp"] = game.Workspace:GetServerTimeNow(),
		}

		if UnReliable == true then
			space.packets.unrely.sendToAll(DataFormat)
		else
			space.packets.rely.sendToAll(DataFormat)
		end

	else
		warn(`Only Server use this function!`)

	end

end

module.SendToAllExcept = function(Players : { Player | string }, Method_Name : string, UnReliable : boolean, ...)
	if Method_Name == nil then return warn(`Method name was not given`) end

	if RunSerivce:IsServer() then

		local DataFormat = {
			["Method"] = Method_Name,
			["Info"] = PackWire(...),
			["Timestamp"] = game.Workspace:GetServerTimeNow(),
		}

		if UnReliable == true then
			for _, plr in pairs(Players) do
				if typeof(plr) == "Instance" then
					space.packets.unrely.sendToAllExcept(DataFormat, plr)
				elseif typeof(plr) == "string" then
					if Players_Service:FindFirstChild(plr) then
						space.packets.unrely.sendToAllExcept(DataFormat, Players_Service:FindFirstChild(plr))
					end
				end
			end
		else
			for _, plr : Player in pairs(Players) do
				if typeof(plr) == "Instance" then
					space.packets.rely.sendToAllExcept(DataFormat, plr)
				elseif typeof(plr) == "string" then
					if Players_Service:FindFirstChild(plr) then
						space.packets.rely.sendToAllExcept(DataFormat, Players_Service:FindFirstChild(plr))
					end
				end
			end
		end

	else
		warn(`Only Server use this function!`)
	end

end

module.Invoke = function(Method_Name : string, ...)

	if RunSerivce:IsClient() then

		local dataformat = {
			["Method"] = Method_Name,
			["Info"] = table.pack(...),
			["Timestamp"] = game.Workspace:GetServerTimeNow(),
		}

		local value = space.queries.one.invoke(dataformat)

		return value
	end

end

module.BindableEvent = function(Method_Name : string, ...)
	module.CallListener(Method_Name, nil, true, nil, ...)
end

module.BindableFunction = function(Method_Name : string, Invoked : boolean, ...)
	local methodCache = module.Cache[Method_Name]

	if not methodCache then

		warn(`Could not find method: {Method_Name}`)

		local maxWait = 5
		local elapsed = 0
		local interval = 0.01

		while not methodCache and elapsed < maxWait do
			task.wait(interval)
			elapsed += interval
			methodCache = module.Cache[Method_Name]
		end

		print(`Found method!`)

		if not methodCache then
			warn(`BindableFunction: {Method_Name} does not exist after waiting {maxWait} seconds!`)
			return nil
		end
	end

	for Tag_ID, info in pairs(methodCache) do
		if info.Only_Bound == true and Invoked ~= true then
			return info.Callback(...)
		end

		if info.Only_Bound == false and Invoked == true then
			return info.Callback(...)
		end
	end

	warn(`BindableFunction: No valid callback found for {Method_Name}`)
	return nil
end

module.Activate = function(Script : ModuleScript | LocalScript)

	if CollectionService:HasTag(Script, "UsesNetHandler") then
		module.UsesNetworkHandler[Script] = true
	end
end

-- [ SETUP ]--
if RunSerivce:IsServer() then

	space.packets.rely.listen(function(data, Player : Player)
		module.CallListener(data.Method, Player, false, data.Timestamp, UnpackWire(data.Info))
	end)

	space.packets.unrely.listen(function(data, Player : Player)
		module.CallListener(data.Method, Player, false, data.Timestamp, UnpackWire(data.Info))
	end)

	space.queries.one.listen(function(data, Player : Player?)

		local Method = data.Method
		local Info = data.Info

		local value = module.BindableFunction(Method, true, Player, Info)

		local dataformat = {
			["Info"] = value,
		}

		return dataformat

	end)

	local Instances = CollectionService:GetTagged("UsesNetHandler")
	for i,mod_Script in ipairs(Instances) do
		local PlrInstance = mod_Script:FindFirstAncestorOfClass("Player")
		local Starter_Player = mod_Script:FindFirstAncestorOfClass("StarterPlayer")
		local StarterGui = mod_Script:FindFirstAncestorOfClass("StarterGui")
		local ReplicatedFirst = mod_Script:FindFirstAncestorOfClass("ReplicatedFirst")

		local clientOnlyHome = mod_Script:IsDescendantOf(ReplicatedStorage.Shared.Services)
			or mod_Script:IsDescendantOf(ReplicatedStorage.UI)

		local ignored = false
		local ancestor = mod_Script.Parent
		while ancestor and ancestor ~= game do
			if CollectionService:HasTag(ancestor, "IgnoreInit") then ignored = true break end
			ancestor = ancestor.Parent
		end

		if PlrInstance == nil and Starter_Player == nil and StarterGui == nil and ReplicatedFirst == nil and not clientOnlyHome and not ignored then
			if module.UsesNetworkHandler[mod_Script] == nil then
				module.UsesNetworkHandler[mod_Script] = false
			end
		end

	end

else

	space.packets.rely.listen(function(data)
		module.CallListener(data.Method, nil, false, data.Timestamp, UnpackWire(data.Info))
	end)

	space.packets.unrely.listen(function(data)
		module.CallListener(data.Method, nil, false, data.Timestamp, UnpackWire(data.Info))
	end)

	local Instances = CollectionService:GetTagged("UsesNetHandler")
	for i,mod_Script in ipairs(Instances) do
		local PlrInstance = mod_Script:FindFirstAncestorOfClass("Player")
		local Replicated = mod_Script:FindFirstAncestorOfClass("ReplicatedStorage")

		if (PlrInstance == Player or Replicated ~= nil) then
			if module.UsesNetworkHandler[mod_Script] == nil then
				module.UsesNetworkHandler[mod_Script] = false
			end
		end
	end

end

task.spawn(function()
	local KeepLooping = true

	local Time_Limit = 10
	local TimeNow = os.clock()

	while KeepLooping do

		local AllTrue = true

		for i,Activated : boolean in pairs(module.UsesNetworkHandler)  do
			if Activated == false then
				AllTrue = false
			end
		end

		if AllTrue == true then
			KeepLooping = false
			Queue_Mode = false
			break
		end

		if os.clock() - TimeNow >= Time_Limit then
			Queue_Mode = false
			print(`NetworkHandler was not successful, not all modules were activated. Auto broken due to time limit.`, module.UsesNetworkHandler)
			break
		end

		task.wait()
	end

	if RunSerivce:IsServer() then
		print(`NetworkHandler has loaded on Server!`)
		SuccessfullyLoaded = true
		KeepLooping = false
	else
		print(`NetworkHandler has loaded on Client!`)
		SuccessfullyLoaded = true
		KeepLooping = false
	end

end)

return module
