-- [ SERVICES ]--
local HTTPSService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Easings = require(script.Easings)

local module = {

	["TweenNumberSequence_Cache"] = {

	},
}

-- [ FUNCTIONS ]--
local function EvaluateNumberSequence(sequence: NumberSequence, time: number): number
	if time <= 0 then
		return sequence.Keypoints[1].Value
	elseif time >= 1 then
		return sequence.Keypoints[#sequence.Keypoints].Value
	end

	for i = 1, #sequence.Keypoints - 1 do
		local a = sequence.Keypoints[i]
		local b = sequence.Keypoints[i + 1]

		if time >= a.Time and time <= b.Time then
			local alpha = (time - a.Time) / (b.Time - a.Time)
			return a.Value + (b.Value - a.Value) * alpha
		end
	end

	return sequence.Keypoints[#sequence.Keypoints].Value
end

local function LerpNumberSequence(startSeq: NumberSequence, endSeq: NumberSequence, alpha: number): NumberSequence
	local timesMap = {}

	-- Collect all unique time points
	for _, kp in ipairs(startSeq.Keypoints) do
		timesMap[kp.Time] = true
	end
	for _, kp in ipairs(endSeq.Keypoints) do
		timesMap[kp.Time] = true
	end

	local times = {}
	for t in pairs(timesMap) do
		table.insert(times, t)
	end
	table.sort(times)

	local keypoints = {}
	for _, t in ipairs(times) do
		local startVal = EvaluateNumberSequence(startSeq, t)
		local endVal = EvaluateNumberSequence(endSeq, t)
		local lerpedVal = startVal + (endVal - startVal) * alpha
		table.insert(keypoints, NumberSequenceKeypoint.new(t, lerpedVal))
	end

	return NumberSequence.new(keypoints)
end

local function Letters(str : string)
	return string.sub(str,1,8)
end

-- [ MODULE FUNCTIONS ]--

module.GetTableLength = function(tbl: table): number
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

module.GenerateID = function(Curly_Braces : boolean)
	local ID = HTTPSService:GenerateGUID(Curly_Braces or false)
	ID = Letters(ID)

	return ID
end

module.CloneTable = function(Table : any)
	-- Define the new table for the copy
	local copy = {}

	-- Loop through the original table to clone
	for key, value in Table do

		copy[key] = type(value) == "table" and module.CloneTable(value) or value
	end

	return copy
end

module.ReplaceTableValues = function(Table1 : { [a] : any }, Table2 : { [a] : any }, DisableCheck : boolean)

	for key,value in pairs(Table1) do

		if Table2[key] ~= nil then

			if DisableCheck == true or typeof(Table2[key]) == typeof(value) then

				if typeof(value) == "table" then
					-- warn("ITS A TABLE")

					module.ReplaceTableValues(value, Table2[key])
				else

					-- print(typeof(value))

					Table1[key] = Table2[key]

					-- warn("REPLACE VALUES!", Table1, Table2)
				end

			else
				print("Table 1 Key & Value: ", key, value,". Table 2 Key & Value: ",key, Table2[key])
			end

		end

	end

	-- warn("RETURNING ",Table1,Table2)

	return Table1
end

module.CheckBackwards = function(Character : Model, Target : Model)

	if Character == nil then return end
	if Target == nil then return end

	local Root : BasePart = Character:FindFirstChild("HumanoidRootPart")
	local Target_Root : BasePart = Target:FindFirstChild("HumanoidRootPart")

	local Dot = Root.CFrame.LookVector:Dot(Target_Root.CFrame.LookVector)

	local Backwards = true
	-- print(Dot)

	if Dot <= -0.2 then
		-- print("THE ENEMY IS FACING FORWARD")
		Backwards = false
	else
		-- print("THE ENEMY IS FACING BACKWARDS")
	end

	return Backwards
end

module.Position_OffsetToScale = function(Frame : Frame)

	local ScaleXPos = Frame.Position.X.Offset/Frame.Parent.AbsoluteSize.X + Frame.Position.X.Scale
	local ScaleYPos = Frame.Position.Y.Offset/Frame.Parent.AbsoluteSize.Y  + Frame.Position.Y.Scale

	return UDim2.new(ScaleXPos,0,ScaleYPos, 0)
end

module.Position_ScaleToOffset = function(Frame : Frame)

	local OffsetXPos = Frame.Position.X.Scale*Frame.Parent.AbsoluteSize.X + Frame.Position.X.Offset
	local OffsetYPos = Frame.Position.Y.Scale*Frame.Parent.AbsoluteSize.Y + Frame.Position.Y.Offset

	return UDim2.new(0, OffsetXPos, 0, OffsetYPos)
end

module.Size_OffsetToScale = function(Frame : Frame)
	local Viewport_Size = Frame.Parent.AbsoluteSize
	local LB_Size = Frame.AbsoluteSize

	return UDim2.new(LB_Size.X/Viewport_Size.X,0,LB_Size.Y/Viewport_Size.Y, 0)
end

module.Size_ScaleToOffset = function(Frame : Frame)
	local LB_Size = Frame.AbsoluteSize
	return UDim2.new(0, LB_Size.X, 0, LB_Size.Y)
end

module.CheckForMovers = function(Character: Model, CheckOtherObjects: boolean, Array_LookAt: {string}, BlackList: boolean)
	local rootPart = Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return {} end

	local ValidClasses = {
		"LinearVelocity",
		"AngularVelocity",
		"AlignPosition",
		"AlignOrientation",
		"VectorForce",
		"Torque",
		"LineForce",
		"BodyForce",
		"BodyPosition",
		"BodyVelocity"
	}

	-- Step 1: Create the filter list
	local FilterList = {}
	if Array_LookAt and #Array_LookAt > 0 then
		for _, name in ipairs(Array_LookAt) do
			if table.find(ValidClasses, name) then
				table.insert(FilterList, name)
			end
		end
	else
		FilterList = ValidClasses
	end

	local FoundMovers = {}

	local function IsValidMover(className: string)
		local isInList = table.find(FilterList, className)
		return BlackList and not isInList or not BlackList and isInList
	end

	-- Step 3: Scan relevant objects
	local function ScanObject(obj)
		for _, child in pairs(obj:GetChildren()) do
			if table.find(ValidClasses, child.ClassName) and IsValidMover(child.ClassName) then
				table.insert(FoundMovers, child)
			end
		end
	end

	if CheckOtherObjects then
		for _, descendant in pairs(Character:GetDescendants()) do
			ScanObject(descendant)
		end
	else
		ScanObject(rootPart)
	end

	if #FoundMovers == 0 then
		FoundMovers = false
	end

	return FoundMovers
end

module.ReturnEasing = function(EasingName : string, Value : number)

	if Easings[EasingName] ~= nil then
		return Easings[EasingName](Value)
	else
		warn(`{EasingName} does not exist in Easings!`)
		return nil
	end

end

module.ChangeCollisionGroup = function(Character : Model, CollisionGroup : string)
	if Character == nil then return end

	for i,v in pairs(Character:GetDescendants()) do
		if v:IsA("BasePart") then
			v.CollisionGroup = CollisionGroup
		end

	end

end

module.TweenBeamTransparencyIn = function(beam: Beam, startTransparency: number, duration: number, easingStyle: string)

	-- Capture original transparency
	local originalTransparency = beam.Transparency

	local startKeypoints = {}
	for _, keypoint in ipairs(originalTransparency.Keypoints) do
		table.insert(startKeypoints, NumberSequenceKeypoint.new(keypoint.Time, startTransparency, keypoint.Envelope))
	end

	-- Set beam to start transparency
	beam.Transparency = NumberSequence.new(startKeypoints)

	-- Tween to original transparency
	local tweenID = module.TweenNumberSequence(beam, "Transparency", originalTransparency, duration, easingStyle)

	return tweenID
end

module.TweenNumberSequence =  function(instance, property: string, target: NumberSequence, duration: number, easingStyle: string, callback: (() -> ())?)
	local start = instance[property]
	local elapsed = 0

	local easingFunction = Easings[easingStyle]
	if not easingFunction then

		easingFunction = function(x) return x end -- linear fallback
	end

	local ID = module.GenerateID()

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local rawAlpha = math.clamp(elapsed / duration, 0, 1)
		local easedAlpha = easingFunction(rawAlpha)

		local lerped = LerpNumberSequence(start, target, easedAlpha)
		instance[property] = lerped

		if rawAlpha >= 1 then
			connection:Disconnect()
			module.TweenNumberSequence_Cache[ID] = nil
			if callback then callback() end
		end
	end)

	local info = {
		["Cleanup"] = function()
			connection:Disconnect()
			module.TweenNumberSequence_Cache[ID] = nil
		end,

	}

	module.TweenNumberSequence_Cache[ID] = info

	return ID
end

module.EndTweenNumberSequence = function(ID : string)

	if module.TweenNumberSequence_Cache[ID] ~= nil then
		module.TweenNumberSequence_Cache[ID].Cleanup()
	end

end

module.CountTable = function(tbl: table): number
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

return module
