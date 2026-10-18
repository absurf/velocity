local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local RunnerPack = require(ReplicatedStorage.Shared.Modules.Speed.RunnerPack)

local Service = {}
type Service = typeof(Service)

local FOCUS_FOLDER = "SpeedFocus"
local Net = SpeedConfig.Net
local SIZE = RunnerPack.Size
local ENTRY = 2 + SIZE
local CORRECTED_REACH = 10

type Runner = {
	Id: number,
	Focus: BasePart,
	Last: any?,            -- the last good report (RunnerPack state)
	Scale: number,         -- its granted time scale
	History: { any },
	Target: Vector3?,
	CorrectedAt: number,   -- os.clock() of the last Correct sent
	Accepted: number, Rejected: number, Corrected: number,
	Why: string?,
}

-- [ STATE ]--
local Started = false
local Runners: { [Player]: Runner } = {}
local UsedIds: { [number]: boolean } = {}
local Outgoing: { { Id: number, Data: buffer } } = {}   -- good reports since the last Speed_Snap
local Callbacks: {
	Command: ((Player, string, string?) -> ())?,
	Snap: ((buffer) -> ())?,
	Place: ((Player, Vector3, string) -> ())?,
	Results: ((string) -> ())?,
} = {}

-- // PRIVATE //--

local function Courses(): Instance?
	local world = workspace:FindFirstChild("World")
	return world and world:FindFirstChild(SpeedConfig.Courses or "Courses")
end

local function StartPosition(): Vector3
	local courses = Courses()
	local course = courses and courses:FindFirstChild(SpeedConfig.CourseName)
	local start = course and course:FindFirstChild("Start")
	return if start and start:IsA("BasePart") then start.Position else Vector3.new(0, 10, 0)
end

local SpawnCache: { Vector3 }? = nil
local SpawnAt = 0
local function SpawnPoints(): { Vector3 }
	if SpawnCache and os.clock() - SpawnAt < 1 then return SpawnCache end
	local points = {}
	SpawnCache, SpawnAt = points, os.clock()
	local courses = Courses()
	if not courses then return points end
	for _, course in courses:GetChildren() do
		local start = course:FindFirstChild("Start")
		if start and start:IsA("BasePart") then table.insert(points, start.Position) end
		for _, name in { "Waypoints", "Grid" } do
			local folder = course:FindFirstChild(name)
			if folder then
				for _, point in folder:GetChildren() do
					if point:IsA("BasePart") then table.insert(points, point.Position) end
				end
			end
		end
	end
	return points
end

local function OnSpawn(position: Vector3): boolean
	for _, point in SpawnPoints() do
		local offset = position - point
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= Net.SpawnRadius and offset.Y <= Net.SpawnRadius and offset.Y >= -Net.SpawnBelow then
			return true
		end
	end
	return false
end

local function FocusFolder(): Folder
	local folder = workspace:FindFirstChild(FOCUS_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOCUS_FOLDER
		folder.Parent = workspace
	end
	return folder :: Folder
end

local function NewId(): number
	for id = 1, 65535 do
		if not UsedIds[id] then
			UsedIds[id] = true
			return id
		end
	end
	return 0
end

local NextBotId = 1000
local function NewBotId(): number
	for _ = 1, 60000 do
		NextBotId = if NextBotId >= 60000 then 1000 else NextBotId + 1
		if not UsedIds[NextBotId] then
			UsedIds[NextBotId] = true
			return NextBotId
		end
	end
	return NewId()
end

local function PlayerAdded(player: Player)
	if Runners[player] then return end
	local part = Instance.new("Part")
	part.Name = tostring(player.UserId)
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = StartPosition()
	part.Parent = FocusFolder()
	player.ReplicationFocus = part
	local id = NewId()
	Runners[player] = { Id = id, Focus = part, Scale = 1, History = {}, CorrectedAt = -math.huge, Accepted = 0, Rejected = 0, Corrected = 0 }
	player:SetAttribute("SpeedId", id)
end

local function PlayerRemoving(player: Player)
	local runner = Runners[player]
	if not runner then return end
	Runners[player] = nil
	UsedIds[runner.Id] = nil
	runner.Focus:Destroy()
end

local function Correct(player: Player, runner: Runner)
	runner.Rejected += 1
	local clock = os.clock()
	if clock - runner.CorrectedAt < Net.CorrectEvery then return end
	runner.CorrectedAt = clock
	local target = if runner.Last then runner.Last.Position else StartPosition()
	runner.Target = target
	runner.Corrected += 1
	if Callbacks.Place then Callbacks.Place(player, target, "Correct") end
end

local function Flush()
	if #Outgoing == 0 or not Callbacks.Snap then return end
	local index = 1
	while index <= #Outgoing do
		local count = math.min(#Outgoing - index + 1, Net.SnapMax)
		local data = buffer.create(count * ENTRY)
		for i = 0, count - 1 do
			local report = Outgoing[index + i]
			buffer.writeu16(data, i * ENTRY, report.Id)
			buffer.copy(data, i * ENTRY + 2, report.Data, 0, SIZE)
		end
		Callbacks.Snap(data)
		index += count
	end
	table.clear(Outgoing)
end

-- // PUBLIC //--

function Service.SetCallbacks(_self: Service, callbacks)
	Callbacks = callbacks
end

function Service.State(_self: Service, player: Player, data: any)
	local runner = Runners[player]
	if not runner or typeof(data) ~= "buffer" or buffer.len(data) ~= SIZE then return end
	local state = RunnerPack.Read(data, 0)
	if not RunnerPack.Finite(state) then return end
	if state.T > workspace:GetServerTimeNow() + Net.Future then return end   -- from the future
	local last = runner.Last
	if last and state.T <= last.T then return end                           -- out of order, or the same one
	local good
	if not last or state.Spawn ~= last.Spawn then

		local target = runner.Target
		good = OnSpawn(state.Position) or (target ~= nil and (state.Position - target).Magnitude <= CORRECTED_REACH)
		if not good then
			runner.Why = ("respawn %d -> %d off any spawn point%s"):format(if last then last.Spawn else -1, state.Spawn,
				if target then (" (%.0f studs from where it was put)"):format((state.Position - target).Magnitude) else "")
		end
	else
		local reach = Net.MaxSpeed * runner.Scale * (state.T - last.T) * Net.Slack + Net.Margin
		local moved = (state.Position - last.Position).Magnitude
		good = moved <= reach
		if not good then runner.Why = ("moved %.0f studs in %.0f ms, %.0f allowed"):format(moved, (state.T - last.T) * 1000, reach) end
	end
	if not good then
		Correct(player, runner)
		return
	end
	runner.Target = nil
	runner.Accepted += 1

	local copy = buffer.create(SIZE)
	buffer.copy(copy, 0, data, 0, SIZE)
	if state.TimeScale > runner.Scale + 0.001 then
		state.TimeScale = runner.Scale
		RunnerPack.SetTimeScale(copy, 0, runner.Scale)
	end
	runner.Last = state
	local history = runner.History
	table.insert(history, state)
	while #history > 2 and history[1].T < state.T - Net.History do table.remove(history, 1) end
	table.insert(Outgoing, { Id = runner.Id, Data = copy })
	-- the streaming focus: where it's heading
	runner.Focus.Position = state.Position + state.Velocity * (state.TimeScale * 0.8)
end

function Service.GetRunner(_self: Service, player: Player)
	return Runners[player]
end

function Service.AddBot(_self: Service): number
	return NewBotId()
end

function Service.BotState(_self: Service, id: number, data: buffer)
	table.insert(Outgoing, { Id = id, Data = data })
end

function Service.RemoveBot(_self: Service, id: number)
	UsedIds[id] = nil
end

function Service.Command(_self: Service, player: Player, action: string, value: string?)
	if Callbacks.Command then Callbacks.Command(player, action, value) end
end

function Service.Results(_self: Service, json: string)
	if Callbacks.Results then Callbacks.Results(json) end
end

function Service.Init(_self: Service)
	if Started then return end
	Started = true

	local rig = workspace:FindFirstChild("Rig")
	if rig and rig:IsA("Model") and rig:FindFirstChild("AnimSaves") then rig.Parent = ServerStorage end
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(PlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do PlayerAdded(player) end
	Players.PlayerRemoving:Connect(PlayerRemoving)
	RunService.Heartbeat:Connect(Flush)
	task.spawn(function()
		if not RunService:IsStudio() then return end
		while true do
			task.wait(1)
			for player, runner in Runners do
				player:SetAttribute("SpeedNet", ("ok %d / turned away %d / corrected %d%s"):format(runner.Accepted, runner.Rejected, runner.Corrected,
					if runner.Why then " / last turned away: " .. runner.Why else ""))
			end
		end
	end)
end

return Service :: Service
