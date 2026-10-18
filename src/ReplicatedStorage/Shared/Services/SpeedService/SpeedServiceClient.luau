local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Service = {}
if RunService:IsServer() then return Service end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local ControlsConfig = require(ReplicatedStorage.Shared.Modules.Configs.ControlsConfig)
local SpeedSim = require(ReplicatedStorage.Shared.Modules.Speed.SpeedSim)
local InputService = require(ReplicatedStorage.Shared.Services.InputService.InputServiceClient)
local BotBrain = require(ReplicatedStorage.Shared.Modules.Speed.BotBrain)
local Generated = require(ReplicatedStorage.Shared.Modules.Speed.Courses.Generated)
local CameraRig = require(script.Parent.SpeedCameraClient)
local Effects = require(script.Parent.SpeedEffectsClient)
local BallView = require(script.Parent.SpeedBallClient)
local HumanView = require(script.Parent.SpeedHumanClient)
local Hud = require(ReplicatedStorage.UI.Holders.SpeedHudHolder)
local RunnerPack = require(ReplicatedStorage.Shared.Modules.Speed.RunnerPack)
local Perf = require(ReplicatedStorage.Shared.Modules.Speed.SpeedPerf)
local Runners = require(script.Parent.SpeedRunnersClient)

local Player = Players.LocalPlayer

-- [ STATE ]--
local Started = false
local Ready = false
local Movement: any = nil
local CameraRigInstance: any, EffectsInstance: any, Ball: any, Human: any, HudInstance: any = nil, nil, nil, nil, nil
local Body = "Human"
local Paused = false
local HudVisible = true
local LastRender = 0
local LastFrame: number? = nil
local Held = { Dive = false, FastRun = false, UseItem = false }
local HitLog = {}
local Callbacks: { State: ((buffer) -> ())?, Lag: ((number, number, number) -> ())?, Request: ((string) -> ())? } = {}
local NextSend = 0                       -- os.clock() of the next Speed_State

local KEEP_GUIS = { GameGUI = true, SpeedFx = true, Cmdr = true, TouchGui = true }
local SpeedOnly = { On = false, Guis = {} :: { ScreenGui }, Core = {} :: { [Enum.CoreGuiType]: boolean }, Added = nil :: RBXScriptConnection?,
	Panels = {} :: { GuiObject } }
local Net = { Sent = 0, Places = 0, LastPlace = nil :: string?, Lag = { 0, 0, 0 } }   -- for the telemetry

-- // PRIVATE //--

local function HideGui(gui: Instance)
	if gui:IsA("ScreenGui") and not KEEP_GUIS[gui.Name] and gui.Enabled then
		gui.Enabled = false
		table.insert(SpeedOnly.Guis, gui)
	end
end

local function SetSpeedOnly(on: boolean)
	if on == SpeedOnly.On then return end
	SpeedOnly.On = on
	local playerGui = Player:WaitForChild("PlayerGui")
	if on then
		HudVisible = true
		HudInstance:SetVisible(true)
		for _, gui in playerGui:GetChildren() do HideGui(gui) end
		SpeedOnly.Added = playerGui.ChildAdded:Connect(HideGui) -- one opened meanwhile goes too
		local panels = playerGui:FindFirstChild("GameGUI") and playerGui.GameGUI:FindFirstChild("Holder")
		for _, panel in if panels then panels:GetChildren() else {} do
			if panel:IsA("GuiObject") and panel.Name ~= "SpeedHolder" and panel.Visible then
				panel.Visible = false
				table.insert(SpeedOnly.Panels, panel)
			end
		end
		for _, kind in Enum.CoreGuiType:GetEnumItems() do
			if kind ~= Enum.CoreGuiType.All then SpeedOnly.Core[kind] = StarterGui:GetCoreGuiEnabled(kind) end
		end
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
	else
		if SpeedOnly.Added then
			SpeedOnly.Added:Disconnect()
			SpeedOnly.Added = nil
		end
		for _, gui in SpeedOnly.Guis do
			if gui.Parent then gui.Enabled = true end
		end
		table.clear(SpeedOnly.Guis)
		for _, panel in SpeedOnly.Panels do
			if panel.Parent then panel.Visible = true end
		end
		table.clear(SpeedOnly.Panels)
		for kind, enabled in SpeedOnly.Core do pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, enabled) end
		table.clear(SpeedOnly.Core)
	end
end

local function SetBody(name: string)
	Body = name
	Movement:SetBody(name)
	Ball:SetVisible(name == "Ball")
	Human:SetVisible(name == "Human")
	Player:SetAttribute("SpeedBody", name)
end

local RaceStart: { JogAt: number, GoAt: number }? = nil

local Auto = false
local AutoBrain: any = nil
local AutoCourse: string? = nil

local function AutoInput(inp, dt)
	local name = Movement.courseName
	if AutoCourse ~= name then
		AutoCourse, AutoBrain = name, nil
		local world = workspace:FindFirstChild("World")
		local courses = world and world:FindFirstChild(SpeedConfig.Courses or "Courses")
		local course = courses and name and courses:FindFirstChild(name)
		if course and course:GetAttribute("Heightfield") == "Generated" then
			local ok, data = pcall(Generated.ForCourse, course)
			if ok and data then
				local A = SpeedConfig.Race.Autoplay
				AutoBrain = BotBrain.new(Movement, data, A and A.Tier or "Pro", math.random(1, 2 ^ 30))
				AutoBrain.LaunchAt = 0
			end
		end
		Movement:SetAutoSteer(AutoBrain == nil)
	end
	if Movement.finishWay then return end
	if AutoBrain then
		AutoBrain:Input(inp, dt)
	else
		inp.y, inp.magnitude, inp.fastRunHeld = 1, 1, true
	end
end

local function SetAuto(on: boolean)
	if Auto == on then return end
	Auto = on
	AutoCourse, AutoBrain = nil, nil
	if not on and Movement then Movement:SetAutoSteer(false) end
end

local function ReadInput(inp, dt)

	local start = RaceStart
	if start then
		local now = workspace:GetServerTimeNow()
		if now < start.GoAt then
			local jog = if now >= start.JogAt then 1 else 0
			inp.x, inp.y, inp.magnitude, inp.lookX, inp.lookY = 0, jog, jog, 0, 0
			inp.dive, inp.fastRunHeld = false, false
			return
		end
		RaceStart = nil
		if SpeedConfig.Race.AutoLaunch and Movement.mode ~= "Fast" then Movement:goFast() end
	end
	if Auto then
		AutoInput(inp, dt)
		return
	end
	if UserInputService:GetFocusedTextBox() then return end
	local x, y = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then x += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then x -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then y += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then y -= 1 end
	local magnitude = (x ~= 0 or y ~= 0) and 1 or 0
	local lookX, lookY = 0, 0
	for _, input in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > 0.2 then
			x, y = input.Position.X, input.Position.Y
			magnitude = math.min(input.Position.Magnitude, 1)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 and input.Position.Magnitude > 0.2 then
			lookX = input.Position.X * SpeedConfig.GamepadDegreesPerSecond * dt
			lookY = -input.Position.Y * SpeedConfig.GamepadDegreesPerSecond * dt
		end
	end
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		local d = UserInputService:GetMouseDelta()
		local sens = UserSettings():GetService("UserGameSettings").MouseSensitivity
		lookX += d.X * SpeedConfig.MouseDegreesPerPixel * sens
		lookY += d.Y * SpeedConfig.MouseDegreesPerPixel * sens
	end
	inp.x, inp.y, inp.magnitude, inp.lookX, inp.lookY = x, y, magnitude, lookX, lookY
	inp.dive = Held.Dive
	inp.fastRunHeld = Held.FastRun
end

local PRESSES = {
	Respawn = function() Movement:RespawnAtStart() end,
	Body = function() SetBody(Body == "Ball" and "Human" or "Ball") end,
	CourseValley = function() Movement:RespawnAtCourse("Valley") end,
	CourseCurves = function() Movement:RespawnAtCourse("Curves") end,
	CoursePart = function() Movement:RespawnAtCourse("PartCourse") end,
	AutoSteer = function() Movement:SetAutoSteer(not Movement.autoSteer) end,
	Hud = function()
		HudVisible = not HudVisible
		HudInstance:SetVisible(HudVisible)
	end,
	FreeMouse = function() CameraRigInstance:ToggleMouseLock() end,
	Ghost = function() Runners:SetGhost(not Runners:GetGhost()) end,
}

local function BindInput()
	local groups = {}
	for name, action in pairs(ControlsConfig.Actions) do
		local group = action.Group or "Speed"
		groups[group] = true
		local handler
		if action.Hold then
			handler = function(state)
				Held[name] = state == Enum.UserInputState.Begin
				return Enum.ContextActionResult.Sink
			end
		else
			local press = PRESSES[name]
			handler = function(state)
				if state == Enum.UserInputState.Begin and press and Ready then press() end
				return Enum.ContextActionResult.Sink
			end
		end
		InputService.RegisterAction(group, "Speed_" .. name, action.Keys, handler)
	end
	for group in pairs(groups) do InputService.BindGroup(group) end
end

local function SendState()
	if not Callbacks.State then return end
	local clock = os.clock()
	if clock < NextSend then return end
	local interval = 1 / SpeedConfig.Net.SendRate
	NextSend += interval
	if NextSend <= clock then NextSend = clock + interval end
	local inp = Movement.input
	Callbacks.State(RunnerPack.Encode({
		T = workspace:GetServerTimeNow(),
		Position = Movement:GetPosition(),
		Velocity = Movement:GetVelocity(),
		Rotation = Movement.visualCF,
		Yaw = Movement.yaw,
		TimeScale = Movement:GetTimeScale(),
		Spawn = Movement.spawnCount or 0,
		Grounded = Movement.isGrounded,
		MostlyGrounded = Movement.mostlyGrounded,
		Dive = inp.dive,
		Slow = Movement.mode == "Slow",
		FastRun = inp.fastRunHeld,
		Ball = Body == "Ball",
		Bad = RunnerPack.JustBad(Movement),
		InputX = inp.x,
		InputY = inp.y,
	}))
	Net.Sent += 1
end

local function Frame(dt: number)
	if not Ready then return end
	local clock = os.clock()
	if LastFrame then
		dt = clock - LastFrame
		Perf.Count("Frame", dt)
	end
	LastFrame = clock
	if Paused then return end
	Perf.Begin("Speed.Input")
	Movement:FrameInput(dt)
	Perf.End()
	Perf.Begin("Speed.Sim")
	Movement:Step(dt)
	Perf.End()
	Perf.Begin("Speed.Send")
	SendState()
	Perf.End()
	local gameDt = dt * Movement:GetTimeScale()
	Perf.Begin("Speed.Body")
	if Body == "Ball" then Ball:Update(gameDt) else Human:Update(gameDt) end
	Perf.End()
	Perf.Begin("Speed.Camera")
	CameraRigInstance:Update(gameDt)
	Perf.End()
	Perf.Begin("Speed.Effects")
	EffectsInstance:Update(gameDt)
	Perf.End()
	Perf.Begin("Speed.Hud")
	if HudVisible then HudInstance:Update() end
	Perf.End()
	Perf.Frame()
end

local function Start()
	local playerGui = Player:WaitForChild("PlayerGui")
	local world = workspace:WaitForChild("World")
	world:WaitForChild(SpeedConfig.Courses or "Courses"):WaitForChild(SpeedConfig.CourseName, 30)

	Movement = SpeedSim.new()
	Movement:SetInputSource(ReadInput)

	SetAuto(Player:GetAttribute("SpeedAutoplay") == true)
	Player:GetAttributeChangedSignal("SpeedAutoplay"):Connect(function()
		SetAuto(Player:GetAttribute("SpeedAutoplay") == true)
	end)
	Player.Idled:Connect(function()
		if not Auto then return end
		pcall(function()
			local virtual = game:GetService("VirtualUser")
			virtual:CaptureController()
			virtual:ClickButton2(Vector2.zero)
		end)
	end)
	Movement:AddIgnore(Runners:Folder())
	CameraRigInstance = CameraRig.new(Movement)
	HudInstance = Hud.new(playerGui)
	HudInstance:Bind(Movement)
	HudInstance:SetReadoutsVisible(playerGui:FindFirstChild("GameGUI") == nil) -- the GameGUI's SpeedHolder shows them
	Movement.Hit.Event:Connect(function(kind, damage)
		local e = Movement.lastEdge or {}
		local p = Movement.pos * Movement.S
		table.insert(HitLog, { kind = kind, damage = damage, speed = Movement:GetSpeed(), pos = { math.floor(p.X), math.floor(p.Y), math.floor(p.Z) },
			part = e.name, normal = e.normal and { e.normal.X, e.normal.Y, e.normal.Z } })
		if #HitLog > 20 then table.remove(HitLog, 1) end
	end)

	local courseName = SpeedConfig.CourseName
	for _, course in world[SpeedConfig.Courses or "Courses"]:GetChildren() do
		if course.Name:sub(1, 4) == "Map_" then courseName = course.Name end
	end
	Movement:SetCourse(courseName)
	Movement:RespawnAtCourse(courseName, true)
	Ball = BallView.new(Movement)
	Human = HumanView.new(Movement, nil, Player.UserId)
	EffectsInstance = Effects.new(Movement, playerGui)
	SetBody(SpeedConfig.Body or "Human")
	BindInput()
	Ready = true

	RunService:BindToRenderStep("SpeedFrame", Enum.RenderPriority.Camera.Value + 1, function(dt)
		LastRender = os.clock()
		Frame(dt)
	end)

	RunService.Heartbeat:Connect(function(dt)
		if os.clock() - LastRender > 0.1 then Frame(dt) end
	end)

	-- DEV HOOKS
	Player:SetAttribute("SpeedCommand", "")
	Player:GetAttributeChangedSignal("SpeedCommand"):Connect(function()
		local cmd = Player:GetAttribute("SpeedCommand")
		if type(cmd) ~= "string" or cmd == "" then return end
		local words = string.split(cmd, " ")
		local action = table.remove(words, 1)
		Service:Command(action, #words > 0 and table.concat(words, " ") or nil)
	end)

	if not RunService:IsStudio() then return end
	local telemetry = Instance.new("StringValue")
	telemetry.Name = "SpeedTelemetry"
	telemetry.Parent = Player
	task.spawn(function()
		while Player.Parent do
			task.wait(0.2)
			local d = Movement:GetDebug()
			d.pos = { d.pos.X, d.pos.Y, d.pos.Z }
			d.fov = workspace.CurrentCamera.FieldOfView
			d.landings = Movement.landingLog
			d.hits = HitLog
			d.physicsFps = workspace:GetRealPhysicsFPS()
			d.body = Body
			d.anim = Human:GetState()
			d.perf = Perf.Report()
			d.spikes = Perf.Spikes()
			local stats = Runners:Stats()
			local ghost = stats.Ghost
			d.net = {
				sent = Net.Sent, places = Net.Places, lastPlace = Net.LastPlace, lag = Net.Lag, copies = stats.Copies,
				ghost = ghost and {
					behind = ghost.Drawn and math.floor((Movement:GetPosition() - ghost.Drawn).Magnitude * 10) / 10,
					delay = ghost.Delay and math.floor(ghost.Delay * 1000), late = math.floor(ghost.Late * 1000),
					clock = ghost.Behind and math.floor(ghost.Behind * 1000), gap = math.floor(ghost.Gap * 1000),
					extrapolated = ghost.Frames > 0 and math.floor(ghost.Extrapolated / ghost.Frames * 1000) / 10 or 0,
					ageLow = ghost.AgeLow and math.floor(ghost.AgeLow * 1000), ageHigh = ghost.AgeHigh and math.floor(ghost.AgeHigh * 1000),
				},
			}
			local okJson, json = pcall(HttpService.JSONEncode, HttpService, d)
			if okJson then telemetry.Value = json end
		end
	end)
end

-- // PUBLIC //--

function Service:SetCallbacks(callbacks)
	Callbacks = callbacks
end

function Service:Request(action: string)
	if Callbacks.Request then Callbacks.Request(action) end
end

function Service:FreeCursor(free: boolean)
	if CameraRigInstance then CameraRigInstance:SetCursorFree(free) end
end

function Service:Finish(way: Vector3?)
	if Movement then Movement:Finish(way) end
end

function Service:GetMovement()
	return Movement
end

function Service:IsAuto(): boolean
	return Auto
end

function Service:IsHeld(name: string): boolean
	return Held[name] == true
end

function Service:GetBody()
	return if Body == "Human" then Human else nil
end

function Service:Place(position: Vector3, why: string?)
	if not Ready or typeof(position) ~= "Vector3" then return end
	Net.Places += 1
	Net.LastPlace = why
	local look = Movement.visualCF.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then flat = Vector3.new(0, 0, -1) end
	local yaw, pitch, waypoint = Movement.yaw, Movement.pitchDown, Movement.waypointIndex
	Movement:resetState(CFrame.lookAt(position, position + flat.Unit))
	Movement.yaw, Movement.pitchDown, Movement.waypointIndex = yaw, pitch, waypoint
	if Movement.camera then Movement.camera:Snap() end
end

function Service:Command(action: string, value: string?)
	if not Ready or type(action) ~= "string" then return end
	local words = value and string.split(value, " ") or {}
	action = action:lower()
	if action == "items" then
		require(script.Parent.SpeedItemClient):Command(value or "")
		return
	end
	if action == "course" and words[1] then

		if not SpeedSim.FindCourse(words[1]) then
			local world = workspace:FindFirstChild("World")
			local folder = world and world:FindFirstChild(SpeedConfig.Courses or "Courses")
			if folder then folder:WaitForChild(words[1], 10) end
		end
		RaceStart = nil
		Movement:RespawnAtCourse(words[1], words[2] == "still")
	elseif action == "load" and words[2] then

		RaceStart = nil
		Paused = true
		require(script.Parent.SpeedRaceClient):Load(words[1], tonumber(words[2]) or 0)
	elseif action == "race" and words[8] then

		Paused = false
		require(script.Parent.SpeedRaceClient):EndLoad()

		if not SpeedSim.FindCourse(words[1]) then
			local world = workspace:FindFirstChild("World")
			local folder = world and world:FindFirstChild(SpeedConfig.Courses or "Courses")
			if folder then folder:WaitForChild(words[1], 10) end
		end
		local n = {}
		for i = 2, 8 do n[i] = tonumber(words[i]) or 0 end
		local at, look = Vector3.new(n[2], n[3], n[4]), Vector3.new(n[5], 0, n[6])
		if look.Magnitude < 1e-3 then look = Vector3.new(0, 0, -1) end
		if Movement.courseName ~= words[1] then Movement:SetCourse(words[1]) end
		Movement:RespawnStill(CFrame.lookAt(at, at + look.Unit))
		RaceStart = { JogAt = n[8] - SpeedConfig.Race.Count, GoAt = n[8] }
		CameraRigInstance:PlayIntro(n[7])
		local Race = require(script.Parent.SpeedRaceClient)
		Race:Begin(n[8])
		Race:Countdown(n[8])
	elseif action == "body" and words[1] then
		SetBody(words[1]:lower() == "ball" and "Ball" or "Human")
	elseif action == "auto" then
		Movement:SetAutoSteer(words[1] ~= "off")
	elseif action == "wp" then
		Movement:RespawnAtWaypoint(tonumber(words[1]) or 1, tonumber(words[2]))
	elseif action == "dive" then
		Movement.forceDiveUntil = os.clock() + (tonumber(words[1]) or 1.5)
	elseif action == "start" then
		Movement:RespawnAtStart()
	elseif action == "still" then
		Movement:RespawnAtCourse(Movement.courseName, true)
	elseif action == "ghost" then
		Runners:SetGhost(if words[1] then words[1]:lower() ~= "off" else not Runners:GetGhost())
	elseif action == "lag" then
		local ping, jitter, loss = math.max(tonumber(words[1]) or 0, 0), math.max(tonumber(words[2]) or 0, 0), math.clamp(tonumber(words[3]) or 0, 0, 100)
		Net.Lag = { ping, jitter, loss }
		if Callbacks.Lag then Callbacks.Lag(ping, jitter, loss) end
	elseif action == "ui" then
		SetSpeedOnly((words[1] or "speed"):lower() == "speed")
	elseif action == "item" then
		local Race = require(script.Parent.SpeedRaceClient)
		local what = words[1]
		if not what or what:lower() == "off" then
			Race:PreviewItem(nil)
		elseif what:lower() == "use" then
			Race:UseItem()
		else

			local uses = tonumber(words[#words])
			local nameWords = table.move(words, 1, if uses then #words - 1 else #words, 1, {})
			Race:PreviewItem(table.concat(nameWords, " "), uses)
		end
	elseif action == "countdown" then
		require(script.Parent.SpeedRaceClient):Countdown(tonumber(words[1]))
	elseif action == "tags" then
		require(ReplicatedStorage.UI.PlayerMarkers).SetEnabled((words[1] or "on"):lower() ~= "off")
	elseif action == "vfx" then

		local what = (words[1] or "land"):lower()
		if what == "lines" then
			EffectsInstance:SetLines((words[2] or "on"):lower() ~= "off")
		else
			require(script.Parent.SpeedVFXClient):Test(what)
		end
	elseif action == "sound" then
		local Sounds = require(script.Parent.SpeedSoundClient)
		local what = words[1] or "on"
		if what:lower() == "on" or what:lower() == "off" then
			Sounds:SetEnabled(what:lower() == "on")
		else
			Sounds:Play(what, tonumber(words[2]))
		end
	elseif action == "minimap" then

		local MapHolder = require(game:GetService("ReplicatedStorage").UI.Holders.MapHolder)
		MapHolder.SetFollow((words[1] or "follow"):lower() ~= "whole")
	elseif action == "steer" then

		local x = tonumber(words[1])
		Movement.forceSteerX = if x then math.clamp(x, -1, 1) else nil
	elseif action == "warp" then
		local studs = tonumber(words[1]) or 500
		local way = if Movement.vel.Magnitude > 1e-3 then Movement.vel.Unit else Movement.visualCF.LookVector
		Movement.pos += way * (studs / Movement.S)
		Movement.prevPos = Movement.pos
	end
end

local function ApplyChat()
	local on = SpeedConfig.Chat ~= false
	task.spawn(function()
		local TextChatService = game:GetService("TextChatService")
		pcall(function()
			local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
			local bar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
			if window then window.Enabled = on end
			if bar then bar.Enabled = on end
		end)
		for _ = 1, 20 do   -- (the core GUI may not be ready yet)
			if pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, on) end) then break end
			task.wait(0.5)
		end
	end)
end

function Service:Init()
	ApplyChat()
	if Started then return end
	Started = true

	local playerGui = Player:WaitForChild("PlayerGui")
	local template = game:GetService("StarterGui"):FindFirstChild("GameGUI")
	if template and not playerGui:FindFirstChild("GameGUI") then template:Clone().Parent = playerGui end
	task.spawn(Start)
end

return Service
