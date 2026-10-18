local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = {}
if RunService:IsServer() then return module end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local Squash = require(ReplicatedStorage.Shared.Modules.Core.Squash)

local Player = Players.LocalPlayer
local MAP = SpeedConfig.Hud.Map

local ARRIVE = Vector2.new(0.45, 0.45)
local OVERTAKE = Vector2.new(1.35, 0.7)
local MOVE = 0.002
local SIMPLIFY = 0.05

local Z = { Edge = 1, Road = 2, Mark = 3, Head = 10, Mine = 11 }

-- [ REFS ]--
local Background: Frame
local Window: Frame?
local Track: Frame?   -- the drawing, made here

-- [ STATE ]--
local Ready = false
local Wanted = nil    -- the CourseTrack last asked for
local Drawn = nil     -- the one drawn
local DrawnAspect = 0
local Follow = (MAP.Follow and MAP.Follow.Enabled) == true
local DrawnFollow = Follow
local Fit = nil
local Heads: { [any]: { Frame: Frame, Image: ImageLabel, Squash: Squash.Squash } } = {}
local Thumbs: { [number]: string } = {}
local Runners = {}

local function Flat(v: Vector3): Vector2
	return Vector2.new(v.X, v.Z)
end

local function ToMap(position: Vector3): Vector2
	local p = Flat(position) - Fit.Origin
	local s = Vector2.new(p:Dot(Fit.Right), -p:Dot(Fit.Forward))
	return Vector2.new(0.5, 0.5 / Fit.Aspect) + (s - Fit.Center) * Fit.Scale
end

-- Map units -> the Track frame's Scale.
local function ToScale(m: Vector2): UDim2
	return UDim2.fromScale(m.X, m.Y * Fit.Aspect)
end

local function Piece(name: string, color: Color3, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = z
	frame.Parent = Track
	return frame
end

local function Bar(name: string, a: Vector2, b: Vector2, width: number, color: Color3, z: number)
	local d = b - a
	local frame = Piece(name, color, z)
	frame.Position = ToScale((a + b) / 2)
	frame.Size = UDim2.fromScale(d.Magnitude + width, width * Fit.Aspect)
	frame.Rotation = math.deg(math.atan2(d.Y, d.X))
	return frame
end

local function Simplify(points: { Vector2 }, tolerance: number): { Vector2 }
	local keep = { [1] = true, [#points] = true }
	local function walk(first: number, last: number)
		local a, b = points[first], points[last]
		local ab = b - a
		local length = ab.Magnitude
		local worst, at = 0, nil
		for i = first + 1, last - 1 do
			local p = points[i]
			local d = if length > 1e-9 then math.abs(ab.X * (a.Y - p.Y) - ab.Y * (a.X - p.X)) / length else (p - a).Magnitude
			if d > worst then worst, at = d, i end
		end
		if at and worst > tolerance then
			keep[at] = true
			walk(first, at)
			walk(at, last)
		end
	end
	walk(1, #points)
	local out = {}
	for i, p in points do
		if keep[i] then table.insert(out, p) end
	end
	return out
end

local function Gate(name: string, track, along: number, color: Color3)
	local point, way = track:PointAt(along)
	local a = ToMap(point)
	local ahead = ToMap(point + way * 10) - a
	if ahead.Magnitude < 1e-6 then return end
	local across = Vector2.new(-ahead.Y, ahead.X).Unit * (MAP.Gate / 2)
	local bar = Bar(name, a - across, a + across, MAP.Road * 0.55, color, Z.Mark)
	local stroke = Instance.new("UIStroke")
	stroke.Color = MAP.EdgeColor
	stroke.Thickness = 1
	stroke.Parent = bar
end

local function Aspect(): number
	local size = (Window or Background).AbsoluteSize
	if size.X > 0 and size.Y > 0 then return size.X / size.Y end
	local constraint = Background.Parent and Background.Parent:FindFirstChildOfClass("UIAspectRatioConstraint")
	return if constraint then constraint.AspectRatio else 1
end

local function Draw()
	if Track then Track:Destroy() end
	Track = nil
	Fit = nil
	Drawn, DrawnAspect, DrawnFollow = Wanted, Aspect(), Follow
	local track = Wanted
	if not track then return end
	local frame = Instance.new("Frame")
	frame.Name = "Track"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 1
	frame.Parent = Window or Background
	Track = frame

	local points = track.Points
	local origin = Flat(points[1])
	local way = Flat(points[#points]) - origin
	local forward = if way.Magnitude > 1e-3 then way.Unit else Vector2.new(0, -1)
	local right = Vector2.new(-forward.Y, forward.X)
	local lo, hi = Vector2.one * math.huge, -Vector2.one * math.huge
	for _, point in points do
		local p = Flat(point) - origin
		local s = Vector2.new(p:Dot(right), -p:Dot(forward))
		lo, hi = lo:Min(s), hi:Max(s)
	end
	local aspect = DrawnAspect
	local span = (hi - lo):Max(Vector2.one)
	local scale = if Follow then 1 / MAP.Follow.Span
		else math.min((1 - 2 * MAP.Padding) / span.X, (1 - 2 * MAP.Padding) / aspect / span.Y)
	Fit = { Origin = origin, Forward = forward, Right = right, Center = (lo + hi) / 2, Scale = scale, Aspect = aspect }
	local mapped = {}
	for i, point in points do mapped[i] = ToMap(point) end
	mapped = Simplify(mapped, MAP.Road * SIMPLIFY)
	for i = 2, #mapped do
		Bar("Edge", mapped[i - 1], mapped[i], MAP.Edge, MAP.EdgeColor, Z.Edge)
		Bar("Road", mapped[i - 1], mapped[i], MAP.Road, MAP.RoadColor, Z.Road)
	end
	for i, along in track.LapEnds do Gate("Lap" .. i, track, along, MAP.LapColor) end
	Gate("Start", track, 0, MAP.FinishColor)
	Gate("Finish", track, track.Length, MAP.FinishColor)

	for key, head in Heads do
		head.Squash:Rest()
		head.Frame:Destroy()
		Heads[key] = nil
	end
end

local function Thumbnail(userId: number, image: ImageLabel)
	if Thumbs[userId] then
		image.Image = Thumbs[userId]
		return
	end
	task.spawn(function()
		local ok, content = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok and content then
			Thumbs[userId] = content
			if image.Parent then image.Image = content end
		end
	end)
end

local function Head(runner)
	local head = Heads[runner.Key]
	if head then return head end
	local frame = Instance.new("Frame")
	frame.Name = "Head_" .. tostring(runner.Key)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(MAP.Icon, MAP.Icon * Fit.Aspect)
	frame.ZIndex = if runner.Mine then Z.Mine else Z.Head
	local image = Instance.new("ImageLabel")
	image.Name = "Face"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundColor3 = MAP.EdgeColor
	image.ZIndex = frame.ZIndex
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = image
	local stroke = Instance.new("UIStroke")
	stroke.Color = if runner.Mine then MAP.MineStroke else MAP.OtherStroke
	stroke.Thickness = if runner.Mine then 2.5 else 1.5
	stroke.Parent = image
	if runner.Bot then stroke.Color = SpeedConfig.Bots.Colors[runner.Bot.Tier] or stroke.Color end
	if runner.Bot and not runner.UserId then
		image.BackgroundColor3 = SpeedConfig.Bots.Colors[runner.Bot.Tier] or MAP.EdgeColor
		local letter = Instance.new("TextLabel")
		letter.Name = "Initial"
		letter.BackgroundTransparency = 1
		letter.Size = UDim2.fromScale(1, 1)
		letter.Font = Enum.Font.GothamBlack
		letter.TextScaled = true
		letter.TextColor3 = Color3.new(1, 1, 1)
		letter.Text = string.sub(tostring(runner.Bot.Name or "?"), 1, 1)
		letter.ZIndex = frame.ZIndex
		letter.Parent = image
	end
	image.Parent = frame
	frame.Parent = Track
	head = { Frame = frame, Image = image, Squash = Squash.new(image) }
	Heads[runner.Key] = head
	if runner.UserId then Thumbnail(runner.UserId, image) end
	head.Squash:Pop(ARRIVE)
	return head
end

local function Paint()
	if not Ready then return end
	if Wanted ~= Drawn or Follow ~= DrawnFollow or math.abs(Aspect() - DrawnAspect) > 0.01 then Draw() end
	if not Fit then return end
	local seen = {}
	local mine = nil
	for _, runner in Runners do
		seen[runner.Key] = true
		local head = Head(runner)
		local at = ToScale(ToMap(runner.Position))
		if runner.Mine then mine = at end
		local was = head.Frame.Position
		if math.abs(at.X.Scale - was.X.Scale) > MOVE or math.abs(at.Y.Scale - was.Y.Scale) > MOVE then head.Frame.Position = at end
	end

	if Follow and mine and Track then
		local anchor = MAP.Follow.Anchor
		local x, y = 0.5 + anchor.X - mine.X.Scale, 0.5 + anchor.Y - mine.Y.Scale
		local was = Track.Position
		if math.abs(x - was.X.Scale) > MOVE / 2 or math.abs(y - was.Y.Scale) > MOVE / 2 then
			Track.Position = UDim2.fromScale(x, y)
		end
	end
	for key, head in Heads do
		if not seen[key] then
			head.Squash:Rest()
			head.Frame:Destroy()
			Heads[key] = nil
		end
	end
end

function module.SetTrack(track)
	Wanted = track
	if Ready then Paint() end
end

function module.SetRunners(list)
	Runners = list or {}
	Paint()
end

function module.PopMine()
	local head = Heads["me"]
	if head then head.Squash:Pop(OVERTAKE) end
end

function module.SetFollow(on: boolean)
	Follow = on == true
	Paint()
end

function module.Init()
	task.spawn(function()
		local gameGui = Player:WaitForChild("PlayerGui"):WaitForChild("GameGUI")
		local holder = gameGui:WaitForChild("Holder"):WaitForChild("MapHolder")
		Background = holder:WaitForChild("Background")

		local constraint = holder:FindFirstChildOfClass("UIAspectRatioConstraint")
		if constraint then constraint.DominantAxis = Enum.DominantAxis.Width end
		local w = MAP.Window or { 0, 0, 1, 1 }
		local window = Instance.new("Frame")
		window.Name = "Window"
		window.BackgroundTransparency = 1
		window.ClipsDescendants = true
		window.Position = UDim2.fromScale(w[1], w[2])
		window.Size = UDim2.fromScale(w[3] - w[1], w[4] - w[2])
		window.ZIndex = 1
		window.Parent = Background
		Window = window
		Ready = true
		Paint()
	end)
end

return module
