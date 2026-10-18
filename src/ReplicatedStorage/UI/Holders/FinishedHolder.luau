local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = {}
if RunService:IsServer() then return module end

local Squash = require(ReplicatedStorage.Shared.Modules.Core.Squash)

local Player = Players.LocalPlayer

-- [ FEEL ]-- STARTING VALUES, NOT TUNED.
local SLAM = { Time = 0.14, From = 2.3, Tilt = -12 }
local LAND = Vector2.new(1.45, 0.6)
local WOBBLE = { Angle = 8, Decay = 5, Speed = 24 }
local BURST_IN = 0.24     -- s the Burst pops up (overshooting)
local BURST_TWIST = -14
local BURST_SETTLE = 0.28
local HOLD = 1.45         -- s from the start till the fade
local FADE = 0.22
local GROW = 0.14         -- x its size both grow by over the fade
module.Duration = HOLD + FADE

-- [ REFS ]--
local Holder: Frame
local Finished: ImageLabel, Burst: ImageLabel
local FinishedScale: UIScale, BurstScale: UIScale
local Gradients: { UIGradient } = {}
local FinishedSquash: any

-- [ STATE ]--
local Ready = false
local StartedAt: number? = nil
local Landed = false
local Connection: RBXScriptConnection? = nil
local Wanted = false

local function EaseIn(x: number): number return x * x end
local function EaseOut(x: number): number return 1 - (1 - x) * (1 - x) end
local function EaseOutBack(x: number): number
	local y = x - 1
	return 1 + 2.7 * y * y * y + 1.7 * y * y
end

local function SetFade(alpha: number)
	local sequence = NumberSequence.new(math.clamp(alpha, 0, 1))
	for _, g in Gradients do g.Transparency = sequence end
end

local function Stop()
	if Connection then
		Connection:Disconnect()
		Connection = nil
	end
	StartedAt = nil
	if FinishedSquash then FinishedSquash:Rest() end
	Holder.Visible = false
end

local function Step()
	local start = StartedAt
	if not start then return end
	local e = os.clock() - start
	if e >= HOLD + FADE then
		Stop()
		return
	end

	if e < SLAM.Time then
		local p = e / SLAM.Time
		FinishedScale.Scale = SLAM.From + (1 - SLAM.From) * EaseIn(p)
		Finished.Rotation = SLAM.Tilt * (1 - EaseOut(p))
	else
		if not Landed then
			Landed = true
			FinishedScale.Scale = 1
			FinishedSquash:Pop(LAND)
		end
		local w = e - SLAM.Time
		Finished.Rotation = WOBBLE.Angle * math.exp(-WOBBLE.Decay * w) * math.sin(WOBBLE.Speed * w)
	end

	local burst = if e < BURST_IN then EaseOutBack(e / BURST_IN) else 1
	Burst.Rotation = BURST_TWIST * (1 - EaseOut(math.min(e / BURST_SETTLE, 1)))
	-- the fade, both growing a little
	if e > HOLD then
		local p = (e - HOLD) / FADE
		SetFade(EaseIn(p))
		local grow = 1 + GROW * EaseOut(p)
		if Landed then FinishedScale.Scale = grow end
		burst *= grow
	else
		SetFade(0)
	end
	BurstScale.Scale = math.max(burst, 0.001)
end

local function Begin()
	Stop()
	Holder.Visible = true
	StartedAt, Landed = os.clock(), false
	FinishedScale.Scale, Finished.Rotation = SLAM.From, SLAM.Tilt
	BurstScale.Scale, Burst.Rotation = 0.001, BURST_TWIST
	SetFade(0)
	Connection = RunService.RenderStepped:Connect(Step)
end

function module.Play()
	if Ready then Begin() else Wanted = true end
end

function module.Init()
	task.spawn(function()
		local gameGui = Player:WaitForChild("PlayerGui"):WaitForChild("GameGUI")
		Holder = gameGui:WaitForChild("Holder"):WaitForChild("FinishedHolder")
		local background = Holder:WaitForChild("Background")
		Burst = background:WaitForChild("Burst")
		Finished = background:WaitForChild("Finished")
		for _, image in { Burst, Finished } do
			local g = image:FindFirstChildOfClass("UIGradient")
			if not g then
				g = Instance.new("UIGradient")
				g.Parent = image
			end
			table.insert(Gradients, g)
		end
		if Finished.ZIndex <= Burst.ZIndex then Finished.ZIndex = Burst.ZIndex + 1 end   -- the word over the Burst
		FinishedScale = Instance.new("UIScale")
		FinishedScale.Name = "SlamScale"
		FinishedScale.Parent = Finished
		BurstScale = Instance.new("UIScale")
		BurstScale.Name = "BurstScale"
		BurstScale.Parent = Burst
		FinishedSquash = Squash.new(Finished)
		Ready = true
		Holder.Visible = false   -- asserted, not assumed
		if Wanted then
			Wanted = false
			Begin()
		end
	end)
end

return module
