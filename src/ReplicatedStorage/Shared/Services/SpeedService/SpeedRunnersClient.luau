local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Runners = {}
if RunService:IsServer() then return Runners end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local RunnerPack = require(ReplicatedStorage.Shared.Modules.Speed.RunnerPack)
local RunnerPath = require(ReplicatedStorage.Shared.Modules.Speed.RunnerPath)
local Perf = require(ReplicatedStorage.Shared.Modules.Speed.SpeedPerf)
local BallView = require(script.Parent.SpeedBallClient)
local HumanView = require(script.Parent.SpeedHumanClient)

local Player = Players.LocalPlayer
local View = SpeedConfig.View
local ENTRY = 2 + RunnerPack.Size
local IDLE = 0.1
local UP = Vector3.yAxis

type Entry = {
	Id: number,
	Mine: boolean,                   -- the ghost: your own runner
	Reports: { any },
	Late: number,
	Ages: { number },
	Gap: number,
	Heard: number,                   -- os.clock() of its newest report
	Proxy: any,
	Views: { [string]: any },
	Body: string?,                   -- the one shown
	Highlight: Highlight?,           -- the ghost's tint
	Delay: number?,
	At: number?,
	Extrapolated: number,
	Frames: number,                  -- ...of these frames
	Drawn: Vector3?,                 -- where it's drawn now, studs
}

-- [ STATE ]--
local Entries: { [number]: Entry } = {}
local Ghost = false
local FolderInstance: Folder? = nil
local Bound = false
local IdleConnection: RBXScriptConnection? = nil
local LastDrawn = 0
local LastStep: number? = nil

-- // PRIVATE //--

local function GetFolder(): Folder
	if FolderInstance and FolderInstance.Parent then return FolderInstance end
	local folder = workspace:FindFirstChild(View.Folder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = View.Folder
		folder.Parent = workspace
	end
	FolderInstance = folder :: Folder
	return folder :: Folder
end

local function NewProxy()
	return {
		S = SpeedConfig.Studs,
		renderPos = Vector3.zero, vel = Vector3.zero, visualCF = CFrame.identity, yaw = 0, mode = "Fast",
		isGrounded = false, mostlyGrounded = false, groundNormal = UP, sinceSwitch = 10, spawn = nil, bad = false,
		input = { x = 0, y = 0, dive = false, fastRunHeld = false },
		Landed = Instance.new("BindableEvent"), Hit = Instance.new("BindableEvent"),
		AddIgnore = function() end, refreshFilter = function() end,
	}
end

local function Quiet(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
		end
	end
end

local function BotInfo(id: number): Instance?
	local registry = ReplicatedStorage:FindFirstChild(SpeedConfig.Bots.Registry)
	return registry and registry:FindFirstChild(tostring(id))
end

local function Owner(entry: Entry): Player?
	if entry.Mine then return Player end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("SpeedId") == entry.Id then return player end
	end
	return nil
end

local function Show(entry: Entry, name: string)
	if entry.Body == name then return end
	for other, view in entry.Views do
		if other ~= name then view:SetVisible(false) end
	end
	local view = entry.Views[name]
	if not view then
		if name == "Ball" then
			view = BallView.new(entry.Proxy, GetFolder())
		else
			local owner = Owner(entry)
			local bot = not owner and BotInfo(entry.Id)

			view = HumanView.new(entry.Proxy, GetFolder(), if owner then owner.UserId elseif bot then bot:GetAttribute("Avatar") else nil)
			view.OnWear = function(model)
				Quiet(model)
				if entry.Highlight and entry.Body == name then entry.Highlight.Adornee = model end
			end
		end
		view.model.Name = ("%s%d%s"):format(if entry.Mine then "Ghost" else "Runner", entry.Id, name)
		Quiet(view.model)
		entry.Views[name] = view
	end
	view:SetVisible(true)
	entry.Body = name
	if entry.Highlight then entry.Highlight.Adornee = view.model end
end

local function Forget(id: number)
	local entry = Entries[id]
	if not entry then return end
	Entries[id] = nil
	for _, view in entry.Views do view:Destroy() end
	if entry.Highlight then entry.Highlight:Destroy() end
	entry.Proxy.Landed:Destroy()
	entry.Proxy.Hit:Destroy()
end

local function Ensure(id: number, mine: boolean): Entry
	local entry = Entries[id]
	if entry then return entry end
	entry = { Id = id, Mine = mine, Reports = {}, Late = 0, Ages = {}, Gap = 1 / SpeedConfig.Net.SendRate, Heard = os.clock(),
		Proxy = NewProxy(), Views = {},
		Extrapolated = 0, Frames = 0 }
	if mine then
		local tint = Instance.new("Highlight")
		tint.Name = "GhostTint"
		tint.FillColor, tint.OutlineColor = View.Ghost.Color, View.Ghost.Color
		tint.FillTransparency, tint.OutlineTransparency = View.Ghost.FillTransparency, 0
		tint.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		tint.Parent = GetFolder()
		entry.Highlight = tint
	end
	Entries[id] = entry
	return entry
end

local StepCount = 0
local FAR_POSE = 350
local POSE_EVERY = 3
local function Step(dt: number)
	Perf.Begin("Speed.Runners")
	StepCount += 1
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	if LastStep then dt = clock - LastStep end
	LastStep = clock
	local delayConfig, clockConfig = View.Delay, View.Clock
	for id, entry in Entries do
		if clock - entry.Heard > View.Forget then
			Forget(id)
			continue
		end
		local delay = math.clamp(entry.Late + entry.Gap + delayConfig.Margin, delayConfig.Min, delayConfig.Max)

		local target = now - delay
		local t = entry.At
		if not t or math.abs(target - t) > clockConfig.Snap then
			t = target
		else
			local gap = target - (t + dt)
			t += dt * (1 + math.clamp(gap * clockConfig.Gain, -clockConfig.Slow, clockConfig.Fast))
		end
		local position, from, to, k = RunnerPath.At(entry.Reports, t, View.Extrapolate)
		if not position then continue end
		entry.Delay, entry.At, entry.Drawn = delay, t, position
		entry.Frames += 1
		local newest = entry.Reports[#entry.Reports]
		if newest and t > newest.T then entry.Extrapolated += 1 end
		local near = if k < 0.5 then from else to
		local proxy = entry.Proxy
		local mode = if near.Slow then "Slow" else "Fast"
		if mode ~= proxy.mode then
			proxy.mode, proxy.sinceSwitch = mode, 0
		else
			proxy.sinceSwitch += dt
		end
		proxy.renderPos = position / proxy.S
		proxy.vel = from.Velocity:Lerp(to.Velocity, k) / proxy.S
		proxy.visualCF = RunnerPath.Rotation(from, to, k)
		proxy.yaw = RunnerPath.Yaw(from, to, k)
		proxy.isGrounded, proxy.mostlyGrounded = near.Grounded, near.MostlyGrounded
		proxy.spawn, proxy.bad = near.Spawn, near.Bad
		proxy.groundNormal = proxy.visualCF.UpVector
		local input = proxy.input
		input.x, input.y, input.dive, input.fastRunHeld = near.InputX, near.InputY, near.Dive, near.FastRun
		Show(entry, if near.Ball then "Ball" else "Human")
		local scale = from.TimeScale + (to.TimeScale - from.TimeScale) * k
		proxy.timeScale = scale

		entry.PoseDt = (entry.PoseDt or 0) + dt * scale
		if (position - eye).Magnitude < FAR_POSE or (StepCount + id) % POSE_EVERY == 0 then
			entry.Views[entry.Body :: string]:Update(entry.PoseDt)
			entry.PoseDt = 0
		end
	end
	Perf.End()
end

local function Start()
	if Bound then return end
	Bound = true
	RunService:BindToRenderStep("SpeedRunners", Enum.RenderPriority.Camera.Value + 2, function(dt)
		LastDrawn = os.clock()
		Step(dt)
	end)

	IdleConnection = RunService.Heartbeat:Connect(function(dt)
		if os.clock() - LastDrawn > IDLE then Step(dt) end
	end)
end

-- // PUBLIC //--

function Runners:Folder(): Folder
	return GetFolder()
end

function Runners:Snapshot(data: any)
	if typeof(data) ~= "buffer" then return end
	local mine = Player:GetAttribute("SpeedId")
	local now = workspace:GetServerTimeNow()
	local rise, decay = View.Delay.Rise, View.Delay.Decay
	for at = 0, buffer.len(data) - ENTRY, ENTRY do
		local id = buffer.readu16(data, at)
		local isMine = id == mine
		if isMine and not Ghost then continue end
		local state = RunnerPack.Read(data, at + 2)
		local entry = Ensure(id, isMine)
		local reports = entry.Reports
		local last = reports[#reports]
		if last and state.T <= last.T then continue end

		local age = now - state.T
		entry.Late = if age > entry.Late then math.min(age, entry.Late + rise) else math.max(age, entry.Late * decay)
		if last and state.Spawn == last.Spawn then
			local gap = math.min(state.T - last.T, View.Delay.Max)
			entry.Gap = if gap > entry.Gap then math.min(gap, entry.Gap + rise) else math.max(gap, entry.Gap * decay)
		end
		local ages = entry.Ages
		table.insert(ages, age)
		if #ages > SpeedConfig.Net.SendRate then table.remove(ages, 1) end
		entry.Heard = os.clock()
		table.insert(reports, state)
		while #reports > 2 and reports[1].T < state.T - View.Keep do table.remove(reports, 1) end
	end
	if next(Entries) ~= nil then Start() end
end

local ListCache, ListStep = nil, -1
local BotCache: { [number]: any } = {}
function Runners:List()
	if ListStep == StepCount and ListCache then return ListCache end
	local players = {}
	for _, player in Players:GetPlayers() do
		local id = player:GetAttribute("SpeedId")
		if type(id) == "number" then players[id] = player end
	end
	local list = {}
	for id, entry in Entries do
		if entry.Mine or not entry.Drawn then continue end
		local player = players[id]
		local info = nil
		if not player then
			local cached = BotCache[id]
			if not (cached and cached.Entry.Parent) then
				local bot = BotInfo(id)
				cached = bot and { Entry = bot, Info = { Name = bot:GetAttribute("Name"), Tier = bot:GetAttribute("Tier"),
					UserId = bot:GetAttribute("UserId"), Avatar = bot:GetAttribute("Avatar") } }
				BotCache[id] = cached
			end
			info = cached and cached.Info
		end
		table.insert(list, { Id = id, Player = player, Position = entry.Drawn, Speed = entry.Proxy.vel.Magnitude * entry.Proxy.S,
			Bot = info })
	end
	for id, cached in BotCache do
		if not Entries[id] then BotCache[id] = nil end
	end
	ListCache, ListStep = list, StepCount
	return list
end

function Runners:EachCopy(fn: (number, any, any, Vector3) -> ())
	for id, entry in Entries do
		if entry.Mine or not entry.Drawn or not entry.Body then continue end
		fn(id, entry.Proxy, entry.Views[entry.Body :: string], entry.Drawn :: Vector3)
	end
end

function Runners:SetGhost(on: boolean)
	Ghost = on
	Player:SetAttribute("SpeedGhost", on)
	if not on then
		local mine = Player:GetAttribute("SpeedId")
		if type(mine) == "number" then Forget(mine) end
	end
end

function Runners:GetGhost(): boolean
	return Ghost
end

function Runners:Stats()
	local copies = 0
	for _ in Entries do copies += 1 end
	local mine = Player:GetAttribute("SpeedId")
	local ghost = if type(mine) == "number" then Entries[mine] else nil
	local now = workspace:GetServerTimeNow()
	local low, high = math.huge, 0
	for _, age in ghost and ghost.Ages or {} do
		low, high = math.min(low, age), math.max(high, age)
	end
	local stats = { Copies = copies, Ghost = ghost and { Delay = ghost.Delay, Late = ghost.Late, Gap = ghost.Gap, Drawn = ghost.Drawn,
		Behind = ghost.At and now - ghost.At, Extrapolated = ghost.Extrapolated, Frames = ghost.Frames,
		AgeLow = if high > 0 then low else nil, AgeHigh = if high > 0 then high else nil } }
	if ghost then ghost.Extrapolated, ghost.Frames = 0, 0 end
	return stats
end

return Runners
