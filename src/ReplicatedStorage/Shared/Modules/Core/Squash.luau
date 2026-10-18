local RunService = game:GetService("RunService")

local Squash = {}
Squash.__index = Squash

local IMPACT = { Damping = 11, Stiffness = 260 }
local JELLY = { X = 0.5, Y = 1 }
local POP_TIME = 1
local SUBSTEP = 1 / 240
local SETTLED = 1e-3

export type Squash = typeof(setmetatable({} :: {
	Gui: GuiObject, Pivot: Vector2, Uniform: boolean, Scale: UIScale?,
	RestSize: UDim2, RestPosition: UDim2, PopFrom: Vector2?, PopStart: number, Q: number, V: number,
}, Squash))

local busy: { [Squash]: boolean } = {}
local connection: RBXScriptConnection? = nil

local function Released(t: number): number
	local decay = IMPACT.Damping / 2
	local freq = math.sqrt(IMPACT.Stiffness - decay * decay)
	return math.exp(-decay * t) * (math.cos(freq * t) + decay / freq * math.sin(freq * t))
end

local function Scaled(d: UDim, k: number): UDim
	return UDim.new(d.Scale * k, math.round(d.Offset * k))
end

local function StepAll(dt: number)
	local now = os.clock()
	dt = math.min(dt, 0.1)
	for s in busy do
		if not s:_Step(now, dt) then busy[s] = nil end
	end
	if next(busy) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function Wake(s: Squash)
	busy[s] = true
	if not connection then connection = RunService.RenderStepped:Connect(StepAll) end
end

function Squash.new(gui: GuiObject, options: { Pivot: Vector2?, Uniform: boolean? }?): Squash
	local self = setmetatable({
		Gui = gui,
		Pivot = options and options.Pivot or Vector2.new(0.5, 0.5),
		Uniform = options ~= nil and options.Uniform == true,
		PopStart = 0, Q = 0, V = 0,
	}, Squash) :: any
	if self.Uniform then
		local scale = gui:FindFirstChild("SquashScale") or Instance.new("UIScale")
		scale.Name = "SquashScale"
		scale.Parent = gui
		self.Scale = scale
	end
	self:Capture()
	return self
end

function Squash:Capture()
	self.RestSize, self.RestPosition = self.Gui.Size, self.Gui.Position
end

function Squash:_Apply(w: number, h: number)
	if self.Uniform then
		(self.Scale :: UIScale).Scale = math.max(w, 0.01)
		return
	end
	local gui, rest, at = self.Gui, self.RestSize, self.RestPosition
	local size = UDim2.new(Scaled(rest.X, w), Scaled(rest.Y, h))
	if gui.Size ~= size then gui.Size = size end
	local shift = self.Pivot - gui.AnchorPoint
	if shift.Magnitude < 1e-6 then return end
	local position = UDim2.new(
		at.X.Scale + shift.X * (rest.X.Scale - size.X.Scale), at.X.Offset + math.round(shift.X * (rest.X.Offset - size.X.Offset)),
		at.Y.Scale + shift.Y * (rest.Y.Scale - size.Y.Scale), at.Y.Offset + math.round(shift.Y * (rest.Y.Offset - size.Y.Offset)))
	if gui.Position ~= position then gui.Position = position end
end

function Squash:_Step(now: number, dt: number): boolean
	local w, h, moving = 1, 1, false
	local from = self.PopFrom
	if from then
		local t = now - self.PopStart
		if t >= POP_TIME then
			self.PopFrom = nil
		else
			local r = Released(t)
			w, h = 1 + (from.X - 1) * r, 1 + (from.Y - 1) * r
			moving = true
		end
	end
	if self.Q ~= 0 or self.V ~= 0 then
		local left = dt
		while left > 0 do
			local step = math.min(left, SUBSTEP)
			left -= step
			self.V += (-IMPACT.Stiffness * self.Q - IMPACT.Damping * self.V) * step
			self.Q += self.V * step
		end
		if math.abs(self.Q) < SETTLED and math.abs(self.V) < SETTLED * 10 then
			self.Q, self.V = 0, 0
		else
			moving = true
		end
		if self.Uniform then
			w, h = w * (1 + self.Q), h * (1 + self.Q)
		else
			w, h = w * (1 + self.Q * JELLY.X), h * (1 - self.Q * JELLY.Y)
		end
	end
	self:_Apply(w, h)
	return moving
end

function Squash:Pop(from: Vector2 | number)
	local shape = if typeof(from) == "number" then Vector2.new(from, from) else from :: Vector2
	self.PopFrom, self.PopStart = shape, os.clock()
	self:_Apply(shape.X, shape.Y)
	Wake(self)
end

function Squash:Knock(amount: number)
	self.Q += amount
	Wake(self)
end

function Squash:Rest()
	self.PopFrom, self.Q, self.V = nil, 0, 0
	busy[self] = nil
	self:_Apply(1, 1)
end

return Squash
