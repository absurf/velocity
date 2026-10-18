local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)

local Service = {}
type Service = typeof(Service)

local TRIES = 3
local RETRY = 2   -- s between tries

local STRIP = { "LuaSourceContainer", "Animator", "BallSocketConstraint", "NoCollisionConstraint", "Camera", "BindableFunction" }

-- [ STATE ]--
local Started = false
local Folder: Folder
local Building: { [Player]: boolean } = {}

-- // PRIVATE //--

local function Stripped(inst: Instance): boolean
	for _, class in STRIP do
		if inst:IsA(class) then return true end
	end
	return false
end

-- The avatar as a drawn body (header).
local function DisplayOnly(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then return false end
	for _, d in model:GetDescendants() do
		if d.Parent and Stripped(d) then d:Destroy() end
	end
	local joints = 0
	for _, joint in model:GetDescendants() do
		if joint:IsA("AnimationConstraint") then
			local a0, a1 = joint.Attachment0, joint.Attachment1
			if a0 and a1 then
				local motor = Instance.new("Motor6D")
				motor.Name = joint.Name
				motor.Part0, motor.Part1 = a0.Parent :: BasePart, a1.Parent :: BasePart
				motor.C0, motor.C1 = a0.CFrame, a1.CFrame
				motor.Parent = a1.Parent
				joints += 1
			end
			joint:Destroy()
		elseif joint:IsA("Motor6D") then
			joints += 1
		end
	end
	if joints == 0 then return false end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = part == root
			part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
			part.Massless = true
		end
	end
	root.Transparency = 1
	humanoid.EvaluateStateMachine = false
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	local lowest = math.huge
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = model:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then lowest = math.min(lowest, foot.Position.Y - foot.Size.Y / 2) end
	end
	local height = root.Position.Y - lowest
	if height ~= height or height < 0.5 or height > 20 then height = humanoid.HipHeight + root.Size.Y / 2 end
	model:SetAttribute("RootHeight", height)
	model.PrimaryPart = root
	return true
end

local function Build(userId: number): Model?
	for try = 1, TRIES do
		local ok, result = pcall(function()
			local description = Players:GetHumanoidDescriptionFromUserIdAsync(userId)
			return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
		end)
		if ok and result then return result end
		warn(("[SpeedAvatarServer] %d's avatar, try %d: %s"):format(userId, try, tostring(result)))
		if try < TRIES then task.wait(RETRY) end
	end
	return nil
end

local function Dress(player: Player)
	local userId = player.UserId
	if userId <= 0 or Building[player] then return end
	Building[player] = true
	local model = Build(userId)
	Building[player] = nil
	if not model then return end
	if not player.Parent or not DisplayOnly(model) then
		model:Destroy()
		return
	end
	model.Name = tostring(userId)
	model:SetAttribute("UserId", userId)
	local old = Folder:FindFirstChild(model.Name)
	if old then old:Destroy() end
	model.Parent = Folder   -- whole: a screen gets it in one piece
end

-- // PUBLIC //--

function Service.BuildFrom(_self: Service, key: string, description: HumanoidDescription): boolean
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn(("[SpeedAvatarServer] %s's outfit: %s"):format(key, tostring(model)))
		return false
	end
	if not Folder or not DisplayOnly(model) then
		model:Destroy()
		return false
	end
	model.Name = key
	local old = Folder:FindFirstChild(key)
	if old then old:Destroy() end
	model.Parent = Folder
	return true
end

function Service.Remove(_self: Service, key: string)
	local model = Folder and Folder:FindFirstChild(key)
	if model then model:Destroy() end
end

function Service.Init(_self: Service)
	if Started then return end
	Started = true
	Folder = ReplicatedStorage:FindFirstChild(SpeedConfig.Avatars) :: Folder
	if not Folder then
		Folder = Instance.new("Folder")
		Folder.Name = SpeedConfig.Avatars
		Folder.Parent = ReplicatedStorage
	end
	Players.PlayerAdded:Connect(Dress)
	for _, player in Players:GetPlayers() do task.spawn(Dress, player) end
	Players.PlayerRemoving:Connect(function(player)
		local model = Folder:FindFirstChild(tostring(player.UserId))
		if model then model:Destroy() end
	end)
end

return Service :: Service
