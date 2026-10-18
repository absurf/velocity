local Config = require(script.Parent.Parent.Configs.SpeedConfig)
local M = require(script.Parent.MathUtil)
local Traps = require(script.Parent.Traps)

local UP = Vector3.yAxis
local LOOK_EVERY = 0.1      -- s between looks for traps
local DODGE_HOLD = 0.7
local SHIFTS = { 0.5, 1, 1.6, 2.4, 3.2, 4.2 }
local STEPS = 6             -- points along the path it looks at
local SLIDE = 0.6
local BIG_LOOK = 1.7
local OVERSHOOT = 1.4
local DODGE_AHEAD = 0.45
local GAP_LOOK = { 0.3, 0.6, 1, 1.4 }

local BotBrain = {}
BotBrain.__index = BotBrain

local function Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function RightOf(dir: Vector3): Vector3
	local f = Flat(dir)
	if f.Magnitude < 1e-6 then return Vector3.xAxis end
	f = f.Unit
	return Vector3.new(-f.Z, 0, f.X)
end

function BotBrain.new(movement, data, tierName: string, seed: number)
	local self = setmetatable({}, BotBrain)
	self.mv, self.data = movement, data
	self.tierName = tierName
	self.tier = Config.Bots.Tiers[tierName] or Config.Bots.Tiers.Racer
	self.rng = Random.new(seed)
	self.noise = self.rng:NextNumber(0, 1000) + 0.37
	self.Along = 0
	self.LaunchAt = 0
	self.clock = 0
	self.nextLook = 0
	self.dodge, self.dodgeUntil = nil, 0
	self.sees = {}
	self.flightDive, self.flightMiss, self.wasGrounded = true, false, true
	self.lane = Config.Bots.ClearLane * (data.HalfWidth + (data.NoiseWidth or 0))   -- units: the clear lane's half width
	self.road = data.HalfWidth * 0.8
	return self
end

function BotBrain:Across(): number
	local p, dir = self.data.PointAt(self.Along)
	return (self.mv.pos - p):Dot(RightOf(dir))
end

function BotBrain:Blocked(near, shift: number, now: number, look: number): boolean
	local mv = self.mv
	local right = RightOf(mv.vel)
	local from = mv.pos + UP
	local prev = from
	for i = 1, STEPS do
		local tau = look * i / STEPS
		local q = from + mv.vel * tau + right * (shift * math.min(tau / SLIDE, 1))
		for _, trap in near do
			if Traps.Touches(trap, prev, q, now + tau) then return true end
		end
		prev = q
	end
	return false
end

function BotBrain:LookForTraps()
	local list = self.data.Traps
	if not (list and list[1]) then return end
	local mv, tier = self.mv, self.tier
	local look = tier.Look
	local reach = mv.vel.Magnitude * tier.Look * BIG_LOOK + 60
	local near = {}
	for _, trap in list do
		local d = trap.Along - self.Along
		if d > -40 and d < reach then
			local seen = self.sees[trap]
			if seen == nil then
				seen = self.rng:NextNumber() < (tier.Dodge[trap.Kind] or 0)
				self.sees[trap] = seen
			end
			if seen then
				table.insert(near, trap)
				if trap.Kind == "Cage" then look = tier.Look * BIG_LOOK end
			end
		end
	end
	if #near == 0 then return end
	local now = Traps.Clock()

	if self.dodge and self.clock < self.dodgeUntil then
		local keep = self.dodge - self:Across()
		if not self:Blocked(near, keep, now, look) then
			self.dodgeUntil = self.clock + DODGE_HOLD
			return
		end
	elseif not self:Blocked(near, 0, now, look) then
		return
	end

	local across = self:Across()
	for _, k in SHIFTS do
		for _, side in (if self.rng:NextNumber() < 0.5 then { 1, -1 } else { -1, 1 }) do
			local shift = side * k * self.lane
			if not self:Blocked(near, shift, now, look) then
				local right = RightOf(mv.vel)
				local _, dir = self.data.PointAt(self.Along)

				self.dodge = across + shift * OVERSHOOT * math.sign(right:Dot(RightOf(dir)) + 1e-6)
				self.dodgeUntil = self.clock + DODGE_HOLD
				return
			end
		end
	end
end

function BotBrain:Dive(): boolean
	local mv, tier = self.mv, self.tier
	local grounded = mv.isGrounded
	if self.wasGrounded and not grounded then
		self.flightDive = self.rng:NextNumber() < tier.Dive
		self.flightMiss = self.rng:NextNumber() < tier.GapMiss
	end
	self.wasGrounded = grounded
	if grounded or not self.flightDive or mv.sinceGrounded < tier.DiveLate then return false end
	local gapRim = self.data.GapRim
	if gapRim and not self.flightMiss then

		local p, v = mv.pos, Flat(mv.vel)
		if gapRim(p.X, p.Z) then return false end
		for _, tau in GAP_LOOK do
			local q = p + v * tau
			if gapRim(q.X, q.Z) then return false end
		end
	end
	return mv:autoDive()
end

function BotBrain:Input(inp, dt: number)
	local mv, data, tier = self.mv, self.data, self.tier
	self.clock += dt
	inp.y, inp.magnitude = 1, 1
	if mv.mode ~= "Fast" then
		inp.x, inp.y, inp.magnitude = 0, 0, 0
		local race = self.Race
		if race then
			local now = Traps.Clock()
			if now >= race.GoAt then
				mv:goFast()
				self.Race = nil
			elseif now >= race.JogAt then
				inp.y, inp.magnitude = 1, 1
			end
			inp.fastRunHeld = false
			return
		end
		inp.fastRunHeld = self.clock >= self.LaunchAt
		return
	end
	if mv.spawnCount ~= self.spawn then
		self.spawn, self.dodge, self.wasGrounded = mv.spawnCount, nil, true
	end
	local pos = mv.pos
	local _, dist, s = data.Road(pos.X, pos.Z)
	if dist ~= math.huge and s > 0 then self.Along = s end
	if self.clock >= self.nextLook then
		self.nextLook = self.clock + LOOK_EVERY
		self:LookForTraps()
	end

	local speed = mv.vel.Magnitude
	local dodging = self.dodge ~= nil and self.clock < self.dodgeUntil
	local ahead = math.max(speed * (if dodging then DODGE_AHEAD else 0.7), 12)
	local _, d0 = data.PointAt(self.Along)
	local p1, d1 = data.PointAt(self.Along + ahead)
	local right1 = RightOf(d1)
	local lane
	if dodging then
		lane = self.dodge
	else
		self.dodge = nil
		local wander = math.noise(self.clock / tier.Wander, self.noise, 0.5) * 2
		local bend = math.clamp((Flat(d1).Unit - Flat(d0).Unit):Dot(RightOf(d0)) * 4, -1, 1)
		lane = (math.clamp(wander, -1, 1) * tier.Lane + bend * tier.Inside) * self.lane
	end

	local limit = self.road
	local gapRim = data.GapRim
	if gapRim and (gapRim(pos.X, pos.Z) or gapRim(p1.X, p1.Z)) then limit = self.lane * 0.8 end
	lane = math.clamp(lane, -limit, limit)
	local target = p1 + right1 * lane
	local heading = Flat(mv.vel)
	if heading.Magnitude < 1e-3 then heading = Flat(mv.visualCF.LookVector) end
	local a = M.signedAngle(heading, Flat(target - pos), UP)
	inp.x = math.clamp(-a / 12 * tier.Steer, -1, 1)
	inp.dive = self:Dive()
end

return BotBrain
