local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local module = {}
if RunService:IsServer() then return module end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local TextRoll = require(ReplicatedStorage.Shared.Modules.Core.TextRoll)

local Player = Players.LocalPlayer
local LOADING = SpeedConfig.Loading

-- [ FEEL ]-- STARTING VALUES, NOT TUNED.
local APPEAR = 0.45       -- s each part fades / slides in
local LEAVE = 0.4         -- s each part fades / slides away
local STAGGER = 0.08      -- s between the parts
local RISE = 0.05
local FOLLOW = 6
local CREEP = 0.35        -- /s it moves at least (while behind)
local SHINE = { Time = 0.85, Rest = 1.5, From = -0.9, To = 0.9 }
local TICK_EDGE = 0.18
local TICK_POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TICK_POP_FROM = 1.3
local TIP_FADE = 0.22     -- s a tip fades out, then the next in
local TIP_TEXT = 0.2
local TIP_MIN_TEXT = 8
local READY_HOLD = 0.35   -- s at 100% before it fades away

-- [ REFS ]--
local Gui: ScreenGui
local Parts: { any } = {}
local Shine: UIGradient?
local ShineBase: NumberSequence?
local TipText: TextLabel, TipBox: Frame, TipCap: UITextSizeConstraint, TipGradient: UIGradient
local TickHolder: Frame
local Ticks: { any } = {}
local CompletedImage, InProgressImage = "", ""
local Percentage: TextLabel
local Status: TextLabel
local StatusRoll: any
local BarPart: any

-- [ STATE ]--
local Ready = false
local Phase: string? = nil           -- nil (off), "In", "Up", "Out"
local PhaseAt = 0
local Target, Shown = 0, 0
local StatusText = ""
local TipIndex = 0
local TipAt = 0
local TipFit = false
local ShineAt = 0
local HideWanted = false
local ReadyAt: number? = nil

-- // PRIVATE //--

local function EaseOut(x: number): number return 1 - (1 - x) ^ 3 end
local function EaseIn(x: number): number return x * x * x end
local function EaseInOut(x: number): number return if x < 0.5 then 2 * x * x else 1 - (-2 * x + 2) ^ 2 / 2 end

local function Through(base: NumberSequence, alpha: number): NumberSequence
	if alpha <= 0 then return base end
	if alpha >= 1 then return NumberSequence.new(1) end
	local points = {}
	for _, k in base.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(k.Time, 1 - (1 - alpha) * (1 - k.Value)))
	end
	return NumberSequence.new(points)
end

local function Fill(f: number): NumberSequence
	if f <= 0 then return NumberSequence.new(1) end
	if f >= 1 then return NumberSequence.new(0) end
	local a, b = math.max(f - TICK_EDGE, 0), f
	local points = { NumberSequenceKeypoint.new(0, if a > 0 then 0 else (0 - (f - TICK_EDGE)) / TICK_EDGE) }
	if a > 0.001 then table.insert(points, NumberSequenceKeypoint.new(a, 0)) end
	if b > a + 0.001 and b < 0.999 then table.insert(points, NumberSequenceKeypoint.new(b, 1)) end
	table.insert(points, NumberSequenceKeypoint.new(1, 1))
	return NumberSequence.new(points)
end

local function GradientOf(object: GuiObject): UIGradient
	local g = object:FindFirstChildOfClass("UIGradient")
	if not g then
		g = Instance.new("UIGradient")
		g.Parent = object
	end
	return g
end

local function Part(frame: GuiObject?, dir: number, delay: number, skip: { [Instance]: boolean }?)
	local part = { Frame = frame, Rest = frame and frame.Position, Dir = dir, Delay = delay, Gradients = {} }
	if frame then
		for _, d in frame:GetDescendants() do
			if (d:IsA("ImageLabel") or d:IsA("TextLabel")) and not (skip and skip[d]) then
				local g = GradientOf(d)
				table.insert(part.Gradients, { Gradient = g, Base = g.Transparency })
			end
		end
	end
	table.insert(Parts, part)
	return part
end

local function Presence(part): number
	local e = os.clock() - PhaseAt
	if Phase == "In" then
		return EaseOut(math.clamp((e - part.Delay) / APPEAR, 0, 1))
	elseif Phase == "Out" then
		local last = 0
		for _, p in Parts do last = math.max(last, p.Delay) end
		return 1 - EaseIn(math.clamp((e - (last - part.Delay)) / LEAVE, 0, 1))
	elseif Phase == "Up" then
		return 1
	end
	return 0
end

local function NextTip()
	local tips = LOADING.Tips
	if #tips == 0 then return end
	local pick = math.random(1, #tips)
	if #tips > 1 and pick == TipIndex then pick = pick % #tips + 1 end
	TipIndex = pick
	TipText.Text = tips[pick]

	TipCap.MaxTextSize = math.max(TIP_MIN_TEXT, math.round(TipBox.Parent.AbsoluteSize.Y * TIP_TEXT))
	TipFit = true
end

local function BuildTicks()
	for _, t in Ticks do t.Image:Destroy() end
	table.clear(Ticks)
	local template = TickHolder:FindFirstChild("TickCompleted")
	if not template then return end
	local layout = TickHolder:FindFirstChildOfClass("UIListLayout")
	local width = TickHolder.AbsoluteSize.X
	local tick = template.AbsoluteSize.X
	local gap = if layout then layout.Padding.Scale * width + layout.Padding.Offset else 0
	local count = if width > 0 and tick > 0 then math.floor((width - gap) / (tick + gap) + 1e-6) else 17
	count = math.clamp(count, 1, 40)
	for i = 1, count do
		local image = template:Clone()
		image.Name = "Tick" .. i
		image.LayoutOrder = i
		image.Visible = true
		local g = GradientOf(image)
		g.Transparency = NumberSequence.new(1)
		local scale = Instance.new("UIScale")
		scale.Parent = image
		image.Parent = TickHolder
		table.insert(Ticks, { Image = image, Gradient = g, Scale = scale, State = "Empty" })
	end
	for _, name in { "TickCompleted", "TickInProgress" } do
		local t = TickHolder:FindFirstChild(name)
		if t then t.Visible = false end
	end
end

local function Off()
	Phase = nil
	Gui.Enabled = false
	HideWanted, ReadyAt = false, nil
end

local function Step(dt: number)
	if not Phase then return end
	local now = os.clock()
	-- the phases
	if Phase == "In" and now - PhaseAt > APPEAR + STAGGER * #Parts then Phase, PhaseAt = "Up", now end
	if Phase == "Out" and now - PhaseAt > LEAVE + STAGGER * #Parts then
		Off()
		return
	end

	if Shown < Target then
		Shown = math.min(Target, Shown + math.max((Target - Shown) * FOLLOW, CREEP) * dt)
	end
	Percentage.Text = ("%d%%"):format(math.floor(Shown * 100 + 1e-6))

	if HideWanted and Phase == "Up" then
		if Shown >= 1 and not ReadyAt then ReadyAt = now end
		if ReadyAt and now - ReadyAt >= READY_HOLD then Phase, PhaseAt = "Out", now end
	end
	-- the ticks
	local count = #Ticks
	for i, t in Ticks do
		local f = math.clamp(Shown * count - (i - 1), 0, 1)
		local state = if f >= 1 then "Done" elseif f > 0 then "Filling" else "Empty"
		if state ~= t.State then
			t.State = state
			t.Image.Image = if state == "Done" then CompletedImage else InProgressImage
			if state == "Done" then
				t.Scale.Scale = TICK_POP_FROM
				TweenService:Create(t.Scale, TICK_POP, { Scale = 1 }):Play()
			end
		end
		t.Fill = f
	end
	-- each part: where it is, how see-through
	for _, part in Parts do
		local p = Presence(part)
		if part.Frame and part.Rest then part.Frame.Position = part.Rest + UDim2.fromScale(0, part.Dir * RISE * (1 - p)) end
		local alpha = 1 - p
		for _, g in part.Gradients do g.Gradient.Transparency = Through(g.Base, alpha) end
		if part == BarPart then
			for _, t in Ticks do t.Gradient.Transparency = Through(Fill(t.Fill or 0), alpha) end
		end
		part.Alpha = alpha
	end

	local tipAlpha = 0
	local e = now - TipAt
	if e > LOADING.TipEvery then
		TipAt, e = now, 0
		NextTip()
	end
	if e < TIP_FADE then tipAlpha = 1 - e / TIP_FADE end   -- (coming in)
	if LOADING.TipEvery - e < TIP_FADE then tipAlpha = 1 - (LOADING.TipEvery - e) / TIP_FADE end   -- (going)
	if TipFit and TipText.AbsoluteSize.Y > TipBox.AbsoluteSize.Y + 1 and TipCap.MaxTextSize > TIP_MIN_TEXT then
		TipCap.MaxTextSize -= 1
		tipAlpha = 1
	else
		TipFit = false
	end
	local tipPart = Parts[3]
	TipGradient.Transparency = NumberSequence.new(1 - (1 - (tipPart and tipPart.Alpha or 0)) * (1 - tipAlpha))
	-- the title's shine: a sweep, a rest
	if Shine and ShineBase then
		local s = now - ShineAt
		local cycle = SHINE.Time + SHINE.Rest
		if s > cycle then ShineAt, s = now, 0 end
		local x = if s < SHINE.Time then SHINE.From + (SHINE.To - SHINE.From) * EaseInOut(s / SHINE.Time) else SHINE.From
		Shine.Offset = Vector2.new(x, Shine.Offset.Y)
		Shine.Transparency = Through(ShineBase, Parts[2].Alpha or 0)
	end
end

-- // PUBLIC //--

function module.Show()
	if not Ready then return end
	local now = os.clock()
	if Phase == "Up" or Phase == "In" then
		HideWanted, ReadyAt = false, nil
		return
	end
	Phase, PhaseAt = "In", now
	Target, Shown = 0, 0
	HideWanted, ReadyAt = false, nil
	Gui.Enabled = true
	StatusText = LOADING.Stages[1] and LOADING.Stages[1].Status or ""
	StatusRoll:Set(StatusText)
	for _, t in Ticks do
		t.State = "Empty"
		t.Fill = 0
		t.Scale.Scale = 1
	end
	TipAt, ShineAt = now, now + APPEAR
	NextTip()
	if #Ticks == 0 then task.defer(BuildTicks) end
	Step(0)
end

function module.Set(progress: number, status: string?)
	if type(progress) == "number" then Target = math.max(Target, math.clamp(progress, 0, 1)) end
	if status and status ~= StatusText and Ready then
		StatusText = status
		if Phase then StatusRoll:Swap(status, -1) else StatusRoll:Set(status) end
	end
end

function module.Hide()
	if not Phase then return end
	Target = 1
	HideWanted = true
	if LOADING.Ready then module.Set(1, LOADING.Ready) end
end

function module.Showing(): boolean
	return Phase ~= nil
end

function module.Init()
	task.spawn(function()
		local template = game:GetService("StarterGui"):WaitForChild("LoadingScreenGUI", 30)
		if not template then return end
		local playerGui = Player:WaitForChild("PlayerGui")
		Gui = template:Clone()
		Gui.Name = "LoadingScreenGUI"
		Gui.Enabled = false
		Gui.ResetOnSpawn = false
		Gui.IgnoreGuiInset = true
		Gui.DisplayOrder = 1000
		Gui.Parent = playerGui
		local holder = Gui:WaitForChild("Holder")
		local title = holder:WaitForChild("TitleHolder")
		local icon = title:WaitForChild("RunnersIcon")
		local shine = icon:FindFirstChild("RunnersShine")
		local tip = holder:WaitForChild("TipHolder")
		local bar = holder:WaitForChild("ProgressBarHolder")
		TickHolder = bar:WaitForChild("TickHolder")
		Percentage = bar:WaitForChild("PercentageHolder"):WaitForChild("Percentage")
		Status = bar:WaitForChild("Status")
		TipBox = tip:WaitForChild("TextHolder")
		TipText = TipBox:WaitForChild("Summary")
		local completed, inProgress = TickHolder:FindFirstChild("TickCompleted"), TickHolder:FindFirstChild("TickInProgress")
		CompletedImage = completed and completed.Image or ""
		InProgressImage = inProgress and inProgress.Image or CompletedImage
		-- the shine sweeps on its own gradient
		if shine then
			Shine = shine:FindFirstChildOfClass("UIGradient")
			ShineBase = Shine and Shine.Transparency
		end

		local top = TipText.Position.Y.Scale - TipText.AnchorPoint.Y * TipText.Size.Y.Scale
		TipText.AnchorPoint = Vector2.new(TipText.AnchorPoint.X, 0)
		TipText.Position = UDim2.new(TipText.Position.X.Scale, TipText.Position.X.Offset, top, TipText.Position.Y.Offset)
		TipText.Size = UDim2.new(TipText.Size.X.Scale, TipText.Size.X.Offset, 0, 0)
		TipText.TextWrapped, TipText.TextScaled = true, true
		TipText.TextYAlignment = Enum.TextYAlignment.Top
		TipText.AutomaticSize = Enum.AutomaticSize.Y
		TipCap = TipText:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
		TipCap.MinTextSize = 1
		TipCap.Parent = TipText
		TipGradient = GradientOf(TipText)

		local back = { Frame = nil, Dir = 0, Delay = 0, Gradients = { { Gradient = GradientOf(holder), Base = GradientOf(holder).Transparency } } }
		table.insert(Parts, back)
		Part(title, -1, STAGGER, { [shine or title] = true })
		Part(tip, 1, STAGGER * 2, { [TipText] = true })
		local skip = {}
		for _, t in TickHolder:GetChildren() do skip[t] = true end
		BarPart = Part(bar, 1, STAGGER * 3, skip)
		StatusRoll = TextRoll.new(Status)

		local known = {}
		for _, g in BarPart.Gradients do known[g.Gradient] = true end
		for _, d in Status:GetDescendants() do
			if d:IsA("UIGradient") and not known[d] then table.insert(BarPart.Gradients, { Gradient = d, Base = d.Transparency }) end
		end
		RunService.RenderStepped:Connect(Step)
		Ready = true
		task.defer(BuildTicks)
	end)
end

return module
