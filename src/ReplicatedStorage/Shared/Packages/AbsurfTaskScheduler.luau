-- [ SERVICES ]--
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- [ UTILITY MODULES ]--
local AbsurfUtility = require(script.Parent.AbsurfUtility)

local module = {
	["Cache"] = {},
}

-- [ TIME SCALE ]--
local TimeScale = 1

function module.SetTimeScale(scale: number)
	assert(type(scale) == "number" and scale >= 0, "TimeScale must be a number >= 0")
	TimeScale = math.clamp(scale, 0, 10)

end

function module.GetTimeScale()
	return TimeScale
end

-- [ MODULE FUNCTIONS ]--

function module.RemoveTask(Unique_ID : string, Activate_Callback : boolean)
	if Unique_ID == nil then return warn("No Unique_ID was given.") end

	if module.Cache[Unique_ID] ~= nil then
		if Activate_Callback == true then
			if module.Cache[Unique_ID][1] == "Timer" then
				local function Time_Amount()
					local Show_Time
					if module.Cache[Unique_ID][6] == true then
						Show_Time = module.Cache[Unique_ID][3]
					else
						Show_Time = module.Cache[Unique_ID][4] - module.Cache[Unique_ID][3]
					end
					return Show_Time
				end
				module.Cache[Unique_ID][2](Time_Amount(), true)
			else
				module.Cache[Unique_ID][2]()
			end
		end
		module.Cache[Unique_ID] = nil
	end
end

function module.ModifyTask(Unique_ID : string, Values)
	if Unique_ID == nil then return warn("No Unique_ID was given.") end
	if module.Cache[Unique_ID] ~= nil then
		for Index : number,Val_Info in pairs(Values) do
			if typeof(Index) == "number" then
				if Index == 1 or Index == 2 then
					warn("Unable to modify Class_Name or Callback")
					continue
				end
				if module.Cache[Unique_ID][Index] ~= nil then
					if typeof(module.Cache[Unique_ID][Index]) == typeof(Val_Info) then
						module.Cache[Unique_ID][Index] = Val_Info
					else

					end
				else

				end
			end
		end
	end
end

function module.ReturnTaskProperties(Unique_ID : string)
	if Unique_ID == nil then return warn("No Unique_ID was given.") end
	return module.Cache[Unique_ID]
end

-- ✅ UPDATED: Added IgnoreTimeScale
function module.Delay(Delay_Time : number, Callback : () -> void, priority : number, IgnoreTimeScale : boolean)
	if typeof(Callback) ~= "function" then return warn("Callback is not a function.") end
	local Unique_ID = AbsurfUtility.GenerateID()
	-- Index 8 = IgnoreTimeScale
	module.Cache[Unique_ID] = {"Delay", Callback, 0, Delay_Time or 1, nil, nil, priority or 0, IgnoreTimeScale or false}
	return Unique_ID
end

-- ✅ UPDATED: Added IgnoreTimeScale
function module.Add(Callback : (dt : number) -> void, priority : number, IgnoreTimeScale : boolean)
	if typeof(Callback) ~= "function" then return warn("Callback is not a function.") end
	local Unique_ID = AbsurfUtility.GenerateID()
	-- Index 8 = IgnoreTimeScale
	module.Cache[Unique_ID] = {"Add", Callback, nil, nil, nil, nil, priority or 0, IgnoreTimeScale or false}
	return Unique_ID
end

-- ✅ UPDATED: Added IgnoreTimeScale
function module.Timer(Time_Amount : number, Speed_Multiplier : number, Increasing : boolean, Callback : (delta : number, Finished : boolean) -> void, priority : number, IgnoreTimeScale : boolean)
	if typeof(Callback) ~= "function" then return warn("Callback is not a function.") end
	Speed_Multiplier = Speed_Multiplier or 1
	local Unique_ID = AbsurfUtility.GenerateID()
	-- Index 8 = IgnoreTimeScale
	module.Cache[Unique_ID] = {"Timer", Callback, 0, Time_Amount or 1, Speed_Multiplier, Increasing or false, priority or 0, IgnoreTimeScale or false}
	return Unique_ID
end

-- ✅ UPDATED: Added IgnoreTimeScale
function module.Repeat(Interval : number, Repeat_Amount : number, Speed_Multiplier : number, Callback : (Repeat_Amount : number) -> void, priority : number, IgnoreTimeScale : boolean)
	if typeof(Callback) ~= "function" then return warn("Callback is not a function.") end
	Speed_Multiplier = Speed_Multiplier or 1
	local Unique_ID = AbsurfUtility.GenerateID()
	-- Index 8 = IgnoreTimeScale
	module.Cache[Unique_ID] = {"Repeat", Callback, 0, Interval or 1, Repeat_Amount or 1, Speed_Multiplier, priority or 0, IgnoreTimeScale or false}
	return Unique_ID
end

-- [ SETUP ]--
RunService.Heartbeat:Connect(function(dt)
	local Scaled_DT = dt * TimeScale -- Pre-calculate the scaled time

	local ids = {}
	for id in pairs(module.Cache) do table.insert(ids,id) end
	table.sort(ids,function(a,b)
		return (module.Cache[a][7] or 0) < (module.Cache[b][7] or 0)
	end)

	for _,ID in ipairs(ids) do
		local info = module.Cache[ID]
		if not info then continue end

		local Use_Time = (info[8] == true) and dt or Scaled_DT

		if info[1] == "Delay" then
			if info[3] >= info[4] then
				module.Cache[ID] = nil
				info[2]()
			else
				info[3] += Use_Time
			end

		elseif info[1] == "Timer" then
			local function Time_Amount()
				local Show_Time
				if info[6] == true then
					Show_Time = info[3]
				else
					Show_Time = info[4] - info[3]
				end
				return Show_Time
			end
			if info[3] >= info[4] then
				module.Cache[ID] = nil
				info[2](Time_Amount(), true)
			else
				info[3] += Use_Time * info[5]
				info[2](Time_Amount(), false)
			end

		elseif info[1] == "Repeat" then
			if info[3] <= info[4] then
				info[3] += Use_Time * info[6]
			else
				info[3] = 0
				if info[5] <= 0 then
					module.Cache[ID] = nil
				else
					info[2](info[5])
					info[5] -= 1
				end
			end

		elseif info[1] == "Add" then
			info[2](Use_Time)
		end
	end
end)

return module
