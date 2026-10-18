local TweenService = game:GetService("TweenService")

local TextRoll = {}
TextRoll.__index = TextRoll

TextRoll.Feel = {
	Distance = 0.5,   -- label heights each word travels
	In = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Out = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	FadeIn = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	FadeOut = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

type Feel = typeof(TextRoll.Feel)
export type TextRoll = typeof(setmetatable({} :: {
	Label: TextLabel, Word: TextLabel, Leaving: TextLabel, Feel: Feel,
	Text: number, Stroke: number?, InTweens: { Tween }, OutTweens: { Tween },
}, TextRoll))

local function Copy(label: TextLabel, name: string): TextLabel
	local copy = label:Clone()
	for _, child in copy:GetChildren() do
		if not (child:IsA("UIStroke") or child:IsA("UIGradient") or child:IsA("UITextSizeConstraint")) then child:Destroy() end
	end
	copy.Name = name
	copy.AnchorPoint = Vector2.new(0.5, 0.5)
	copy.Position = UDim2.fromScale(0.5, 0.5)
	copy.Size = UDim2.fromScale(1, 1)
	copy.Rotation = 0
	copy.BackgroundTransparency = 1
	copy.Visible = false
	copy.Parent = label
	return copy
end

local function At(by: number): UDim2
	return UDim2.fromScale(0.5, 0.5 + by)
end

local function Stop(tweens: { Tween })
	for _, tween in tweens do tween:Cancel() end
	table.clear(tweens)
end

local function Play(tweens: { Tween }, instance: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(instance, info, goal)
	table.insert(tweens, tween)
	tween:Play()
end

local function Fade(self: TextRoll, tweens: { Tween }?, word: TextLabel, fade: number, info: TweenInfo?)
	local text = self.Text + (1 - self.Text) * fade
	local stroke = word:FindFirstChildOfClass("UIStroke")
	local strokeTo = if self.Stroke then self.Stroke + (1 - self.Stroke) * fade else nil
	if tweens and info then
		Play(tweens, word, info, { TextTransparency = text })
		if stroke and strokeTo then Play(tweens, stroke, info, { Transparency = strokeTo }) end
	else
		word.TextTransparency = text
		if stroke and strokeTo then stroke.Transparency = strokeTo end
	end
end

function TextRoll.new(label: TextLabel, feel: Feel?): TextRoll
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local self = setmetatable({
		Label = label,
		Feel = feel or TextRoll.Feel,
		Text = label.TextTransparency,
		Stroke = if stroke then stroke.Transparency else nil,
		InTweens = {},
		OutTweens = {},
	}, TextRoll) :: TextRoll
	self.Word = Copy(label, "Word")
	self.Leaving = Copy(label, "Leaving")
	self.Word.Visible = true
	local function mirror()
		for _, copy in { self.Word, self.Leaving } do
			copy.TextScaled = label.TextScaled
			copy.TextSize = label.TextSize
			copy.TextWrapped = label.TextWrapped
		end
	end
	for _, property in { "TextScaled", "TextSize", "TextWrapped" } do
		label:GetPropertyChangedSignal(property):Connect(mirror)
	end
	-- The label is only the slot now.
	label.TextTransparency = 1
	if stroke then stroke.Enabled = false end
	return self
end

local function Leave(self: TextRoll, direction: number)
	local word, leaving = self.Word, self.Leaving
	Stop(self.InTweens)
	Stop(self.OutTweens)
	if not word.Visible then return end
	leaving.Text = word.Text
	leaving.TextColor3 = word.TextColor3
	local gradient, leavingGradient = word:FindFirstChildOfClass("UIGradient"), leaving:FindFirstChildOfClass("UIGradient")
	if gradient and leavingGradient then
		leavingGradient.Color = gradient.Color
		leavingGradient.Enabled = gradient.Enabled
	end
	leaving.Position = word.Position
	leaving.TextTransparency = word.TextTransparency
	local stroke, leavingStroke = word:FindFirstChildOfClass("UIStroke"), leaving:FindFirstChildOfClass("UIStroke")
	if stroke and leavingStroke then leavingStroke.Transparency = stroke.Transparency end
	leaving.Visible = true
	word.Visible = false
	Play(self.OutTweens, leaving, self.Feel.Out, { Position = At(-direction * self.Feel.Distance) })
	Fade(self, self.OutTweens, leaving, 1, self.Feel.FadeOut)
end

local function Arrive(self: TextRoll, text: string, direction: number, style: ((TextLabel) -> ())?)
	local word = self.Word
	Stop(self.InTweens)
	word.Text = text
	self.Label.Text = text
	if style then style(word) end
	word.Position = At(direction * self.Feel.Distance)
	Fade(self, nil, word, 1)
	word.Visible = true
	Play(self.InTweens, word, self.Feel.In, { Position = At(0) })
	Fade(self, self.InTweens, word, 0, self.Feel.FadeIn)
end

function TextRoll:Swap(text: string, direction: number?, style: ((TextLabel) -> ())?)
	Leave(self, direction or 1)
	Arrive(self, text, direction or 1, style)
end

function TextRoll:In(text: string, direction: number?, style: ((TextLabel) -> ())?)
	Arrive(self, text, direction or 1, style)
end

function TextRoll:Out(direction: number?)
	Leave(self, direction or 1)
	self.Label.Text = ""
end

function TextRoll:Set(text: string)
	self.Word.Text = text
	self.Label.Text = text
end

function TextRoll:Measure(text: string)
	self.Label.Text = text
end

function TextRoll:Clear()
	Stop(self.InTweens)
	Stop(self.OutTweens)
	self.Word.Visible = false
	self.Leaving.Visible = false
	self.Label.Text = ""
end

return TextRoll
