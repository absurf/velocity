local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = {}
if RunService:IsServer() then return module end

local TweenService = game:GetService("TweenService")

local Starting = require(ReplicatedStorage.Starting)
local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local Squash = require(ReplicatedStorage.Shared.Modules.Core.Squash)
local TextRoll = require(ReplicatedStorage.Shared.Modules.Core.TextRoll)

local Player = Players.LocalPlayer
local COUNT = SpeedConfig.Hud.Countdown

-- [ FEEL ]-- STARTING VALUES, NOT TUNED.
local FEEL = TextRoll.Feel
local WOBBLE = { Angle = 9, Decay = 5.5, Speed = 26 }
local BURST_SPIN = 40
local GO_SLAM = { Time = 0.12, From = 2.4, Tilt = -14 }   -- GO!'s, harder
local GO_LAND = Vector2.new(1.5, 0.55)
local GO_EXIT = 0.22     -- s GO! flies at you and fades...
local GO_GROW = 1.7      -- ...to this x its size
local BURST_IN = 0.28
local BURST_TWIST = -30
local BURST_OUT = 0.18
local LATE = 0.25

-- [ REFS ]--
local Holder: Frame
local IconHolder: Frame, Icon: ImageLabel
local Burst: ImageLabel
local SlamScale: UIScale, BurstScale: UIScale
local IconSquash: Squash.Squash
local Leaving: ImageLabel
local LeavingHolder: Frame
local Tweens: { Tween } = {}
local FramePixels = Vector2.new(200, 196)

-- [ STATE ]--
local Ready = false
local GoAt: number? = nil
local Beat: string? = nil   -- the picture showing: "3", "2", "1", "Go"
local BeatAt = 0            -- server time its beat began
local Landed = false
local WobbleAt: number? = nil   -- server time GO! landed
local Connection: RBXScriptConnection? = nil

local function EaseIn(x: number): number return x * x end
local function EaseOut(x: number): number return 1 - (1 - x) * (1 - x) end
local function EaseOutBack(x: number): number   -- past 1 and back
	local y = x - 1
	return 1 + 2.7 * y * y * y + 1.7 * y * y
end
local function EaseInBack(x: number): number    -- below 0 first
	return 2.7 * x * x * x - 1.7 * x * x
end

local function Dress(name: string): boolean
	local picture = Starting[name]
	if not picture then return false end
	IconSquash:Rest()
	local pixels = picture.Pixels or picture.Size
	Icon.Image = picture.Image
	Icon.Size = UDim2.fromScale(pixels.X.Offset / FramePixels.X, pixels.Y.Offset / FramePixels.Y)
	Icon.Position = UDim2.fromScale(0.5, 0.5)
	Icon.AnchorPoint = Vector2.new(0.5, 0.5)
	Icon.ImageTransparency = 0
	IconSquash:Capture()
	return true
end

local function Play(instance: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(instance, info, goal)
	table.insert(Tweens, tween)
	tween:Play()
end

local function StopTweens()
	for _, tween in Tweens do tween:Cancel() end
	table.clear(Tweens)
end

local function Below(rest: UDim2, size: UDim2, by: number): UDim2
	return rest + UDim2.new(0, 0, size.Y.Scale * by, size.Y.Offset * by)
end

local function Hide()
	GoAt, Beat, WobbleAt = nil, nil, nil
	if Connection then
		Connection:Disconnect()
		Connection = nil
	end
	StopTweens()
	IconSquash:Rest()
	SlamScale.Scale, IconHolder.Rotation = 1, 0
	BurstScale.Scale, Burst.Rotation = 1, 0
	Icon.Visible, Burst.Visible, Leaving.Visible = false, false, false
	Holder.Visible = false
end

local function BeatAtTime(goAt: number, t: number): (string?, number)
	if t < 0 then
		local n = math.ceil(-t / COUNT.Beat - 1e-9)
		if n > COUNT.Beats then return nil, 0 end
		return tostring(n), goAt - n * COUNT.Beat
	end
	return "Go", goAt
end

local function Step()
	local goAt = GoAt
	if not goAt then return end
	local now = workspace:GetServerTimeNow()
	local t = now - goAt
	if t >= COUNT.Go + GO_EXIT then
		Hide()
		return
	end
	local name, startAt = BeatAtTime(goAt, t)
	if not name then return end
	local go = name == "Go"
	if name ~= Beat then
		local previous = Beat
		Beat, BeatAt = name, startAt
		Holder.Visible = true
		local late = now - startAt > LATE
		StopTweens()

		if previous and not late and Icon.Visible then
			Leaving.Image, Leaving.Size, Leaving.AnchorPoint = Icon.Image, Icon.Size, Icon.AnchorPoint
			Leaving.Position, Leaving.ImageTransparency, Leaving.Visible = Icon.Position, Icon.ImageTransparency, true
			LeavingHolder.Rotation = IconHolder.Rotation
			Play(Leaving, FEEL.Out, { Position = Below(Icon.Position, Icon.Size, FEEL.Distance) })
			Play(Leaving, FEEL.FadeOut, { ImageTransparency = 1 })
		else
			Leaving.Visible = false
		end
		Icon.Visible = Dress(name)
		Burst.Visible = go
		SlamScale.Scale, IconHolder.Rotation = 1, 0
		WobbleAt = nil
		Landed = late or not go

		if not go and not late then
			local rest = Icon.Position
			Icon.Position, Icon.ImageTransparency = Below(rest, Icon.Size, -FEEL.Distance), 1
			Play(Icon, FEEL.In, { Position = rest })
			Play(Icon, FEEL.FadeIn, { ImageTransparency = 0 })
		end
	end
	local e = now - BeatAt
	if not go then return end
	if not Landed then
		if e >= GO_SLAM.Time then
			Landed, WobbleAt = true, now
			SlamScale.Scale, IconHolder.Rotation = 1, 0
			IconSquash:Pop(GO_LAND)
		else
			local p = e / GO_SLAM.Time
			SlamScale.Scale = GO_SLAM.From + (1 - GO_SLAM.From) * EaseIn(p)
			IconHolder.Rotation = GO_SLAM.Tilt * (1 - EaseOut(p))
		end
	end
	if WobbleAt then
		-- landed: a swing that dies away
		local w = now - WobbleAt
		IconHolder.Rotation = WOBBLE.Angle * math.exp(-WOBBLE.Decay * w) * math.sin(WOBBLE.Speed * w)
	end
	local burst = if e < BURST_IN then EaseOutBack(e / BURST_IN) else 1
	Burst.Rotation = BURST_TWIST * (1 - EaseOut(math.min(e / (COUNT.Go + GO_EXIT), 1))) + BURST_SPIN * e
	if e > COUNT.Go then
		local p = math.min((e - COUNT.Go) / GO_EXIT, 1)
		SlamScale.Scale = 1 + (GO_GROW - 1) * EaseIn(p)
		Icon.ImageTransparency = p
		burst = 1 - EaseInBack(math.min((e - COUNT.Go) / BURST_OUT, 1))
	end
	BurstScale.Scale = math.max(burst, 0.001)
end

local function Begin(goAt: number)
	Hide()
	GoAt = goAt
	Connection = RunService.RenderStepped:Connect(Step)
	Step()   -- already in a beat: it shows this frame
end

function module.Countdown(goAt: number)
	if type(goAt) ~= "number" or goAt ~= goAt then return end
	if Ready then Begin(goAt) else GoAt = goAt end
end

function module.Clear()
	if Ready then Hide() else GoAt = nil end
end

function module.Init()
	task.spawn(function()
		local gameGui = Player:WaitForChild("PlayerGui"):WaitForChild("GameGUI")
		Holder = gameGui:WaitForChild("Holder"):WaitForChild("StartingHolder")
		local background = Holder:WaitForChild("Background")
		Burst = background:WaitForChild("Burst")
		IconHolder = background:WaitForChild("IconHolder")
		Icon = IconHolder:WaitForChild("Icon")
		for _, layer in background:GetChildren() do
			if layer:IsA("ImageLabel") and layer ~= Burst and Starting[layer.Name] then layer.Visible = false end
		end
		local pixels = Starting.Burst and Starting.Burst.Pixels
		if pixels then FramePixels = Vector2.new(pixels.X.Offset, pixels.Y.Offset) end
		if IconHolder.ZIndex <= Burst.ZIndex then IconHolder.ZIndex = Burst.ZIndex + 1 end   -- the picture over the Burst

		LeavingHolder = IconHolder:Clone()
		LeavingHolder.Name = "LeavingHolder"
		for _, child in LeavingHolder:GetChildren() do
			if child:IsA("UIScale") or child:IsA("LuaSourceContainer") or (child:IsA("GuiObject") and child.Name ~= Icon.Name) then child:Destroy() end
		end
		Leaving = LeavingHolder:FindFirstChild(Icon.Name) :: ImageLabel
		Leaving.Name = "Leaving"
		Leaving.Visible = false
		LeavingHolder.Parent = IconHolder.Parent
		SlamScale = Instance.new("UIScale")
		SlamScale.Name = "SlamScale"
		SlamScale.Parent = IconHolder
		BurstScale = Instance.new("UIScale")
		BurstScale.Name = "BurstScale"
		BurstScale.Parent = Burst
		IconSquash = Squash.new(Icon)
		Ready = true
		local want = GoAt
		Hide()
		if want then Begin(want) end
	end)
end

return module
