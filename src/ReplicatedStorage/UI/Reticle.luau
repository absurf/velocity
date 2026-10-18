local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Reticle = {}
if RunService:IsServer() then return Reticle end

local Player = Players.LocalPlayer

-- [ FEEL ]-- STARTING VALUES, NOT TUNED.
local FADE_IN, FADE_OUT = 0.12, 0.1          -- s
local LAND = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)   -- it lands from POP x
local LEAVE = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SHRINK = 0.75                           -- x it shrinks to as it goes
local WHIRL = 110                             -- degrees the outline whirls in through
local SPIN = { runner = 140, point = 45, search = 25 }   -- degrees a second the outline turns
local POP = { runner = 1.7, point = 1.3, search = 1.15 }
local DIM = { search = 0.6 }                  -- the most a state shows (SEARCH sits dim)
local GLIDE = 28
local KICK = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)   -- a new lock: the dot from 1.5 x
local BADGE_DELAY, BADGE_SLIDE = 0.06, 0.35

-- [ STATE ]--
local Gui: ScreenGui? = nil
local Kinds: { [string]: any } = {}

-- // PRIVATE //--

local function Gradient(guiObject: GuiObject): UIGradient
	local g = guiObject:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	g.Parent = guiObject
	return g
end

local function Build(): boolean
	if Gui and Gui.Parent then return true end
	local source = StarterGui:FindFirstChild("ScreenGui")
	local playerGui = Player:FindFirstChild("PlayerGui")
	if not (source and playerGui) then return false end
	local gui = source:Clone()
	gui.Name = "SpeedReticle"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = true
	local example = gui:FindFirstChild("Example")
	local badgeTemplate = example and example:FindFirstChild("KeybindHolder")
	if badgeTemplate then badgeTemplate.Parent = nil end   -- (a template: each state gets its own)
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") then child.Visible = false end
	end

	local ground = gui:FindFirstChild("GroundReticle")
	if not (ground and ground:FindFirstChild("Outline", true)) then ground = example end
	for kind, frame in { runner = gui:FindFirstChild("Redreticle"), point = ground, search = gui:FindFirstChild("GrayReticle") } do
		local outline = frame and frame:FindFirstChild("Outline", true)
		if not (frame and outline) then continue end
		local k: any = { Frame = frame, Alpha = 0, Want = 0, Spin = 0, Whirl = 0, Pos = nil, Grads = {}, Shown = false, Kind = kind }
		k.Outline = outline
		k.Dot = frame:FindFirstChild("Dot", true)
		k.Scale = Instance.new("UIScale")
		k.Scale.Parent = frame
		k.DotScale = Instance.new("UIScale")
		if k.Dot then k.DotScale.Parent = k.Dot end
		for _, piece in { k.Outline, k.Dot } do
			if piece then table.insert(k.Grads, Gradient(piece)) end
		end
		if badgeTemplate and kind ~= "search" then
			local badge = badgeTemplate:Clone()
			badge.Parent = frame
			k.Badge = badge
			k.BadgeHome = badge.Position
			k.Text = badge:FindFirstChild("KeybindText")
			local red, blue = badge:FindFirstChild("Red"), badge:FindFirstChild("Blue")
			if red then red.Visible = kind == "runner" end
			if blue then blue.Visible = kind ~= "runner" end
			if k.Text then   -- (the key's label over its backdrop)
				k.Text.ZIndex = math.max(k.Text.ZIndex, (red and red.ZIndex or 1) + 1, (blue and blue.ZIndex or 1) + 1)
			end
			k.BadgeGrads = {}
			for _, piece in { red, blue, k.Text } do
				if piece then table.insert(k.BadgeGrads, Gradient(piece)) end
			end
			k.BadgeAlpha = 0
		end
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		if not frame:FindFirstChildOfClass("UIAspectRatioConstraint") then   -- (the Example has none: kept square)
			local square = Instance.new("UIAspectRatioConstraint")
			square.AspectRatio = 1
			square.Parent = frame
		end
		Kinds[kind] = k
	end
	gui.Parent = playerGui
	Gui = gui
	return true
end

local function Fade(grads: { UIGradient }, alpha: number)
	local seq = NumberSequence.new(1 - alpha)
	for _, g in grads do g.Transparency = seq end
end

local function Show(k, at: Vector2)
	k.Shown = true
	k.Frame.Visible = true
	k.Pos = at
	k.Whirl = -WHIRL
	k.LandAt = os.clock()
	k.Scale.Scale = POP[k.Kind] or 1.3
	TweenService:Create(k.Scale, LAND, { Scale = 1 }):Play()
	if k.Kind == "runner" and k.Dot then   -- (the dot pops in as it closes on them)
		k.DotScale.Scale = 0.2
		TweenService:Create(k.DotScale, KICK, { Scale = 1 }):Play()
	end
	if k.Badge then
		k.BadgeAlpha = 0
		k.Badge.Position = k.BadgeHome + UDim2.fromScale(BADGE_SLIDE, 0)
		TweenService:Create(k.Badge, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, BADGE_DELAY), { Position = k.BadgeHome }):Play()
	end
end

local function Hide(k)
	k.Shown = false
	TweenService:Create(k.Scale, LEAVE, { Scale = SHRINK }):Play()
end

local function Step(dt: number)
	for kind, k in Kinds do
		if not k.Shown and k.Alpha <= 0 then
			if k.Frame.Visible then k.Frame.Visible = false end
			continue
		end
		-- the fade
		local target = if k.Shown then (DIM[kind] or 1) else 0
		local rate = if k.Shown then 1 / FADE_IN else 1 / FADE_OUT
		local alpha = if k.Alpha < target then math.min(k.Alpha + dt * rate, target) else math.max(k.Alpha - dt * rate, target)
		if alpha ~= k.Alpha then
			k.Alpha = alpha
			Fade(k.Grads, alpha)
		end
		if k.Badge then
			local badgeTarget = if k.Shown and os.clock() - (k.LandAt or 0) >= BADGE_DELAY then 1 else 0
			local b = if k.BadgeAlpha < badgeTarget then math.min(k.BadgeAlpha + dt * rate, 1) else math.max(k.BadgeAlpha - dt * rate, badgeTarget)
			if b ~= k.BadgeAlpha then
				k.BadgeAlpha = b
				Fade(k.BadgeGrads, b)
			end
		end
		-- the outline: whirls in, then turns
		k.Whirl += (0 - k.Whirl) * math.min(dt * 12, 1)
		k.Spin = (k.Spin + dt * (SPIN[kind] or 60)) % 360
		if k.Outline then k.Outline.Rotation = k.Spin + k.Whirl end
		-- it glides after its target
		if k.Pos and k.Goal then
			k.Pos = k.Pos:Lerp(k.Goal, 1 - math.exp(-dt * GLIDE))
			k.Frame.Position = UDim2.fromOffset(k.Pos.X, k.Pos.Y)
		end
	end
end

-- // PUBLIC //--

function Reticle.Set(kind: string?, at: Vector2?, key: string?)
	if not Build() then return end
	for name, k in Kinds do
		local want = name == kind and at ~= nil
		if want then
			k.Goal = at
			if not k.Shown then Show(k, at :: Vector2) end
			if key and k.Text and k.Text.Text ~= key then k.Text.Text = key end
		elseif k.Shown then
			Hide(k)
		end
	end
end

function Reticle.Lock()
	local k = Kinds.runner
	if not (k and k.Shown) then return end
	k.DotScale.Scale = 1.5
	TweenService:Create(k.DotScale, KICK, { Scale = 1 }):Play()
	k.Whirl -= 90   -- (a spin on: it whirls back to rest)
end

function Reticle.Init()
	RunService.RenderStepped:Connect(Step)
end

return Reticle
