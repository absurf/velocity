local RunService = game:GetService("RunService")

local UISpring = {}
UISpring.__index = UISpring

export type UISpring = typeof(setmetatable({} :: {
	Value: number,
	Velocity: number,
	Target: number,
	Frequency: number,
	Damping: number,
	OnStep: ((number) -> ())?,
}, UISpring))

local SUBSTEP = 1 / 240
local MAX_DT = 0.1 -- a hitch should not fling anything
local REST = 1e-3

local awake: { [UISpring]: boolean } = {}
local connection: RBXScriptConnection? = nil

local function stepAll(dt: number)
	for spring in awake do
		spring:_Step(dt)
	end
	if next(awake) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function wake(spring: UISpring)
	awake[spring] = true
	if not connection then
		connection = RunService.RenderStepped:Connect(stepAll)
	end
end

function UISpring.new(initial: number, frequency: number, dampingRatio: number, onStep: ((number) -> ())?): UISpring
	local self = setmetatable({
		Value = initial,
		Velocity = 0,
		Target = initial,
		Frequency = frequency,
		Damping = dampingRatio,
		OnStep = onStep,
	}, UISpring)
	if onStep then
		onStep(initial)
	end
	return self
end

function UISpring._Step(self: UISpring, dt: number)
	local omega = 2 * math.pi * self.Frequency
	local remaining = math.min(dt, MAX_DT)
	while remaining > 0 do
		local h = math.min(remaining, SUBSTEP)
		remaining -= h
		local accel = omega * omega * (self.Target - self.Value) - 2 * self.Damping * omega * self.Velocity
		self.Velocity += accel * h
		self.Value += self.Velocity * h
	end

	if math.abs(self.Target - self.Value) < REST and math.abs(self.Velocity) < REST then
		self.Value = self.Target
		self.Velocity = 0
		awake[self] = nil
	end

	if self.OnStep then
		self.OnStep(self.Value)
	end
end

function UISpring.SetTarget(self: UISpring, target: number)
	self.Target = target
	wake(self)
end

function UISpring.SetValue(self: UISpring, value: number)
	self.Value = value
	wake(self)
end

function UISpring.Kick(self: UISpring, velocity: number)
	self.Velocity += velocity
	wake(self)
end

function UISpring.Snap(self: UISpring, value: number)
	self.Value = value
	self.Target = value
	self.Velocity = 0
	awake[self] = nil
	if self.OnStep then
		self.OnStep(value)
	end
end

function UISpring.Destroy(self: UISpring)
	awake[self] = nil
	self.OnStep = nil
end

return UISpring
