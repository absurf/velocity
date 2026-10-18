local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = {}
if RunService:IsServer() then return module end

local Items = require(ReplicatedStorage.Items)
local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local TextFit = require(ReplicatedStorage.Shared.Modules.Core.TextFit)
local TextRoll = require(ReplicatedStorage.Shared.Modules.Core.TextRoll)
local Squash = require(ReplicatedStorage.Shared.Modules.Core.Squash)

local Player = Players.LocalPlayer

-- [ FEEL ]-- (WeaponHolder's)
local SHOW = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDE = TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
-- (Squash) STARTING VALUES, NOT TUNED.
local ARRIVE = Vector2.new(1.3, 0.7)
local KICK = -0.22
local REFILL = 1.4                     -- a use back: its tick starts this big

-- [ REFS ]--
local Holder: Frame, HolderScale: UIScale
local Icon: ImageLabel
local NameHolder: Frame, NameLabel: TextLabel, NameCap: UITextSizeConstraint
local NameRoll: TextRoll.TextRoll
local Key: TextLabel
local Charges: Frame, TickTemplate: Frame
local Ticks: { Frame } = {}
local Hops: { Squash.Squash } = {}
local TickFull: { boolean } = {}    -- each tick full, as painted
local IconSquash: Squash.Squash

-- [ STATE ]--
local Ready = false
local Want = nil
local Shown = false
local ShownName: string? = nil
local ScaleTween: Tween? = nil

local ModelView: ViewportFrame? = nil
local ModelSpin: RBXScriptConnection? = nil
local function ShowModel(model: Instance?)
	if ModelSpin then ModelSpin:Disconnect() ModelSpin = nil end
	if ModelView then ModelView:Destroy() ModelView = nil end
	if not (model and model:IsA("Model")) then return end
	local view = Instance.new("ViewportFrame")
	view.Name = "ModelView"
	view.BackgroundTransparency = 1
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.5, 0.5)
	view.Size = UDim2.fromScale(1.15, 1.15)
	view.Ambient = Color3.fromRGB(180, 180, 180)
	view.LightDirection = Vector3.new(-0.5, -1, -0.6)
	local copy = model:Clone()
	local cf, size = copy:GetBoundingBox()
	copy:PivotTo(copy:GetPivot() - cf.Position)
	copy.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local reach = size.Magnitude / 2 / math.tan(math.rad(15)) * 0.9
	camera.CFrame = CFrame.lookAt(Vector3.new(reach * 0.55, reach * 0.35, reach * 0.75).Unit * reach, Vector3.zero)
	camera.Parent = view
	view.CurrentCamera = camera
	view.Parent = Icon.Parent
	ModelView = view
	local base = copy:GetPivot()
	local t0 = os.clock()
	ModelSpin = RunService.RenderStepped:Connect(function()
		if not copy.Parent then return end
		copy:PivotTo(CFrame.Angles(0, (os.clock() - t0) * 0.8 % (math.pi * 2), 0) * base)
	end)
end

local function Pop(show: boolean)
	if ScaleTween then ScaleTween:Cancel() end
	if show then Holder.Visible = true end
	local tween = TweenService:Create(HolderScale, if show then SHOW else HIDE, { Scale = if show then 1 else 0 })
	ScaleTween = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and ScaleTween == tween and not show then Holder.Visible = false end
	end)
	tween:Play()
end

local function FitName()
	local room, used = NameHolder.AbsoluteSize.X, NameLabel.AbsoluteSize.X
	if room > 0 and used > room + 0.5 and NameLabel.TextSize > 1 then
		local size = math.max(math.floor(NameLabel.TextSize * room / used), 1)
		NameCap.MaxTextSize = size
		NameLabel.TextSize = size
	end
end

local function Fill(tick: Frame, share: number)
	local fill = tick:FindFirstChild("Fill") :: ImageLabel?
	if not fill then return end
	fill.Visible = share > 0
	local gradient = fill:FindFirstChildOfClass("UIGradient")
	if not gradient then return end
	if share >= 1 then
		gradient.Transparency = NumberSequence.new(0)
	elseif share > 0 then
		local edge = math.clamp(share, 0.001, 0.998)
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(edge, 0),
			NumberSequenceKeypoint.new(edge + 0.001, 1), NumberSequenceKeypoint.new(1, 1),
		})
	end
end

local function PaintTicks()
	local item = Want
	if not item then return end
	local max = math.max(math.floor(item.MaxUses or 1), 1)
	for i = #Ticks + 1, max do
		local tick = TickTemplate:Clone()
		tick.Name = "Tick" .. i
		tick.Parent = Charges
		Ticks[i] = tick
	end
	local uses = math.clamp(math.floor(item.Uses or max), 0, max)
	for i, tick in Ticks do
		tick.LayoutOrder = i
		tick.Visible = i <= max
		Fill(tick, if i <= uses then 1 elseif i == uses + 1 then math.clamp(item.Fill or 0, 0, 1) else 0)
		local full = i <= uses
		if not Hops[i] then Hops[i] = Squash.new(tick, { Uniform = true }) end
		if full and TickFull[i] == false and not item.Fresh then Hops[i]:Pop(REFILL) end   -- a use came back
		TickFull[i] = full
	end
	item.Fresh = nil
end

local function Paint()
	local item = Want
	if not item then
		if Shown then
			Shown = false
			Pop(false)
		end
		return
	end
	local picture = Items[item.Name]
	local name = string.upper(tostring(item.Display or SpeedConfig.Hud.ItemNames[item.Name] or item.Name))
	if not picture and name ~= ShownName then
		Icon.Visible = false
		ShowModel(item.Model)
	end
	if picture and name ~= ShownName then
		ShowModel(nil)
		IconSquash:Rest()
		Icon.Image = picture.Image
		Icon.Size = picture.Size
		Icon.Position = picture.Position
		Icon.AnchorPoint = picture.AnchorPoint
		Icon.Visible = true
		IconSquash:Capture()
		IconSquash:Pop(ARRIVE)
	end
	if name ~= ShownName then
		NameCap.MaxTextSize = 100
		if Shown then NameRoll:Swap(name) else NameRoll:Set(name) end
		ShownName = name
	end
	Key.Text = tostring(item.Key or SpeedConfig.Hud.ItemKey)
	PaintTicks()
	if not Shown then
		Shown = true
		Pop(true)
	end
end

function module.SetItem(item)
	Want = if type(item) == "table" then table.clone(item) else nil
	if Want then Want.Fresh = true end
	if Ready then Paint() end
end

function module.Used()
	if Ready and Shown then IconSquash:Knock(KICK) end
end

function module.SetCharge(uses: number, fill: number?)
	if not Want then return end
	Want.Uses, Want.Fill = uses, fill
	if Ready then PaintTicks() end
end

function module.Clear()
	Want = nil
	ShowModel(nil)
	if Ready then Paint() end
end

function module.Init()
	task.spawn(function()
		local gameGui = Player:WaitForChild("PlayerGui"):WaitForChild("GameGUI")
		Holder = gameGui:WaitForChild("Holder"):WaitForChild("ItemHolder")
		local background = Holder:WaitForChild("Background")
		Icon = background:WaitForChild("IconHolder"):WaitForChild("Icon")
		IconSquash = Squash.new(Icon)
		NameHolder = background:WaitForChild("NameHolder")
		NameLabel = NameHolder:WaitForChild("ItemName")
		Key = background:WaitForChild("KeybindHolder"):WaitForChild("KeybindText")
		Charges = background:WaitForChild("ChargeHolder")
		TickTemplate = Charges:WaitForChild("Tick")
		Ticks = { TickTemplate }
		NameCap = NameLabel:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
		NameCap.MaxTextSize = 100
		NameCap.Parent = NameLabel
		TextFit.FitLabel(NameLabel, true)
		TextFit.FitLabel(Key)
		NameLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(FitName)
		NameHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			NameCap.MaxTextSize = 100
			FitName()
		end)
		NameRoll = TextRoll.new(NameLabel)
		HolderScale = Holder:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		HolderScale.Parent = Holder

		Holder.Visible = false
		HolderScale.Scale = 0
		Ready = true
		Paint()
	end)
end

return module
