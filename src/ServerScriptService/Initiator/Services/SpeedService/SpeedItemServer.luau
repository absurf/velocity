local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local Generated = require(ReplicatedStorage.Shared.Modules.Speed.Courses.Generated)
local SpeedServiceServer = require(script.Parent.SpeedServiceServer)
local SpeedMapServer = require(script.Parent.SpeedMapServer)
local SpeedBotServer = require(script.Parent.SpeedBotServer)

local Service = {}
type Service = typeof(Service)

local ITEMS = SpeedConfig.Items
local CARDS = ITEMS and ITEMS.Cards
local S = SpeedConfig.Studs
local BOT_EVERY = 0.1   -- s between the bots' card / item checks
local NAMES = { grapple = "Grapple", gator = "Gator", drink = "Drink", energy = "Drink", ["energy drink"] = "Drink",
	ink = "Ink", shotgun = "Shotgun" }

-- [ STATE ]--
local Started = false
local Map: Instance? = nil
local Data: any = nil
local Cards: { any } = {}
local Taken: { [number]: number } = {}         -- card id -> server time it's back
local Held: { [number]: string } = {}          -- runner id -> what it holds
local BotUseAt: { [number]: number } = {}
local Ropes: { [number]: number } = {}         -- runner id -> server time its rope ends
local Gators: { [number]: any } = {}
local NextGator = 0
local Rng = Random.new()
local NextBots = 0

-- // PRIVATE //--

local function Tell(player: Player, value: string)
	SpeedServiceServer:Command(player, "items", value)
end

local function TellAll(value: string)
	for _, player in Players:GetPlayers() do Tell(player, value) end
end

local function IdOf(player: Player): number?
	local id = player:GetAttribute("SpeedId")
	return if type(id) == "number" then id else nil
end

local EveryoneNow: { any }? = nil
local function Everyone(): { any }
	if EveryoneNow then return EveryoneNow end
	local list = {}
	for _, player in Players:GetPlayers() do
		local id = IdOf(player)
		local runner = id and SpeedServiceServer:GetRunner(player)
		if runner and runner.Last then
			table.insert(list, { Id = id, Position = runner.Last.Position, Velocity = runner.Last.Velocity, Player = player })
		end
	end
	SpeedBotServer:Each(function(id, sim)
		table.insert(list, { Id = id, Position = sim:GetPosition(), Velocity = sim:GetVelocity(), Sim = sim })
	end)
	EveryoneNow = list
	return list
end

local function Find(id: number): any?
	for _, runner in Everyone() do
		if runner.Id == id then return runner end
	end
	return nil
end

local function AlongOf(position: Vector3): number
	if not (Data and Data.Road) then return 0 end
	local _, _, s = Data.Road(position.X / S, position.Z / S)
	return s or 0
end

local function SetHeld(id: number, item: string?, player: Player?)
	Held[id] = item
	if player then Tell(player, if item then "got " .. item else "spent") end
	TellAll(("hand %d %s"):format(id, item or "none"))
end

local function Roll(): string
	local total = 0
	for _, weight in ITEMS.Pool do total += weight end
	local pick = Rng:NextNumber() * total
	for name, weight in ITEMS.Pool do
		pick -= weight
		if pick <= 0 then return name end
	end
	return "Grapple"
end

local function Refresh()
	local map = SpeedMapServer:Current()
	if map == Map then return end
	Map = map
	Data, Cards, Taken, Ropes, Gators = nil, {}, {}, {}, {}
	table.clear(Held)
	table.clear(BotUseAt)
	if map and map:GetAttribute("Heightfield") == "Generated" then
		local ok, data = pcall(Generated.ForCourse, map)
		if ok and data then
			Data = data
			Cards = data.Cards or {}
		end
	end
	TellAll("reset")
end

local function Recent(player: Player): { Vector3 }
	local runner = SpeedServiceServer:GetRunner(player)
	local list = {}
	if not (runner and runner.Last) then return list end
	local now = runner.Last.T
	for i = #runner.History, 1, -1 do
		local state = runner.History[i]
		if now - state.T > 0.5 then break end
		table.insert(list, state.Position)
	end
	if #list == 0 then table.insert(list, runner.Last.Position) end
	return list
end

local function Take(card, now: number)
	Taken[card.Id] = now + CARDS.Respawn
	TellAll(("card %d %.3f"):format(card.Id, Taken[card.Id]))
end

local function Got(id: number, player: Player?)
	if Held[id] then return end
	SetHeld(id, Roll(), player)
	if not player then
		local wait = ITEMS.BotUse or { 1.5, 4 }
		BotUseAt[id] = workspace:GetServerTimeNow() + Rng:NextNumber(wait[1], wait[2])
	end
end

local function SlowRunner(runner, keep: number)
	if runner.Player then
		Tell(runner.Player, ("slow %.3f"):format(keep))
	elseif runner.Sim then
		runner.Sim:Slow(keep)
	end
end

local function UseGrappleOn(from, target)
	local G = ITEMS.Grapple
	local now = workspace:GetServerTimeNow()
	Ropes[from.Id] = now + G.Pull
	TellAll(("rope %d runner %d %.3f"):format(from.Id, target.Id, Ropes[from.Id]))
	if target.Player then
		Tell(target.Player, ("yank %d %.2f"):format(from.Id, G.Yank))
	elseif target.Sim then
		local fromId = from.Id
		target.Sim:Yank(function()
			local r = Find(fromId)
			return r and r.Position
		end, G.Yank)
	end
	if from.Sim then   -- (a bot fires it: its own pull runs here)
		local toId = target.Id
		from.Sim:Grapple(function()
			local r = Find(toId)
			return r and r.Position
		end)
	end
end

local function UseShotgun(from, target)
	local SG = ITEMS.Shotgun
	local d = (target.Position - from.Position).Magnitude

	local hits = 0
	local within = math.deg(math.atan2(SG.Body, math.max(d, 1)))
	for _ = 1, SG.Pellets do
		local off = math.sqrt(Rng:NextNumber()) * SG.Spread   -- (even over the cone's disc)
		if off <= within then hits += 1 end
	end
	local share = hits / SG.Pellets
	local kill = share * (SG.Near + (SG.Far - SG.Near) * math.clamp(d / SG.Range, 0, 1))
	local keep = 1 - kill
	if hits > 0 then SlowRunner(target, keep) end
	TellAll(("fx shot %d %d %.3f"):format(from.Id, target.Id, keep))
end

local function UseGator(from)
	local GA = ITEMS.Gator

	local mine = AlongOf(from.Position)
	local target, best = nil, math.huge
	for _, runner in Everyone() do
		if runner.Id ~= from.Id then
			local along = AlongOf(runner.Position)
			if along > mine and along < best then target, best = runner, along end
		end
	end
	NextGator += 1
	local way = if from.Velocity.Magnitude > 1 then from.Velocity.Unit else Vector3.new(0, 0, -1)
	Gators[NextGator] = {
		Id = NextGator, From = from.Id, Target = target and target.Id, Born = workspace:GetServerTimeNow(),
		Position = from.Position + Vector3.new(0, GA.Hover, 0) + way * 8, Velocity = way * math.max(from.Velocity.Magnitude * 1.2, GA.MinSpeed),
		Flown = 0,
	}
	TellAll(("gator %d %d %d"):format(NextGator, from.Id, target and target.Id or 0))
end

local function StepGators(dt: number)
	local GA = ITEMS.Gator
	local now = workspace:GetServerTimeNow()
	for id, g in Gators do
		local target = g.Target and Find(g.Target)
		local gone = now - g.Born > GA.Life or (not target and g.Flown > GA.Forward)
		if gone then
			Gators[id] = nil
			TellAll(("gatorend %d"):format(id))
			continue
		end
		if target then
			local aim = target.Position + Vector3.new(0, GA.Hover, 0)
			local to = aim - g.Position
			if to.Magnitude <= GA.Hit then
				Gators[id] = nil
				SlowRunner(target, GA.Keep)
				TellAll(("gatorhit %d %d"):format(id, target.Id))
				continue
			end
			local speed = math.max(GA.MinSpeed, target.Velocity.Magnitude * GA.Speed)

			local dist = to.Magnitude
			if dist < (GA.Commit or 60) then
				g.Velocity = to.Unit * speed
			else
				local turn = GA.Turn * (1 + 4 * math.clamp(1 - dist / 300, 0, 1))
				g.Velocity = g.Velocity:Lerp(to.Unit * speed, math.min(dt * turn, 1))
				if g.Velocity.Magnitude < speed then g.Velocity = g.Velocity.Unit * speed end
			end
		end
		local step = g.Velocity * dt
		g.Position += step
		g.Flown += step.Magnitude
	end
end

local function CardRequest(player: Player, id: number)
	local card = Cards[id]
	local me = IdOf(player)
	local now = workspace:GetServerTimeNow()

	local function No()
		if card then Tell(player, ("card %d %.3f"):format(id, if Taken[id] and now < Taken[id] then Taken[id] else 0)) end
	end
	if not card or not me or (Taken[id] and now < Taken[id]) then No() return end
	for _, position in Recent(player) do
		if (position + Vector3.new(0, 2.5, 0) - card.Position).Magnitude <= CARDS.Reach + CARDS.Slack then
			Take(card, now)
			Got(me, player)
			return
		end
	end
	No()
end

local function UseRequest(player: Player, words: { string })
	local me = IdOf(player)
	if not me then return end
	local held = Held[me]
	local from = Find(me)
	if not (held and from) then return end
	local what = words[1] == "grapple" and "Grapple" or (NAMES[words[2] or ""] or "")
	if what ~= held then return end
	local slack = CARDS.Slack
	if held == "Grapple" then
		local G = ITEMS.Grapple
		if words[2] == "runner" then
			local target = Find(tonumber(words[3]) or -1)
			if not target or (target.Position - from.Position).Magnitude > G.Range * 1.4 + slack then return end
			SetHeld(me, nil, player)
			UseGrappleOn(from, target)
		elseif words[2] == "point" then
			local point = Vector3.new(tonumber(words[3]) or 0, tonumber(words[4]) or 0, tonumber(words[5]) or 0)
			if (point - from.Position).Magnitude > G.Range * 1.4 + slack then return end
			SetHeld(me, nil, player)
			Ropes[me] = workspace:GetServerTimeNow() + G.Hold
			TellAll(("rope %d point %.1f %.1f %.1f %.3f"):format(me, point.X, point.Y, point.Z, Ropes[me]))
		end
	elseif held == "Drink" then
		SetHeld(me, nil, player)
		TellAll(("fx drink %d %.3f"):format(me, workspace:GetServerTimeNow() + ITEMS.Drink.Seconds))
	elseif held == "Ink" then
		SetHeld(me, nil, player)
		TellAll(("ink %d"):format(me))
	elseif held == "Shotgun" then
		local target = Find(tonumber(words[3]) or -1)
		if not target or (target.Position - from.Position).Magnitude > ITEMS.Shotgun.Range * 1.3 + slack then return end
		SetHeld(me, nil, player)
		UseShotgun(from, target)
	elseif held == "Gator" then
		SetHeld(me, nil, player)
		UseGator(from)
	end
end

local function BotUse(bot, now: number)
	local item = Held[bot.Id]
	local way = if bot.Velocity.Magnitude > 1 then bot.Velocity.Unit else Vector3.new(0, 0, -1)
	local function Ahead(range: number)
		local best, bestD = nil, math.huge
		for _, runner in Everyone() do
			if runner.Id ~= bot.Id then
				local to = runner.Position - bot.Position
				local d = to.Magnitude
				if d > 10 and d <= range and to.Unit:Dot(way) > 0.8 and d < bestD then best, bestD = runner, d end
			end
		end
		return best
	end
	if item == "Grapple" or item == "Shotgun" then
		local target = Ahead(if item == "Grapple" then (ITEMS.Grapple.RunnerRange or ITEMS.Grapple.Range) else ITEMS.Shotgun.Range)
		if not target then
			BotUseAt[bot.Id] = now + 0.5
			return
		end
		SetHeld(bot.Id, nil)
		if item == "Grapple" then UseGrappleOn(bot, target) else UseShotgun(bot, target) end
	elseif item == "Drink" then
		SetHeld(bot.Id, nil)
		bot.Sim:Boost(ITEMS.Drink.Boost, ITEMS.Drink.Seconds)
		TellAll(("fx drink %d %.3f"):format(bot.Id, now + ITEMS.Drink.Seconds))
	elseif item == "Ink" then
		SetHeld(bot.Id, nil)
		TellAll(("ink %d"):format(bot.Id))
	elseif item == "Gator" then
		SetHeld(bot.Id, nil)
		UseGator(bot)
	end
	BotUseAt[bot.Id] = nil
end

local function StepBots()
	local now = workspace:GetServerTimeNow()
	if now < NextBots then return end
	NextBots = now + BOT_EVERY
	local reach = CARDS.Reach + 4
	for _, bot in Everyone() do
		if not bot.Sim then continue end
		local at = bot.Position + Vector3.new(0, 2.5, 0)
		for _, card in Cards do
			if (not Taken[card.Id] or now >= Taken[card.Id]) and (card.Position - at).Magnitude <= reach then
				Take(card, now)
				Got(bot.Id, nil)
			end
		end
		local useAt = BotUseAt[bot.Id]
		if useAt and now >= useAt and Held[bot.Id] then BotUse(bot, now) end
	end

	for id in BotUseAt do
		if not Find(id) then BotUseAt[id], Held[id] = nil, nil end
	end
end

-- // PUBLIC //--

function Service.Request(_self: Service, player: Player, action: string): boolean
	local words = string.split(action, " ")
	if words[1] == "card" then
		Refresh()
		CardRequest(player, tonumber(words[2]) or -1)
		return true
	elseif words[1] == "grapple" then
		if words[2] == "off" then
			local me = IdOf(player)
			if me and Ropes[me] then
				Ropes[me] = nil
				TellAll(("rope %d off"):format(me))
			end
		else
			UseRequest(player, words)
		end
		return true
	elseif words[1] == "use" then
		UseRequest(player, words)
		return true
	end
	return false
end

function Service.Give(_self: Service, player: Player, name: string): string?
	local item = NAMES[string.lower(name or "")]
	local id = IdOf(player)
	if not item then return ("no item %q (grapple, gator, drink, ink, shotgun)"):format(tostring(name)) end
	if not id then return player.Name .. " isn't running" end
	SetHeld(id, item, player)
	return nil
end

function Service.Holding(_self: Service, player: Player): string?
	local id = IdOf(player)
	return id and Held[id]
end

function Service.Init(_self: Service)
	if Started or not CARDS then return end
	Started = true
	Players.PlayerRemoving:Connect(function(player)
		local id = IdOf(player)
		if id then Held[id], Ropes[id] = nil, nil end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.delay(4, function()
			if not player.Parent then return end
			local now = workspace:GetServerTimeNow()
			for id, item in Held do Tell(player, ("hand %d %s"):format(id, item)) end
			for id, back in Taken do
				if back > now then Tell(player, ("card %d %.3f"):format(id, back)) end
			end
		end)
	end)
	RunService.Heartbeat:Connect(function(dt)
		EveryoneNow = nil
		Refresh()
		StepBots()
		if next(Gators) then StepGators(dt) end
	end)
end

return Service :: Service
