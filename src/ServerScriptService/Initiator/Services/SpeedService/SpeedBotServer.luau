local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local SpeedSim = require(ReplicatedStorage.Shared.Modules.Speed.SpeedSim)
local BotBrain = require(ReplicatedStorage.Shared.Modules.Speed.BotBrain)
local RunnerPack = require(ReplicatedStorage.Shared.Modules.Speed.RunnerPack)
local Generated = require(ReplicatedStorage.Shared.Modules.Speed.Courses.Generated)
local SpeedServiceServer = require(script.Parent.SpeedServiceServer)
local SpeedMapServer = require(script.Parent.SpeedMapServer)
local SpeedAvatarServer = require(script.Parent.SpeedAvatarServer)

local Service = {}
type Service = typeof(Service)

local BOTS = SpeedConfig.Bots
local LAUNCH = { 0.5, 2.5 }
local DONE_SEND = 0.5

type Bot = {
	Id: number, Name: string, Tier: string, Key: string,
	Sim: any, Brain: any, Course: Instance, Length: number,
	NextSend: number, Done: number?, Entry: Configuration,
}

-- [ STATE ]--
local Started = false
local Bots: { Bot } = {}
local Registry: Folder
local Wanted: { Difficulty: string, Count: number? }? = nil
local Filling = false
local Seeds = Random.new()

-- // PRIVATE //--

local function Tiers(difficulty: string, count: number): { string }
	local mix = BOTS.Mix[difficulty]
	local total = 0
	for _, n in mix do total += n end
	local list, rest = {}, {}
	for _, tier in { "Pro", "Racer", "Rookie" } do
		local exact = count * (mix[tier] or 0) / math.max(total, 1)
		for _ = 1, math.floor(exact) do table.insert(list, tier) end
		table.insert(rest, { Tier = tier, Left = exact - math.floor(exact) })
	end
	table.sort(rest, function(a, b) return a.Left > b.Left end)
	local i = 1
	while #list < count do
		table.insert(list, rest[(i - 1) % #rest + 1].Tier)
		i += 1
	end
	return list
end

local function Pick(rng: Random, list: { any }): any
	return list[rng:NextInteger(1, #list)]
end

local function Outfit(rng: Random): HumanoidDescription
	local pool = BOTS.Outfits
	local d = Instance.new("HumanoidDescription")
	d.Shirt = Pick(rng, pool.Shirt)
	d.Pants = Pick(rng, pool.Pants)
	d.HairAccessory = tostring(Pick(rng, pool.Hair))
	if rng:NextNumber() < pool.HatChance then d.HatAccessory = tostring(Pick(rng, pool.Hat)) end
	local skin = Pick(rng, pool.Skin)
	d.HeadColor, d.TorsoColor, d.LeftArmColor, d.RightArmColor, d.LeftLegColor, d.RightLegColor = skin, skin, skin, skin, skin, skin
	return d
end

local function Report(bot: Bot): buffer
	local sim = bot.Sim
	local inp = sim.input
	local done = bot.Done ~= nil
	return RunnerPack.Encode({
		T = workspace:GetServerTimeNow(),
		Position = sim:GetPosition(),
		Velocity = if done then Vector3.zero else sim:GetVelocity(),
		Rotation = sim.visualCF,
		Yaw = sim.yaw,
		TimeScale = sim:GetTimeScale(),
		Spawn = sim.spawnCount or 0,
		Grounded = done or sim.isGrounded,
		MostlyGrounded = done or sim.mostlyGrounded,
		Dive = not done and inp.dive,
		Slow = sim.mode == "Slow",
		FastRun = not done and inp.fastRunHeld,
		Ball = false,
		Bad = not done and RunnerPack.JustBad(sim),
		InputX = if done then 0 else inp.x,
		InputY = if done then 0 else inp.y,
	})
end

local FRIENDS_KEEP = 600
local FriendsOf: { [number]: { At: number, List: { any } } } = {}
local Descriptions: { [number]: HumanoidDescription } = {}
local function Friends(): { { Id: number, Name: string } }
	local list, seen = {}, {}
	if not BOTS.Friends then return list end
	for _, player in Players:GetPlayers() do seen[player.UserId] = true end
	for _, player in Players:GetPlayers() do
		if player.UserId <= 0 then continue end   -- (Studio's test players)
		local cached = FriendsOf[player.UserId]
		if not cached or os.clock() - cached.At > FRIENDS_KEEP then
			local theirs = {}
			local ok, pages = pcall(function() return Players:GetFriendsAsync(player.UserId) end)
			if ok and pages then
				local read = 0
				while read < BOTS.FriendsRead do
					for _, friend in pages:GetCurrentPage() do
						read += 1
						local name = friend.DisplayName
						if type(name) ~= "string" or name == "" then name = friend.Username end
						table.insert(theirs, { Id = friend.Id, Name = tostring(name) })
					end
					if pages.IsFinished then break end
					if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
				end
			end
			cached = { At = os.clock(), List = theirs }
			FriendsOf[player.UserId] = cached
		end
		for _, friend in cached.List do
			if not seen[friend.Id] then
				seen[friend.Id] = true
				table.insert(list, friend)
			end
		end
	end
	for i = #list, 2, -1 do
		local j = Seeds:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function Dress(key: string, friendId: number?, rng: Random)
	if friendId then
		local description = Descriptions[friendId]
		if not description then
			local ok, got = pcall(function() return Players:GetHumanoidDescriptionFromUserIdAsync(friendId) end)
			if ok and got then
				description = got
				Descriptions[friendId] = got
			end
		end
		if description and SpeedAvatarServer:BuildFrom(key, description:Clone()) then return end
	end
	SpeedAvatarServer:BuildFrom(key, Outfit(rng))
end

local function Remove(bot: Bot)
	SpeedServiceServer:RemoveBot(bot.Id)
	SpeedAvatarServer:Remove(bot.Key)
	bot.Entry:Destroy()
	bot.Sim:Destroy()
end

local function ClearAll()
	for _, bot in Bots do Remove(bot) end
	table.clear(Bots)
end

local function Step(dt: number)
	if #Bots == 0 then

		local current = SpeedMapServer:Current()
		if Wanted and not Filling and current and Wanted.Map ~= current then
			task.spawn(Service.Fill, Service, Wanted.Difficulty, Wanted.Count)
		end
		return
	end
	local current = SpeedMapServer:Current()
	if Bots[1].Course ~= current or not Bots[1].Course.Parent then
		ClearAll()   -- (refilled on the next step, if wanted)
		return
	end
	local clock = os.clock()
	local finish = (SpeedConfig.Hud.FinishReach or 40) / SpeedConfig.Studs
	for _, bot in Bots do
		local sim = bot.Sim

		local still = bot.Done and sim.mode == "Slow" and sim.vel.Magnitude < 0.5
		if not still then
			sim:FrameInput(dt)
			sim:Step(dt)
		end
		if not bot.Done and bot.Brain.Along >= bot.Length - finish then
			bot.Done = workspace:GetServerTimeNow()
			bot.Entry:SetAttribute("Finished", bot.Done)
			sim:Finish(bot.FinishWay)
		end
		if clock >= bot.NextSend then
			bot.NextSend = clock + (if still then DONE_SEND else 1 / SpeedConfig.Net.SendRate)
			SpeedServiceServer:BotState(bot.Id, Report(bot))
		end
	end
end

-- // PUBLIC //--

function Service.Fill(_self: Service, difficulty: string?, count: number?, race: any?): (number, string?)
	if Filling then return 0, "already filling" end
	difficulty = difficulty or BOTS.Difficulty
	if not BOTS.Mix[difficulty] then return 0, ("no difficulty %q (Easy / Normal / Hard)"):format(tostring(difficulty)) end
	local course = SpeedMapServer:Current()
	if not course then
		Wanted = { Difficulty = difficulty, Count = count }
		return 0, "no generated map up: they'll join the next `map`"
	end
	Filling = true
	ClearAll()
	Wanted = { Difficulty = difficulty, Count = count, Map = course }
	local data = Generated.ForCourse(course)
	local want = math.clamp(math.floor(count or (BOTS.Field - #Players:GetPlayers())), 0, 31)
	local tiers = Tiers(difficulty, want)
	local friends = Friends()

	local names = table.clone(BOTS.Names)
	for i = #names, 2, -1 do
		local j = Seeds:NextInteger(1, i)
		names[i], names[j] = names[j], names[i]
	end
	local start = course:FindFirstChild("Start")
	local startCF = if start and start:IsA("BasePart") then start.CFrame else data.Start
	local grid = BOTS.Grid
	for i, tier in tiers do
		if SpeedMapServer:Current() ~= course then break end   -- (a new map came up meanwhile)
		local rng = Random.new(Seeds:NextInteger(1, 2 ^ 30))
		local id = SpeedServiceServer:AddBot()
		local key = "Bot" .. id
		local sim = SpeedSim.new()
		sim.headless = true
		sim:SetBody("Human")
		sim:SetCourse(course.Name)
		local slot = race and race.Slots[i]
		if slot then
			sim:RespawnStill(slot)
		else
			local row, col = (i - 1) // grid.PerRow, (i - 1) % grid.PerRow
			local across = (col - (grid.PerRow - 1) / 2) * grid.Across
			sim:RespawnStill(startCF * CFrame.new(across, 0, (row + 1) * grid.Back))   -- behind the start (+z is back)
		end
		local brain = BotBrain.new(sim, data, tier, rng:NextInteger(1, 2 ^ 30))
		brain.LaunchAt = rng:NextNumber(LAUNCH[1], LAUNCH[2])
		if race then brain.Race = { JogAt = race.JogAt, GoAt = race.GoAt } end
		local record: any = nil
		sim:SetInputSource(function(input, frameDt)
			if record and record.Done then

				input.x, input.y, input.magnitude, input.lookX, input.lookY = 0, 0, 0, 0, 0
				input.dive, input.fastRunHeld, input.fastRunPressed = false, false, false
				return
			end
			brain:Input(input, frameDt)
		end)
		local friend = friends[i]
		local name = if friend then friend.Name else names[(i - 1) % #names + 1]
		local entry = Instance.new("Configuration")
		entry.Name = tostring(id)
		entry:SetAttribute("Name", name)
		if friend then entry:SetAttribute("UserId", friend.Id) end
		entry:SetAttribute("Tier", tier)
		entry:SetAttribute("Avatar", key)
		entry:SetAttribute("Difficulty", difficulty)
		entry.Parent = Registry
		local _, finishWay = data.PointAt(data.Line.Length)
		record = { Id = id, Name = name, Tier = tier, Key = key, Sim = sim, Brain = brain, Course = course,
			Length = data.Line.Length, FinishWay = finishWay, NextSend = 0, Entry = entry }
		table.insert(Bots, record)
		task.spawn(Dress, key, friend and friend.Id, rng)
	end
	Filling = false
	return #Bots, nil
end

function Service.Clear(_self: Service)
	Wanted = nil
	ClearAll()
end

function Service.SetRace(_self: Service, jogAt: number, goAt: number)
	for _, bot in Bots do
		bot.Brain.Race = { JogAt = jogAt, GoAt = goAt }
	end
end

function Service.Each(_self: Service, fn: (number, any) -> ())
	for _, bot in Bots do fn(bot.Id, bot.Sim) end
end

function Service.List(_self: Service)
	local list = {}
	for _, bot in Bots do
		table.insert(list, { Id = bot.Id, Name = bot.Name, Tier = bot.Tier, Along = bot.Brain.Along * SpeedConfig.Studs, Done = bot.Done,
			UserId = bot.Entry:GetAttribute("UserId") })
	end
	return list
end

function Service.Init(_self: Service)
	if Started then return end
	Started = true
	Registry = ReplicatedStorage:FindFirstChild(BOTS.Registry) :: Folder
	if not Registry then
		Registry = Instance.new("Folder")
		Registry.Name = BOTS.Registry
		Registry.Parent = ReplicatedStorage
	end
	RunService.Heartbeat:Connect(Step)
end

return Service :: Service
