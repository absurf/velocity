local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Race = {}
if RunService:IsServer() then return Race end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local SpeedSim = require(ReplicatedStorage.Shared.Modules.Speed.SpeedSim)
local CourseTrack = require(ReplicatedStorage.Shared.Modules.Speed.CourseTrack)
local Perf = require(ReplicatedStorage.Shared.Modules.Speed.SpeedPerf)
local Backend = require(script.Parent.SpeedServiceClient)
local Runners = require(script.Parent.SpeedRunnersClient)
local Sounds = require(script.Parent.SpeedSoundClient)
local VFX = require(script.Parent.SpeedVFXClient)
local Holders = ReplicatedStorage.UI.Holders
local SpeedHolder = require(Holders.SpeedHolder)
local MatchInfoHolder = require(Holders.MatchInfoHolder)
local PlaceHolder = require(Holders.PlaceHolder)
local MapHolder = require(Holders.MapHolder)
local ItemHolder = require(Holders.ItemHolder)
local StartingHolder = require(Holders.StartingHolder)
local ResultsHolder = require(Holders.ResultsHolder)
local FinishedHolder = require(Holders.FinishedHolder)
local GUIController = require(ReplicatedStorage.UI.GUIController)
local LoadingScreen = require(ReplicatedStorage.UI.LoadingScreen)
local PlayerMarkers = require(ReplicatedStorage.UI.PlayerMarkers)
local MapClient = require(script.Parent.SpeedMapClient)

local Player = Players.LocalPlayer
local HUD = SpeedConfig.Hud

-- [ STATE ]--
local Started = false
local Movement: any = nil
local Track: any = nil          -- the course's CourseTrack
local TrackName: string? = nil
local Hints: { [any]: number } = {}
local Armed = true
local StartedAt: number? = nil  -- os.clock() its clock started
local EndedAt: number? = nil    -- ...and stopped (the finish)
local Item: { Name: string, Uses: number, MaxUses: number, Since: number? }? = nil   -- the `speed item` preview
local LastPlace: number? = nil
local RaceGo: number? = nil
local Others: { [any]: { Along: number, Position: Vector3 } } = {}
local FieldLast: number? = nil  -- the last runner's along (Race:Field)

-- // PRIVATE //--

local function Along(key: any, position: Vector3): number
	local along, segment = Track:Progress(position, Hints[key])
	Hints[key] = segment
	return along
end

local function Rebuild(courseName: string?)
	TrackName = courseName
	Track = CourseTrack.new(courseName and SpeedSim.FindCourse(courseName))
	table.clear(Hints)
	table.clear(Others)
	MapHolder.SetTrack(Track)
end

local function NewRun()
	Armed, StartedAt, EndedAt, RaceGo = true, nil, nil, nil
	table.clear(Hints)
	Backend:Finish(nil)
	GUIController.ShowHud()
end

local function Crossed()
	local _, way = Track:PointAt(Track.Length)
	Sounds:Finish()

	VFX:Burst("FinishRaceEmit", function() return Movement and Movement:GetPosition() end, way)
	ResultsHolder.Flash()
	ResultsHolder.HoldFor(FinishedHolder.Duration + 0.15)
	FinishedHolder.Play()
	GUIController.HideHud()
	Backend:Finish(way)

	task.delay(FinishedHolder.Duration + 2, function()
		if EndedAt and not ResultsHolder.Showing() then GUIController.ShowHud() end
	end)
end

local function OtherCrossed(id: any)
	local _, way = Track:PointAt(Track.Length)
	VFX:Burst("FinishRaceEmit", function()
		local other = Others[id]
		return other and other.Position
	end, way)
end

local function StepItem(now: number)
	if not Item or Item.Uses >= Item.MaxUses then return end
	Item.Since = Item.Since or now
	local share = (now - Item.Since) / HUD.ItemRecharge
	if share >= 1 then
		Item.Uses += 1
		Item.Since = if Item.Uses < Item.MaxUses then now else nil
		share = 0
	end
	ItemHolder.SetCharge(Item.Uses, share)
end

local function Step()
	local mv = Movement
	if not mv then return end
	Perf.Begin("Speed.Race")
	if mv.courseName ~= TrackName then Rebuild(mv.courseName) end
	local now = os.clock()
	local speed = mv:GetSpeed()
	SpeedHolder.SetSpeed(speed)
	local me = mv:GetPosition()
	local mine = if Track then Along("me", me) else 0

	if RaceGo and not StartedAt then
		local since = workspace:GetServerTimeNow() - RaceGo
		if since >= 0 then StartedAt, RaceGo = now - since, nil end
	end
	if Armed and speed > HUD.MoveToStart then Armed, StartedAt = false, now end
	if StartedAt and not EndedAt and Track and Track:Finished(mine, HUD.FinishReach) then
		EndedAt = now
		Crossed()
	end
	MatchInfoHolder.SetTime(if StartedAt then (EndedAt or now) - StartedAt else 0)
	MatchInfoHolder.SetLap(if Track then Track:Lap(mine) else 1, if Track then Track.Laps else 1)

	local place = 1
	local heads = { { Key = "me", Position = me, UserId = Player.UserId, Mine = true, Speed = speed } }
	local tags = {}
	local everyone = { { Along = mine } }
	local seen = {}
	for _, runner in Runners:List() do
		local along = if Track then Along(runner.Id, runner.Position) else 0
		if Track and along > mine then place += 1 end
		local last = Others[runner.Id]
		Others[runner.Id] = { Along = along, Position = runner.Position }
		seen[runner.Id] = true
		if Track and last and not Track:Finished(last.Along, HUD.FinishReach) and Track:Finished(along, HUD.FinishReach) then
			OtherCrossed(runner.Id)
		end
		table.insert(heads, { Key = runner.Id, Position = runner.Position, Speed = runner.Speed, Bot = runner.Bot,
			UserId = if runner.Player then runner.Player.UserId elseif runner.Bot then runner.Bot.UserId else nil })
		local tag = { Key = runner.Id, Position = runner.Position, Along = along, IsPlayer = runner.Player ~= nil,
			Name = if runner.Player then runner.Player.DisplayName elseif runner.Bot then runner.Bot.Name else "?",
			Tier = runner.Bot and runner.Bot.Tier,
			UserId = if runner.Player then runner.Player.UserId elseif runner.Bot then runner.Bot.UserId else nil,
			Avatar = if runner.Player then tostring(runner.Player.UserId) elseif runner.Bot then runner.Bot.Avatar else nil }
		table.insert(tags, tag)
		table.insert(everyone, tag)
	end
	local last = mine
	for id, other in Others do
		if not seen[id] then
			Others[id] = nil   -- (gone: left, or not drawn)
		else
			last = math.min(last, other.Along)
		end
	end
	FieldLast = if Track then last else nil
	table.sort(everyone, function(a, b) return a.Along > b.Along end)
	for i, entry in everyone do entry.Place = i end
	PlayerMarkers.Update(tags, if StartedAt then now - StartedAt else nil)   -- (markers over the runners near you)
	PlaceHolder.SetPlace(place)
	MapHolder.SetRunners(heads)
	if LastPlace and place < LastPlace then MapHolder.PopMine() end
	if #heads > 1 then Sounds:Place(place, LastPlace) end   -- (alone, it never changes)
	LastPlace = place
	StepItem(now)
	Perf.End()
end

local function Start()
	repeat
		Movement = Backend:GetMovement()
		if not Movement then task.wait(0.1) end
	until Movement
	Movement.RunStarted.Event:Connect(function(courseName)
		if courseName ~= TrackName then Rebuild(courseName) end
		NewRun()
	end)
	Rebuild(Movement.courseName)
	NewRun()
	RunService:BindToRenderStep("SpeedRace", Enum.RenderPriority.Camera.Value + 3, Step)
end

-- // PUBLIC //--

function Race:PreviewItem(name: string?, uses: number?)
	if not name then
		Item = nil
		ItemHolder.Clear()
		return
	end
	local max = math.clamp(math.floor(uses or 1), 1, 10)
	Item = { Name = name, Uses = max, MaxUses = max }
	ItemHolder.SetItem({ Name = name, Uses = max, MaxUses = max })
end

function Race:UseItem()
	if not Item or Item.Uses <= 0 then return end
	Item.Uses -= 1
	Item.Since = Item.Since or os.clock()
	ItemHolder.SetCharge(Item.Uses, 0)
	ItemHolder.Used()
end

function Race:Field(): (number?, any)
	return FieldLast, Track
end

function Race:Begin(goAt: number)
	NewRun()
	Armed, RaceGo = false, goAt
	ResultsHolder.Close(true)   -- a new race: the last one's results go
end

function Race:Results(json: string)
	local ok, payload = pcall(function() return game:GetService("HttpService"):JSONDecode(json) end)
	if ok and type(payload) == "table" then ResultsHolder.Update(payload, "P" .. Player.UserId) end
end

local LoadToken = 0
local SoundsLoaded = false

local function Preload(list: { Instance }, report: (number) -> ())
	local ContentProvider = game:GetService("ContentProvider")
	for i, item in list do
		pcall(function() ContentProvider:PreloadAsync({ item }) end)
		report(i / #list)
	end
end

function Race:Load(courseName: string, raceId: number)
	LoadToken += 1
	local token = LoadToken
	LoadingScreen.Show()
	MapClient:SetTurbo(true)
	task.spawn(function()
		local loading = SpeedConfig.Loading
		local done: { [string]: number } = {}
		local function Report()
			local total, status = 0, nil
			for _, stage in loading.Stages do
				local p = math.clamp(done[stage.Key] or 0, 0, 1)
				total += stage.Weight * p
				if not status and p < 1 then status = stage.Status end
			end
			LoadingScreen.Set(total, status or loading.Waiting)
		end
		local function Live(): boolean return token == LoadToken end
		-- the track: the course model on its way
		local world = workspace:WaitForChild("World")
		local courses = world:WaitForChild(SpeedConfig.Courses or "Courses")
		local course = courses:FindFirstChild(courseName)
		local since = os.clock()
		while not course and Live() and os.clock() - since < 30 do
			done.Track = math.min((os.clock() - since) / 3, 0.9)
			Report()
			task.wait(0.05)
			course = courses:FindFirstChild(courseName)
		end
		if not Live() then return end
		done.Track = 1

		while Live() and course and course.Parent do
			done.Ground = SpeedSim.FieldProgress(course)
			local paint, props = MapClient:LoadProgress(course)
			done.Paint, done.Props = paint, props
			Report()
			if done.Ground >= 1 and paint >= 1 and props >= 1 then break end
			task.wait()
		end
		if not Live() then return end
		MapClient:SetTurbo(false)

		local avatars = ReplicatedStorage:FindFirstChild(SpeedConfig.Avatars)
		local registry = ReplicatedStorage:FindFirstChild(SpeedConfig.Bots.Registry)
		local wanted = {}
		for _, player in Players:GetPlayers() do table.insert(wanted, tostring(player.UserId)) end
		for _, bot in if registry then registry:GetChildren() else {} do
			local key = bot:GetAttribute("Avatar")
			if type(key) == "string" then table.insert(wanted, key) end
		end
		local list = {}
		since = os.clock()
		for i, key in wanted do
			local model = avatars and avatars:FindFirstChild(key)
			while not model and Live() and avatars and os.clock() - since < 6 do
				task.wait(0.1)
				model = avatars:FindFirstChild(key)
			end
			if model then table.insert(list, model) end
			done.Runners = 0.5 * i / math.max(#wanted, 1)
			Report()
		end
		if not SoundsLoaded then
			local sounds = ReplicatedStorage:FindFirstChild("Assets")
			sounds = sounds and sounds:FindFirstChild("Speed") and sounds.Speed:FindFirstChild(SpeedConfig.Sound.Folder)
			if sounds then table.insert(list, sounds) end
			SoundsLoaded = true
		end
		Preload(list, function(share)
			done.Runners = 0.5 + 0.5 * share
			Report()
		end)
		if not Live() then return end
		done.Runners = 1
		Report()

		Backend:Request("loaded " .. raceId)
	end)
end

function Race:EndLoad()
	LoadToken += 1
	MapClient:SetTurbo(false)
	LoadingScreen.Hide()
end

function Race:Countdown(goAt: number?)
	local count = HUD.Countdown
	goAt = goAt or workspace:GetServerTimeNow() + count.Beats * count.Beat + count.Lead
	StartingHolder.Countdown(goAt :: number)
	Sounds:Countdown(goAt :: number)   -- its beeps, on the same beats
end

function Race:Init()
	if Started then return end
	Started = true
	task.spawn(Start)
end

return Race
