local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local CourseTrack = require(ReplicatedStorage.Shared.Modules.Speed.CourseTrack)
local SpeedServiceServer = require(script.Parent.SpeedServiceServer)
local SpeedMapServer = require(script.Parent.SpeedMapServer)
local SpeedBotServer = require(script.Parent.SpeedBotServer)

local Service = {}
type Service = typeof(Service)

local RACE = SpeedConfig.Race

type Racer = {
	Key: string, Name: string, UserId: number?, Bot: boolean,
	Player: Player?, BotId: number?,
	Hint: number,
	Along: number,     -- studs along the line
	Time: number?,     -- s from GO to over the line
}

-- [ STATE ]--
local Started = false
local Current: any = nil
local RaceIds = 0
local AutoStarting = false

-- // PRIVATE //--

local function Payload(race): string
	local finished, rest = {}, {}
	for _, r in race.Racers do
		table.insert(if r.Time then finished else rest, r)
	end
	table.sort(finished, function(a, b) return a.Time < b.Time end)
	table.sort(rest, function(a, b) return a.Along > b.Along end)
	local rows = {}
	local function Row(r, place)
		table.insert(rows, { Key = r.Key, Name = r.Name, UserId = r.UserId, Bot = r.Bot, Time = r.Time, Place = place })
	end
	for i, r in finished do Row(r, i) end
	if race.Over then
		for _, r in rest do Row(r, #rows + 1) end
	end
	return HttpService:JSONEncode({ Race = race.Id, Course = race.Course.Name, GoAt = race.GoAt, Over = race.Over,
		Deadline = race.Deadline, NextAt = race.NextAt, Rows = rows })
end

local function Send(race)
	SpeedServiceServer:Results(Payload(race))
end

local function Autoplaying(): boolean
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("SpeedAutoplay") == true then return true end
	end
	return false
end

local function NextDelay(): number
	return if Autoplaying() then (RACE.AutoNext or RACE.Next) else RACE.Next
end

local function Next(race)
	if race.Starting then return end
	race.Starting = true
	task.spawn(function()
		local ok, err = pcall(Service.Start, Service, nil, race.Difficulty)
		if not ok then warn("[SpeedRace] the next race didn't start: " .. tostring(err)) end
	end)
end

local function Go(race)
	if not race.Loading then return end
	race.Loading = false
	local introAt = workspace:GetServerTimeNow() + RACE.Reveal
	local goAt = introAt + RACE.Hold + RACE.Sweep + RACE.Count
	race.GoAt = goAt
	SpeedBotServer:SetRace(goAt - RACE.Count, goAt)
	for i, player in race.Players do
		if not player.Parent then continue end
		local cf = race.Slots[race.BotCount + i]
		local p, look = cf.Position, cf.LookVector
		SpeedServiceServer:Command(player, "race", ("%s %.3f %.3f %.3f %.5f %.5f %.4f %.4f"):format(
			race.Course.Name, p.X, p.Y, p.Z, look.X, look.Z, introAt, goAt))
	end
end

local function Step()
	local race = Current
	if not race then

		if Autoplaying() and not AutoStarting then
			AutoStarting = true
			task.spawn(function()
				local ok, err = pcall(Service.Start, Service, nil, nil)
				if not ok then warn("[SpeedRace] autoplay couldn't start a race: " .. tostring(err)) end
				task.wait(2)
				AutoStarting = false
			end)
		end
		return
	end
	if race.Loading then

		for player in race.Waiting do
			if not player.Parent then race.Waiting[player] = nil end
		end
		if next(race.Waiting) == nil or workspace:GetServerTimeNow() >= race.LoadBy then Go(race) end
		return
	end
	if not race.Course.Parent then
		-- a `map` (or another race) replaced it
		Current = nil
		SpeedServiceServer:Results(HttpService:JSONEncode({ Race = race.Id, Closed = true }))
		return
	end
	local now = workspace:GetServerTimeNow()
	if now < race.GoAt then return end
	local changed = false
	local reach = SpeedConfig.Hud.FinishReach or 40
	local bots = nil
	for key, r in race.Racers do
		if r.Time then continue end
		if r.Player then
			if not r.Player.Parent then
				race.Racers[key] = nil   -- left the game: out of the race
				changed = true
				continue
			end
			local runner = SpeedServiceServer:GetRunner(r.Player)
			local last = runner and runner.Last
			if last and last.T >= race.GoAt and race.Track then
				local along, segment = race.Track:Progress(last.Position, r.Hint)
				r.Hint, r.Along = segment, along
				if race.Track:Finished(along, reach) then
					r.Time = last.T - race.GoAt
					changed = true
				end
			end
		elseif r.BotId then
			if not bots then
				bots = {}
				for _, bot in SpeedBotServer:List() do bots[bot.Id] = bot end
			end
			local bot = bots[r.BotId]
			if bot then
				r.Along = bot.Along or r.Along
				if bot.Done then
					r.Time = bot.Done - race.GoAt
					changed = true
				end
			end
		end
	end
	if changed and not race.Deadline then
		for _, r in race.Racers do
			if r.Time then race.Deadline = now + RACE.DNF break end   -- the winner's over: the rest have DNF s
		end
	end
	if not race.Over then
		local all = true
		for _, r in race.Racers do
			if not r.Time then all = false break end
		end
		if all or (race.Deadline and now >= race.Deadline) then
			race.Over, race.NextAt = true, now + NextDelay()
			changed = true
		end
	end

	if race.Over and race.NextAt and race.NextAt - now > NextDelay() + 0.5 then
		race.NextAt = now + NextDelay()
		changed = true
	end
	if changed then Send(race) end
	if race.Over and now >= race.NextAt then Next(race) end
end

-- // PUBLIC //--

function Service.Start(_self: Service, seed: number?, difficulty: string?): (string, string?)
	difficulty = difficulty or "Normal"
	local bots = difficulty ~= "Off"
	if bots and not SpeedConfig.Bots.Mix[difficulty] then return "", ("no difficulty %q"):format(difficulty) end
	local model, data = SpeedMapServer:New(seed)
	local players = Players:GetPlayers()
	local botCount = if bots then math.max(SpeedConfig.Bots.Field - #players, 0) else 0

	local slots = {}
	for slot = 0, botCount + #players - 1 do slots[slot + 1] = data.RaceSlot(slot) end

	RaceIds += 1
	local id = RaceIds
	for _, player in players do
		SpeedServiceServer:Command(player, "load", ("%s %d"):format(model.Name, id))
	end
	if botCount > 0 then

		SpeedBotServer:Fill(difficulty, botCount, { Slots = slots, JogAt = math.huge, GoAt = math.huge })
	else
		SpeedBotServer:Clear()
	end

	local racers = {}
	for _, bot in SpeedBotServer:List() do
		local key = "B" .. bot.Id
		racers[key] = { Key = key, Name = bot.Name, UserId = bot.UserId, Bot = true, BotId = bot.Id, Hint = 1, Along = 0 }
	end
	for _, player in players do
		local key = "P" .. player.UserId
		racers[key] = { Key = key, Name = player.DisplayName, UserId = player.UserId, Bot = false, Player = player, Hint = 1, Along = 0 }
	end
	local waiting = {}
	for _, player in players do waiting[player] = true end
	Current = { Id = id, Course = model, Track = CourseTrack.new(model), GoAt = math.huge, Difficulty = difficulty,
		Racers = racers, Over = false, Loading = true, Waiting = waiting, LoadBy = workspace:GetServerTimeNow() + RACE.LoadTimeout,
		Players = players, Slots = slots, BotCount = botCount }
	return ("race on %s: %d players at the back, %d bots (%s); loading on every screen, then GO"):format(model.Name, #players, botCount,
		if bots then difficulty else "off")
end

function Service.Request(_self: Service, player: Player, action: any)
	if type(action) ~= "string" then return end
	local loaded = tonumber(action:match("^loaded (%d+)$"))
	if loaded then

		local race = Current
		if race and race.Id == loaded and race.Loading then race.Waiting[player] = nil end
		return
	end
	if action ~= "raceagain" then return end
	local race = Current
	if not race or race.Starting then return end
	local me = race.Racers["P" .. player.UserId]

	if race.Over or (me and me.Time) then Next(race) end
end

function Service.SetAutoplay(_self: Service, players: { Player }, on: boolean)
	for _, player in players do player:SetAttribute("SpeedAutoplay", on) end
end

function Service.Current(_self: Service)
	return Current
end

function Service.Init(_self: Service)
	if Started then return end
	Started = true
	RunService.Heartbeat:Connect(Step)
end

return Service :: Service
