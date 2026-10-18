local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = {}
if RunService:IsServer() then return module end

local TweenService = game:GetService("TweenService")

local ImageList = require(ReplicatedStorage.ImageList)
local TextRoll = require(ReplicatedStorage.Shared.Modules.Core.TextRoll)

local Player = Players.LocalPlayer

local FEEL = TextRoll.Feel

-- [ REFS ]--
local Icon: ImageLabel
local Leaving: ImageLabel
local Tweens: { Tween } = {}

-- [ STATE ]--
local Ready = false
local Wanted = 1
local Shown: number? = nil

local function Picture(place: number)
	local best = nil
	for n = math.clamp(place, 1, 99), 1, -1 do
		best = ImageList["Place_" .. n .. ".png copy"]
		if best then return best end
	end
	return nil
end

local function Dress(icon: ImageLabel, place: number)
	local picture = Picture(place)
	if not picture then return end
	icon.Image = picture.Image
	icon.Size = picture.Size
	icon.Position = picture.Position
	icon.AnchorPoint = picture.AnchorPoint
end

local function Play(instance: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(instance, info, goal)
	table.insert(Tweens, tween)
	tween:Play()
end

local function Below(rest: UDim2, size: UDim2, by: number): UDim2
	return rest + UDim2.new(0, 0, size.Y.Scale * by, size.Y.Offset * by)
end

local function Paint()
	if Wanted == Shown then return end
	local before = Shown
	Shown = Wanted
	for _, tween in Tweens do tween:Cancel() end
	table.clear(Tweens)
	local distance = FEEL.Distance

	if before ~= nil then
		Leaving.Image, Leaving.Size, Leaving.AnchorPoint = Icon.Image, Icon.Size, Icon.AnchorPoint
		Leaving.Position, Leaving.ImageTransparency, Leaving.Visible = Icon.Position, Icon.ImageTransparency, true
		Play(Leaving, FEEL.Out, { Position = Below(Icon.Position, Icon.Size, distance) })
		Play(Leaving, FEEL.FadeOut, { ImageTransparency = 1 })
	end
	Dress(Icon, Wanted)
	if before == nil then return end

	local rest = Icon.Position
	Icon.Position, Icon.ImageTransparency = Below(rest, Icon.Size, -distance), 1
	Play(Icon, FEEL.In, { Position = rest })
	Play(Icon, FEEL.FadeIn, { ImageTransparency = 0 })
end

function module.SetPlace(place: number)
	Wanted = math.max(math.floor(place), 1)
	if Ready then Paint() end
end

function module.Init()
	task.spawn(function()
		local gameGui = Player:WaitForChild("PlayerGui"):WaitForChild("GameGUI")
		local background = gameGui:WaitForChild("Holder"):WaitForChild("PlaceHolder"):WaitForChild("Background")
		Icon = background:WaitForChild("IconHolder"):WaitForChild("Icon")
		Leaving = Icon:Clone()
		Leaving.Name = "Leaving"
		Leaving.Visible = false
		for _, child in Leaving:GetChildren() do
			if child:IsA("LuaSourceContainer") then child:Destroy() end   -- (its look -- aspect, stroke -- stays)
		end
		Leaving.Parent = Icon.Parent
		for _, layer in background:GetChildren() do
			if layer:IsA("ImageLabel") and layer.Name:match("^Place_%d") then layer.Visible = false end
		end
		Ready = true
		Paint()
	end)
end

return module
