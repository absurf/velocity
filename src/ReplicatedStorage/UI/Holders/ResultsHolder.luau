local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local module = {}
if RunService:IsServer() then return module end

local Places = require(ReplicatedStorage.Places)
local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)

local Player = Players.LocalPlayer

-- [ FEEL ]-- STARTING VALUES, NOT TUNED.
local ME_BACKDROP = "rbxassetid://116300018057014"
local OTHER_BACKDROP = "rbxassetid://139023957196393"
local STAGGER = 0.1
local SLIDE = 0.14
local SLIDE_TIME = 0.5   -- s it slides (quint out)
local WIPE_TIME = 0.45   -- s the sweep crosses the row (cubic out)
local SOFT = 0.22        -- the sweep's soft edge, x the row's width
local PLACE_GROW = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)   -- the place picture: 0, 0 -> its size
local OPEN = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHUT = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local SCROLL = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- [ REFS ]--
local Root: Frame
local Scroll: ScrollingFrame
local Template: Frame
local NextSummary: TextLabel
local OpenScale: UIScale
local FlashFrame: Frame
local Backend: any = nil

-- [ STATE ]--
local Ready = false
local Pending: { any }? = nil
local RaceId: number? = nil
local Rows: { [string]: any } = {}
local Animating: { any } = {}
local Opened, Dismissed = false, false
local Times = { NextAt = nil :: number?, Deadline = nil :: number? }
local MyKey: string? = nil
local ScrollTween: Tween? = nil
local HoldUntil = 0
local OpenQueued = false

-- // PRIVATE //--

local function EaseOutQuint(x: number): number return 1 - (1 - x) ^ 5 end
local function EaseOutCubic(x: number): number return 1 - (1 - x) ^ 3 end

local function FormatTime(t: number): string
	local minutes = math.floor(t / 60)
	return ("%d:%05.2f"):format(minutes, t - minutes * 60)
end

local function PlacePicture(place: number)
	for n = math.clamp(place, 1, 99), 1, -1 do
		local picture = Places[tostring(n)]
		if picture then return picture end
	end
	return nil
end

local function Sweep(edge: number, soft: number): NumberSequence
	local a, b = edge - soft, edge
	if b <= 0 then return NumberSequence.new(1) end
	if a >= 1 then return NumberSequence.new(0) end
	local function value(x: number): number return math.clamp((x - a) / math.max(soft, 1e-4), 0, 1) end
	local times = { 0 }
	for _, x in { math.clamp(a, 0, 1), math.clamp(b, 0, 1) } do
		if x > times[#times] + 1e-3 and x < 1 - 1e-3 then table.insert(times, x) end
	end
	table.insert(times, 1)
	local points = {}
	for _, x in times do table.insert(points, NumberSequenceKeypoint.new(x, value(x))) end
	return NumberSequence.new(points)
end

local function SetHidden(record)
	for _, g in record.Gradients do g.Gradient.Transparency = NumberSequence.new(1) end
end

local function Dress(record)
	local data, row = record.Data, record.Frame
	local mine = data.Key == MyKey
	row.Name = data.Key
	row.LayoutOrder = data.Place or 99
	local backdrop = row:FindFirstChild("Backdrop")
	if backdrop then backdrop.Image = if mine then ME_BACKDROP else OTHER_BACKDROP end
	local name = row:FindFirstChild("PlayerName")
	if name then name.Text = tostring(data.Name or "?") end
	local time = row:FindFirstChild("Time")
	if time then time.Text = if data.Time then FormatTime(data.Time) else "DNF" end
	local behind = row:FindFirstChild("TimeBehindFirst")
	if behind then behind.Text = if data.Time and record.First then ("+%.2f"):format(math.max(data.Time - record.First, 0)) else "" end
	local icon = row:FindFirstChild("PlayerIcon") and row.PlayerIcon:FindFirstChild("Icon")
	if icon then
		icon.Visible = data.UserId ~= nil
		if data.UserId then icon.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(data.UserId) end
	end
	local holder = row:FindFirstChild("PlacementHolder")
	local place = holder and holder:FindFirstChild("Icon")
	local picture = PlacePicture(data.Place or 99)
	if place and picture then
		place.Image = picture.Image
		record.PlaceSize = picture.Size
		place.Size = if record.Settled then picture.Size else UDim2.new(0, 0, 0, 0)   -- (nothing till its row lands)
		place.AnchorPoint = Vector2.new(0.5, 0.5)
		place.Position = UDim2.new(0.5, 0, 0.5, 0)
	end
end

local function NewRow(data, first: number?)
	local row = Template:Clone()
	local record = { Data = data, First = first, Frame = row, Pieces = {}, Gradients = {} }
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") then table.insert(record.Pieces, { Gui = child, Rest = child.Position }) end
	end
	local place = row:FindFirstChild("PlacementHolder") and row.PlacementHolder:FindFirstChild("Icon")
	for _, d in row:GetDescendants() do
		if d:IsA("UIGradient") and d.Parent and d.Parent:IsA("GuiObject") then

			table.insert(record.Gradients, { Gradient = d, Gui = d.Parent, Original = d.Transparency, Late = d.Parent == place })
		end
	end
	Dress(record)
	SetHidden(record)
	row.Visible = true
	row.Parent = Scroll
	record.Place = place
	return record
end

local function Measure(record): boolean
	local row = record.Frame
	local x, w = row.AbsolutePosition.X, row.AbsoluteSize.X
	if w < 2 then return false end
	for _, g in record.Gradients do
		local gx, gw = g.Gui.AbsolutePosition.X, g.Gui.AbsoluteSize.X
		g.From, g.Width = (gx - x) / w, math.max(gw / w, 1e-3)
	end
	return true
end

local function Reveal(record, delay: number)
	record.StartAt = os.clock() + delay
	record.Measured = false
	table.insert(Animating, record)
end

local function Settle(record)
	for _, piece in record.Pieces do piece.Gui.Position = piece.Rest end

	for _, g in record.Gradients do g.Gradient.Transparency = g.Original end
	record.Settled = true
	local place = record.Place
	if place and record.PlaceSize then
		place.Size = UDim2.new(0, 0, 0, 0)
		TweenService:Create(place, PLACE_GROW, { Size = record.PlaceSize }):Play()
	end
end

local function ShowMine()
	local mine = MyKey and Rows[MyKey]
	if not mine then return end
	local row = mine.Frame
	local top = row.AbsolutePosition.Y - Scroll.AbsolutePosition.Y + Scroll.CanvasPosition.Y
	local view = Scroll.AbsoluteSize.Y
	if top >= Scroll.CanvasPosition.Y and top + row.AbsoluteSize.Y <= Scroll.CanvasPosition.Y + view then return end
	local target = math.max(top - (view - row.AbsoluteSize.Y) / 2, 0)
	if ScrollTween then ScrollTween:Cancel() end
	ScrollTween = TweenService:Create(Scroll, SCROLL, { CanvasPosition = Vector2.new(0, target) })
	ScrollTween:Play()
end

local function Step()
	if not Root.Visible then return end
	-- the next race's count (the server's)
	local now = workspace:GetServerTimeNow()
	local target = Times.NextAt or (Times.Deadline and Times.Deadline + SpeedConfig.Race.Next)
	local text = if target then ("Next Race - %ds"):format(math.max(math.ceil(target - now), 0)) else "Next Race"
	if NextSummary.Text ~= text then NextSummary.Text = text end
	-- the rows coming in
	local clock = os.clock()
	for i = #Animating, 1, -1 do
		local record = Animating[i]
		local e = clock - record.StartAt
		if e < 0 then continue end
		if not record.Measured then
			record.Measured = Measure(record)
			if not record.Measured then continue end
			record.StartAt, e = clock, 0
		end
		local p = EaseOutQuint(math.min(e / SLIDE_TIME, 1))
		local w = EaseOutCubic(math.min(e / WIPE_TIME, 1))
		if p >= 1 and w >= 1 then
			table.remove(Animating, i)
			Settle(record)
			continue
		end
		local shift = UDim2.fromScale(-SLIDE * (1 - p), 0)
		for _, piece in record.Pieces do piece.Gui.Position = piece.Rest + shift end
		local edge = -SOFT + (1 + 2 * SOFT) * w
		for _, g in record.Gradients do
			if not g.Late then g.Gradient.Transparency = Sweep((edge - g.From) / g.Width, SOFT / g.Width) end
		end
	end
end

local function Open()
	if Opened or Dismissed then return end
	-- FINISHED! first (its fade, then this)
	local wait = HoldUntil - os.clock()
	if wait > 0 then
		if not OpenQueued then
			OpenQueued = true
			task.delay(wait, function()
				OpenQueued = false
				Open()
			end)
		end
		return
	end
	Opened = true
	Root.Visible = true
	OpenScale.Scale = 0.6
	TweenService:Create(OpenScale, OPEN, { Scale = 1 }):Play()
	if Backend then Backend:FreeCursor(true) end
	Scroll.CanvasPosition = Vector2.zero
	local list = {}
	for _, record in Rows do table.insert(list, record) end
	table.sort(list, function(a, b) return (a.Data.Place or 99) < (b.Data.Place or 99) end)
	for i, record in list do Reveal(record, 0.15 + (i - 1) * STAGGER) end
	task.delay(0.15 + #list * STAGGER + SLIDE_TIME, ShowMine)
end

local function Forget()
	for _, record in Rows do record.Frame:Destroy() end
	table.clear(Rows)
	table.clear(Animating)
	Opened, Dismissed, RaceId = false, false, nil

	Times.NextAt, Times.Deadline = nil, nil
end

local function Apply(payload, myKey: string)
	MyKey = myKey
	if payload.Closed then
		if payload.Race == RaceId then module.Close(true) end
		return
	end
	if payload.Race ~= RaceId then
		Forget()
		Root.Visible = false
		RaceId = payload.Race
	end
	Times.NextAt = if type(payload.NextAt) == "number" then payload.NextAt else nil
	Times.Deadline = if type(payload.Deadline) == "number" then payload.Deadline else nil
	local first = nil
	for _, data in payload.Rows or {} do
		if data.Time and (not first or data.Time < first) then first = data.Time end
	end
	local mine = false
	for _, data in payload.Rows or {} do
		if data.Key == myKey then mine = true end
		local record = Rows[data.Key]
		if not record then
			record = NewRow(data, first)
			Rows[data.Key] = record
			if Opened and Root.Visible then Reveal(record, 0) end   -- in live: just this one
		elseif record.Data.Time ~= data.Time or record.Data.Place ~= data.Place then
			record.Data, record.First = data, first
			Dress(record)
		end
	end
	if mine then Open() end
end

local function Grown(u: UDim2, f: number): UDim2
	return UDim2.new(u.X.Scale * f, u.X.Offset * f, u.Y.Scale * f, u.Y.Offset * f)
end

local function Wire(frame: GuiObject, button: GuiButton, grow: number, onActivated: () -> ())
	local rest = frame.Size
	local big = TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = Grown(rest, grow) })
	local small = TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Size = Grown(rest, 0.9) })
	local back = TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Size = rest })
	local hovering = false
	local function enter() hovering = true; big:Play() end
	local function leave() hovering = false; back:Play() end
	button.MouseEnter:Connect(enter)
	button.MouseLeave:Connect(leave)
	button.SelectionGained:Connect(enter)
	button.SelectionLost:Connect(leave)
	button.Activated:Connect(function()
		small:Play()
		onActivated()
	end)
	small.Completed:Connect(function() if hovering then big:Play() else back:Play() end end)
end

local function RaceAgain()
	if Backend then Backend:Request("raceagain") end
end

-- // PUBLIC //--

function module.Update(payload: any, myKey: string)
	if type(payload) ~= "table" then return end
	if not Ready then
		Pending = { payload, myKey }
		return
	end
	Apply(payload, myKey)
end

function module.Close(reset: boolean?)
	if not Ready then
		Pending = nil
		return
	end
	if Backend then Backend:FreeCursor(false) end
	if reset then
		Forget()
		HoldUntil, OpenQueued = 0, false   -- a new race: nothing to wait for
		Root.Visible = false
		return
	end
	Dismissed = true
	require(ReplicatedStorage.UI.GUIController).ShowHud()   -- the HUD back as it shuts
	local tween = TweenService:Create(OpenScale, SHUT, { Scale = 0 })
	tween.Completed:Connect(function()
		if Dismissed then Root.Visible = false end
	end)
	tween:Play()
end

function module.Showing(): boolean
	return Root ~= nil and Root.Visible
end

function module.HoldFor(seconds: number)
	HoldUntil = os.clock() + seconds
end

function module.Flash()
	if not FlashFrame then return end
	FlashFrame.BackgroundTransparency = 0.25
	FlashFrame.Visible = true
	local tween = TweenService:Create(FlashFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	tween.Completed:Connect(function() FlashFrame.Visible = false end)
	tween:Play()
end

function module.Init()
	task.spawn(function()
		local playerGui = Player:WaitForChild("PlayerGui")
		local gameGui = playerGui:WaitForChild("GameGUI")
		Root = gameGui:WaitForChild("Holder"):WaitForChild("ResultsHolder")
		local background = Root:WaitForChild("Background")
		Scroll = background:WaitForChild("MainHolder"):WaitForChild("ScrollingFrame")

		local best, most = nil, -1
		for _, child in Scroll:GetChildren() do
			if child.Name == "PlayerTemplate" and #child:GetDescendants() > most then best, most = child, #child:GetDescendants() end
		end
		if not best then
			warn("[ResultsHolder] no PlayerTemplate in the ScrollingFrame")
			return
		end
		Template = best:Clone()
		for _, child in Scroll:GetChildren() do
			if child.Name == "PlayerTemplate" then child:Destroy() end
		end

		local holder = Template:FindFirstChild("PlacementHolder")
		if holder then
			holder.BackgroundTransparency = 1
			local icon = holder:FindFirstChild("Icon")
			if icon then icon.BackgroundTransparency = 1 end
		end
		NextSummary = background:WaitForChild("NextRaceHolder"):WaitForChild("ImageButton"):WaitForChild("Summary")
		OpenScale = Instance.new("UIScale")
		OpenScale.Name = "OpenScale"
		OpenScale.Parent = Root
		Root.Visible = false
		-- the buttons
		local nextHolder = background.NextRaceHolder
		Wire(nextHolder, nextHolder.ImageButton, 1.05, RaceAgain)
		local againHolder = background:WaitForChild("RaceAgainHolder")
		Wire(againHolder, againHolder:WaitForChild("ImageButton"), 1.05, RaceAgain)
		local exit = background:WaitForChild("ExitButton")
		Wire(exit, exit, 1.1, function() module.Close(false) end)
		-- the crossing's flash: over everything
		local flashGui = Instance.new("ScreenGui")
		flashGui.Name = "SpeedFinishFlash"
		flashGui.IgnoreGuiInset = true
		flashGui.ResetOnSpawn = false
		flashGui.DisplayOrder = 50
		FlashFrame = Instance.new("Frame")
		FlashFrame.Size = UDim2.fromScale(1, 1)
		FlashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
		FlashFrame.BackgroundTransparency = 1
		FlashFrame.BorderSizePixel = 0
		FlashFrame.Visible = false
		FlashFrame.Parent = flashGui
		flashGui.Parent = playerGui
		Backend = require(ReplicatedStorage.Shared.Services.SpeedService.SpeedServiceClient)
		RunService.RenderStepped:Connect(Step)
		Ready = true
		if Pending then
			local p = Pending
			Pending = nil
			Apply(p[1], p[2])
		end
	end)
end

return module
