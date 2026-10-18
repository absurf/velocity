local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = {}
if RunService:IsServer() then return module end

local TextFit = require(ReplicatedStorage.Shared.Modules.Core.TextFit)
local TextRoll = require(ReplicatedStorage.Shared.Modules.Core.TextRoll)

local Player = Players.LocalPlayer
local TIME_RATE = 30   -- the clock's rewrites a second, at most

-- [ REFS ]--
local Time: TextLabel
local LapRoll: TextRoll.TextRoll

-- [ STATE ]--
local Ready = false
local WantTime, WantLap, WantLaps = 0, 1, 1
local TimeShown: string? = nil
local LapShown: string? = nil
local LapNumber = 0
local TimeAt = -math.huge

local function Clock(seconds: number): string
	local hundredths = math.floor(math.max(seconds, 0) * 100)
	return ("%02d:%02d:%02d"):format(hundredths // 6000, (hundredths // 100) % 60, hundredths % 100)
end

local function PaintTime()
	local now = os.clock()
	if now - TimeAt < 1 / TIME_RATE then return end
	local text = Clock(WantTime)
	if text ~= TimeShown then
		TimeShown, TimeAt = text, now
		Time.Text = text
	end
end

local function PaintLap()
	local text = ("LAP %d/%d"):format(WantLap, WantLaps)
	if text == LapShown then return end
	if LapShown == nil or WantLap == LapNumber then
		LapRoll:Set(text)
	else
		LapRoll:Swap(text, if WantLap > LapNumber then 1 else -1)
	end
	LapShown, LapNumber = text, WantLap
end

function module.SetTime(seconds: number)
	WantTime = seconds
	if Ready then PaintTime() end
end

function module.SetLap(lap: number, laps: number)
	WantLap, WantLaps = math.max(math.floor(lap), 1), math.max(math.floor(laps), 1)
	if Ready then PaintLap() end
end

function module.Init()
	task.spawn(function()
		local gameGui = Player:WaitForChild("PlayerGui"):WaitForChild("GameGUI")
		local background = gameGui:WaitForChild("Holder"):WaitForChild("MatchInfoHolder"):WaitForChild("Background")
		Time = background:WaitForChild("TimeHolder"):WaitForChild("TimeText")
		local lap = background:WaitForChild("LapsHolder"):WaitForChild("LapText")
		TextFit.FitLabel(Time)
		TextFit.FitLabel(lap, true)
		LapRoll = TextRoll.new(lap)
		Ready = true
		PaintTime()
		PaintLap()
	end)
end

return module
