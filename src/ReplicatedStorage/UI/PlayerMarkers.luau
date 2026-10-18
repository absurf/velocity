local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local PlayerMarkers = {}
if RunService:IsServer() then return PlayerMarkers end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local GUIController = require(script.Parent.GUIController)

local Player = Players.LocalPlayer

local SIZE = 0.1
local PROXIMITY = 260
local SCALE = { Near = 1, Far = 0.75, FarAt = PROXIMITY }
local START_GRACE = 4
local OFFSCREEN = false
local HEAD = 6
local LIFT = 7
local STEM_MIN = 0.15
local NEAR = 8
local EDGE = 0.07
local POP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHRINK = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HEADSHOT = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"

-- [ STATE ]--
local Enabled = true
local Gui: ScreenGui? = nil
local Template: Frame? = nil
local Geo = { Aspect = 1, HolderTop = 0.4127, HolderH = 1.0867 }
local Markers: { [any]: any } = {}
local Pending: { any } = {}

-- // PRIVATE //--

local function Setup(): boolean
	if Gui and Gui.Parent and Template then return true end
	local source = StarterGui:FindFirstChild("PlayerMarker")
	local playerGui = Player:FindFirstChild("PlayerGui")
	local background = source and source:FindFirstChild("Background")
	if not (source and playerGui and background) then return false end

	local holder = background:FindFirstChild("NodeHolder") :: Frame?
	local ratio = background:FindFirstChildOfClass("UIAspectRatioConstraint")
	Geo.Aspect = if ratio then ratio.AspectRatio else 1
	if holder then
		Geo.HolderTop = holder.Position.Y.Scale - holder.Size.Y.Scale * holder.AnchorPoint.Y - 0.5
		Geo.HolderH = holder.Size.Y.Scale
	end
	local gui = source:Clone()
	gui.Name = "PlayerMarkers"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -2
	gui.Enabled = true
	Template = gui:FindFirstChild("Background") :: Frame
	Template.Visible = false
	gui.Parent = playerGui
	Gui = gui
	return true
end

local function HeadView(avatar: string?, parent: Instance): ViewportFrame?
	local folder = ReplicatedStorage:FindFirstChild(SpeedConfig.Avatars or "SpeedAvatars")
	local model = avatar and folder and folder:FindFirstChild(avatar)
	if not model then
		local human = ReplicatedStorage:FindFirstChild("Assets")
		human = human and human:FindFirstChild("Speed")
		human = human and human:FindFirstChild("Human")
		model = human and human:FindFirstChild("Rig")
	end
	local head = model and model:FindFirstChild("Head") :: BasePart?
	if not (model and head) then return nil end
	local view = Instance.new("ViewportFrame")
	view.Name = "Face"
	view.BackgroundTransparency = 1
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.5, 0.5)
	view.Size = UDim2.fromScale(1, 1)
	view.Ambient = Color3.fromRGB(170, 170, 170)
	view.LightColor = Color3.new(1, 1, 1)
	view.LightDirection = Vector3.new(-0.4, -0.6, -1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = view

	local copy = Instance.new("Model")
	local face = head:Clone()
	for _, d in face:GetChildren() do
		if d:IsA("JointInstance") or d:IsA("LuaSourceContainer") then d:Destroy() end
	end

	local colors = model:FindFirstChildOfClass("BodyColors")
	if colors then
		face.Color = colors.HeadColor3
		colors:Clone().Parent = copy
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local own = humanoid:Clone()
		own.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		own.Parent = copy
	end
	face.Parent = copy
	for _, accessory in model:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle") :: BasePart?
		local weld = handle and handle:FindFirstChildWhichIsA("JointInstance")
		if handle and weld and ((weld :: any).Part0 == head or (weld :: any).Part1 == head) then
			local part = handle:Clone()
			for _, d in part:GetChildren() do
				if d:IsA("JointInstance") or d:IsA("Attachment") or d:IsA("LuaSourceContainer") then d:Destroy() end
			end
			part.Parent = copy
		end
	end
	copy.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local size = math.max(face.Size.X, face.Size.Y)
	local at = face.Position + Vector3.new(0, size * 0.18, 0)   -- (the face, a touch high: no shoulders)
	camera.CFrame = CFrame.lookAt(at + face.CFrame.LookVector * size * 3.1 + Vector3.new(0, size * 0.25, 0), at)
	camera.Parent = view
	view.CurrentCamera = camera
	view.Parent = parent
	return view
end

local function SetFace(marker, runner)
	local id = runner.UserId
	local key = if type(id) == "number" and id > 0 then "u" .. id else "a" .. tostring(runner.Avatar)
	if marker.FaceKey == key then return end
	marker.FaceKey = key
	if marker.View then
		marker.View:Destroy()
		marker.View = nil
	end
	local icon = marker.Icon :: ImageLabel?
	if not icon then return end
	if type(id) == "number" and id > 0 then
		icon.Image = HEADSHOT:format(id)
		icon.ImageTransparency = 0
	else
		icon.ImageTransparency = 1
		marker.Avatar = runner.Avatar
		table.insert(Pending, marker)
	end
end

local function NewMarker(key: any)
	local frame = (Template :: Frame):Clone()
	frame.Name = "Marker" .. tostring(key)
	frame.Visible = false
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	local pop = Instance.new("UIScale")
	pop.Scale = 0
	pop.Parent = frame
	local icon = frame:FindFirstChild("Icon", true) :: ImageLabel?
	if icon then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = icon
	end
	local holder = frame:FindFirstChild("NodeHolder")
	frame.Parent = Gui
	return { Frame = frame, Pop = pop, Icon = icon, Holder = holder, Node = holder and holder:FindFirstChild("Node"),
		Place = frame:FindFirstChild("Placement", true), Shown = false }
end

local function Drop(key: any)
	local marker = Markers[key]
	if not marker then return end
	marker.Frame:Destroy()
	Markers[key] = nil
end

local function Show(marker, on: boolean, instant: boolean?)
	if marker.Shown == on then return end
	marker.Shown = on
	if marker.Tween then marker.Tween:Cancel() end
	if on then   -- (it appears: a little pop, Back out)
		marker.Frame.Visible = true
		marker.Pop.Scale = 0.4
		marker.Tween = TweenService:Create(marker.Pop, POP, { Scale = 1 })
		marker.Tween:Play()
	elseif instant or not marker.Frame.Visible then
		marker.Frame.Visible = false
	else   -- (it goes: shrinks away)
		local tween = TweenService:Create(marker.Pop, SHRINK, { Scale = 0 })
		marker.Tween = tween
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not marker.Shown then marker.Frame.Visible = false end
		end)
		tween:Play()
	end
end

-- // PUBLIC //--

function PlayerMarkers.Update(runners: { any }, runFor: number?)
	if not Setup() then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local view = camera.ViewportSize
	local eye = camera.CFrame.Position
	local hidden = not Enabled or GUIController.HudHidden()
	local starting = runFor == nil or runFor < START_GRACE

	local perStud = view.Y / (2 * math.tan(math.rad(camera.FieldOfView) / 2))
	local seen = {}
	for _, runner in runners do
		local key = runner.Key
		if key == nil or not runner.Position then continue end
		seen[key] = true
		local marker = Markers[key]
		if not marker then
			marker = NewMarker(key)
			Markers[key] = marker
		end
		local tip = runner.Position + Vector3.new(0, HEAD, 0)
		local distance = (tip - eye).Magnitude
		if hidden or starting or distance < NEAR or distance > PROXIMITY then
			Show(marker, false, hidden or starting)
			continue
		end
		SetFace(marker, runner)
		if marker.Place and marker.PlaceText ~= runner.Place then
			marker.PlaceText = runner.Place
			marker.Place.Text = tostring(runner.Place or "")
		end
		local t = math.clamp(distance / SCALE.FarAt, 0, 1)
		local h = math.round(SIZE * view.Y * (SCALE.Near + (SCALE.Far - SCALE.Near) * t))
		local frame = marker.Frame
		if marker.H ~= h then
			marker.H = h
			frame.Size = UDim2.fromOffset(math.round(h * Geo.Aspect), h)
		end
		local z = math.clamp(1000 - math.floor(distance / 10), 1, 1000)   -- (nearer in front)
		if marker.Z ~= z then
			marker.Z = z
			frame.ZIndex = z
		end
		local p = camera:WorldToViewportPoint(tip)
		local depth = p.Z
		local x, y = p.X, p.Y
		local margin = EDGE * view.Y + h / 2
		local onScreen = depth > 0 and x > margin and x < view.X - margin and y > margin and y < view.Y - margin
		if onScreen then

			local holderH = Geo.HolderH * h
			local stem = math.clamp(LIFT * perStud / math.max(depth, 0.1), STEM_MIN * holderH, holderH)
			frame.Position = UDim2.fromOffset(x, y - Geo.HolderTop * h - stem)
			if marker.Holder then marker.Holder.Visible = true end
			if marker.Node then marker.Node.Position = UDim2.fromScale(0.5, 0.5 + stem / holderH - 1) end
		elseif not OFFSCREEN then
			Show(marker, false)   -- (off the screen: no marker)
			continue
		else

			local cx, cy = view.X / 2, view.Y / 2
			local dx, dy = x - cx, y - cy
			if depth <= 0 then dx, dy = -dx, -dy end
			if math.abs(dx) < 1e-3 and math.abs(dy) < 1e-3 then dy = 1 end
			local sx = (cx - margin) / math.max(math.abs(dx), 1e-3)
			local sy = (cy - margin) / math.max(math.abs(dy), 1e-3)
			local s = math.min(sx, sy)
			frame.Position = UDim2.fromOffset(cx + dx * s, cy + dy * s)
			if marker.Holder then marker.Holder.Visible = false end
		end
		Show(marker, true)
	end
	for key in Markers do
		if not seen[key] then Drop(key) end
	end
	local marker = table.remove(Pending, 1)
	if marker and marker.Frame.Parent and marker.Icon and not marker.View then
		marker.View = HeadView(marker.Avatar, marker.Icon.Parent)
	end
end

function PlayerMarkers.SetEnabled(on: boolean)
	Enabled = on
	if not on then
		for _, marker in Markers do Show(marker, false) end
	end
end

return PlayerMarkers
