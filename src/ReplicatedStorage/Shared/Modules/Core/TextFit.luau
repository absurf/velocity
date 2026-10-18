local RunService  = game:GetService("RunService")
local TextService = game:GetService("TextService")

local TextFit = {}
if RunService:IsServer() then return TextFit end

local TEXT_SIZE_CAP = 100
local MEASURE_SIZE = 100

local lineRatio: { [string]: number } = {} -- [fontKey] = line height / TextSize
local lineWaiters: { [string]: { () -> () } } = {}

local function scaleOf(inst: Instance): number
	local s = 1
	local cur: Instance? = inst
	while cur and not cur:IsA("LayerCollector") do
		local uiScale = cur:FindFirstChildOfClass("UIScale")
		if uiScale then
			s *= uiScale.Scale
		end
		cur = cur.Parent
	end
	return s
end

local function unscaledHeight(inst: GuiObject): number?
	local s = scaleOf(inst)
	if s < 0.01 then
		return nil
	end
	local h = inst.AbsoluteSize.Y / s
	if h < 1 then
		return nil
	end
	return h
end

local function fontKey(font: Font): string
	return font.Family .. "|" .. tostring(font.Weight.Value) .. "|" .. font.Style.Name
end

local function getLineRatio(font: Font, onReady: () -> ()): number
	local key = fontKey(font)
	local ratio = lineRatio[key]
	if ratio then
		return ratio
	end
	if lineWaiters[key] then
		table.insert(lineWaiters[key], onReady)
		return 1
	end
	lineWaiters[key] = { onReady }
	task.spawn(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = "0123456789"
		params.Font = font
		params.Size = MEASURE_SIZE
		params.Width = 100000
		local ok, bounds = pcall(function()
			return TextService:GetTextBoundsAsync(params)
		end)
		lineRatio[key] = if ok and bounds and bounds.Y > 0 then bounds.Y / MEASURE_SIZE else 1
		local waiters = lineWaiters[key]
		lineWaiters[key] = nil
		for _, fn in waiters do
			fn()
		end
	end)
	return 1
end

local function textSizeFor(label: TextLabel, boxHeight: number, onLineReady: () -> ()): number
	local cap = TEXT_SIZE_CAP
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		cap = math.min(cap, constraint.MaxTextSize)
	end
	return math.clamp(math.floor(boxHeight / getLineRatio(label.FontFace, onLineReady)), 1, cap)
end

local function makeHugging(label: TextLabel, written: boolean?): () -> ()
	label.TextScaled = false
	label.TextWrapped = false
	label.AutomaticSize = if written then Enum.AutomaticSize.None else Enum.AutomaticSize.X

	label.Size = UDim2.new(0, 0, label.Size.Y.Scale, label.Size.Y.Offset)

	local function apply()
		local h = unscaledHeight(label)
		if not h then
			return
		end
		local size = textSizeFor(label, h, apply)
		if label.TextSize ~= size then
			label.TextSize = size
		end
	end

	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	label:GetPropertyChangedSignal("FontFace"):Connect(apply)
	if written then

		local function hug()
			local s = scaleOf(label)
			if s < 0.01 then
				return
			end
			local want = UDim2.new(0, math.ceil(label.TextBounds.X / s), label.Size.Y.Scale, label.Size.Y.Offset)
			if label.Size ~= want then
				label.Size = want
			end
		end

		label:GetPropertyChangedSignal("TextBounds"):Connect(hug)
		label:GetPropertyChangedSignal("Text"):Connect(hug)
		label:GetPropertyChangedSignal("TextSize"):Connect(hug)
		hug()
	end
	return apply
end

function TextFit.FitLabel(label: TextLabel?, written: boolean?)
	if not label then
		return
	end
	makeHugging(label, written)()
end

function TextFit.BindSnugTextHolder(holder: GuiObject?, label: TextLabel?, motionSafe: boolean?)
	if not (holder and label) then
		return
	end
	holder.Size = UDim2.new(0, 0, holder.Size.Y.Scale, holder.Size.Y.Offset)
	label.AnchorPoint = Vector2.new(0, label.AnchorPoint.Y)
	label.Position = UDim2.new(0, 0, label.Position.Y.Scale, label.Position.Y.Offset)

	local apply = makeHugging(label)
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)

	if motionSafe then
		holder.AutomaticSize = Enum.AutomaticSize.None
		local function hug()
			local s = scaleOf(label)
			if s < 0.01 then
				return -- scaled to nothing: keep the last width
			end
			local want = UDim2.new(0, math.ceil(label.AbsoluteSize.X / s), holder.Size.Y.Scale, holder.Size.Y.Offset)
			if holder.Size ~= want then
				holder.Size = want
			end
		end
		label:GetPropertyChangedSignal("AbsoluteSize"):Connect(hug)
		apply()
		hug()
	else
		holder.AutomaticSize = Enum.AutomaticSize.X
		apply()
	end
end

return TextFit
