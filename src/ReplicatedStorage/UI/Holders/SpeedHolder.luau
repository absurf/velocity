local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = {}
if RunService:IsServer() then return module end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local TextFit = require(ReplicatedStorage.Shared.Modules.Core.TextFit)
local Squash = require(ReplicatedStorage.Shared.Modules.Core.Squash)

local Player = Players.LocalPlayer
local BAR = SpeedConfig.Hud.SpeedBar

local NUMBER_RATE = 20   -- the number's rewrites a second, at most
local FADE_STEP = 0.05

-- [ FEEL ]-- STARTING VALUES, NOT TUNED.
local HOP = { From = 1.35, Again = 0.35 }
local PACE = SpeedConfig.Pace or 1
local JUMP = {                              -- the bar's jelly on a change of speed
	Window = 0.2,                           -- s: a change this fast counts
	Rise = 30 * PACE, Drop = 60 * PACE,
	PerStud = 1 / (400 * PACE), Min = 0.04, Max = 0.14,   -- how hard: by the change's size
	Again = 0.3,                            -- s before it can be knocked again
}

-- [ REFS ]--
local Number: TextLabel
local Ticks: { ImageLabel } = {}
local Hops: { Squash.Squash } = {}   -- each tick's
local Jelly: Squash.Squash          -- the bar's (TickHolder)

-- [ STATE ]--
local Ready = false
local Wanted = 0
local Shown: string? = nil      -- the number on show
local Painted: { number } = {}  -- each tick's transparency as painted
local Full: { boolean } = {}     -- each tick fully lit, as painted
local HoppedAt: { number } = {}
local Recent: { { number } } = {}
local KnockedAt = -math.huge
local NumberAt = -math.huge   -- os.clock() the number was last rewritten
local PlainGradient = false

local function ColorAt(t: number): Color3
	local colors = SpeedConfig.Hud.SpeedColors
	local x = math.clamp(t, 0, 1) * (#colors - 1)
	local i = math.min(math.floor(x) + 1, #colors - 1)
	return colors[i]:Lerp(colors[i + 1], x - (i - 1))
end

local function Paint(speed: number)
	local now = os.clock()
	local text = tostring(math.floor(math.max(speed, 0) + 0.5))
	if text ~= Shown and now - NumberAt >= 1 / NUMBER_RATE then
		Shown, NumberAt = text, now
		Number.Text = text
	end
	local lit = math.clamp(speed / BAR.Max, 0, 1) * #Ticks
	for i, tick in Ticks do
		local on = math.clamp(lit - (i - 1), 0, 1)
		local transparency = math.round(BAR.Dim * (1 - on) / FADE_STEP) * FADE_STEP
		if transparency ~= Painted[i] then
			Painted[i] = transparency
			tick.ImageTransparency = transparency
		end
		local full = on >= 0.999
		if full and Full[i] == false and now - (HoppedAt[i] or -math.huge) >= HOP.Again then
			HoppedAt[i] = now
			Hops[i]:Pop(HOP.From)
		end
		Full[i] = full
	end

	table.insert(Recent, { now, speed })
	while #Recent > 1 and Recent[1][1] < now - JUMP.Window do table.remove(Recent, 1) end
	local low, high = speed, speed
	for _, sample in Recent do low, high = math.min(low, sample[2]), math.max(high, sample[2]) end
	if now - KnockedAt >= JUMP.Again then
		local rise, drop = speed - low, high - speed
		if rise >= JUMP.Rise then
			KnockedAt = now
			table.clear(Recent)
			Jelly:Knock(math.clamp(rise * JUMP.PerStud, JUMP.Min, JUMP.Max))
		elseif drop >= JUMP.Drop then
			KnockedAt = now
			table.clear(Recent)
			Jelly:Knock(-math.clamp(drop * JUMP.PerStud, JUMP.Min, JUMP.Max))
		end
	end
end

function module.SetSpeed(studsPerSecond: number)
	Wanted = studsPerSecond
	if Ready then Paint(studsPerSecond) end
end

function module.Init()
	task.spawn(function()
		local gameGui = Player:WaitForChild("PlayerGui"):WaitForChild("GameGUI")
		local background = gameGui:WaitForChild("Holder"):WaitForChild("SpeedHolder"):WaitForChild("Background")
		local info = background:WaitForChild("InfoHolder")
		local numberHolder = info:WaitForChild("NumberHolder")
		Number = numberHolder:WaitForChild("SpeedText")
		local labelHolder = info:WaitForChild("SpeedHolder")
		TextFit.BindSnugTextHolder(numberHolder, Number)
		TextFit.BindSnugTextHolder(labelHolder, labelHolder:WaitForChild("SpeedText"))
		local bar = background:WaitForChild("TickHolder")
		local template = bar:WaitForChild("Tick")
		for i = 1, BAR.Ticks do
			local tick = if i == 1 then template else template:Clone()
			tick.LayoutOrder = i
			tick.Parent = bar
			Ticks[i] = tick
			local gradient = tick:FindFirstChildOfClass("UIGradient")
			if gradient and i == 1 then
				local plain = true
				for _, key in gradient.Color.Keypoints do plain = plain and key.Value == Color3.new(1, 1, 1) end
				for _, key in gradient.Transparency.Keypoints do plain = plain and key.Value == 0 end
				PlainGradient = plain
			end
			if gradient and PlainGradient then gradient.Enabled = false end
			Hops[i] = Squash.new(tick, { Uniform = true })
		end
		Jelly = Squash.new(bar)
		Ready = true
		Paint(Wanted)
	end)
end

return module
