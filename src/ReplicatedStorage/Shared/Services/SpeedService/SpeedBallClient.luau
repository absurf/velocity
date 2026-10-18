local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local M = require(ReplicatedStorage.Shared.Modules.Speed.MathUtil)

local UP = Vector3.yAxis

local BallView = {}
BallView.__index = BallView

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

function BallView.new(movement, parent)
	local self = setmetatable({}, BallView)
	self.movement = movement
	self.parent = parent
	self.S = Config.Studs
	self.radius = Config.Ball.Radius * self.S
	local d = self.radius * 2
	local model = Instance.new("Model")
	model.Name = "__SpeedBall"
	self.ball = makePart({ Name = "Ball", Shape = Enum.PartType.Ball, Size = Vector3.one * d, Color = Config.Ball.Color, Parent = model })
	self.bandA = makePart({ Name = "BandA", Shape = Enum.PartType.Cylinder, Size = Vector3.new(d * 0.16, d * 1.02, d * 1.02), Color = Config.Ball.BandColor, Parent = model })
	self.bandB = makePart({ Name = "BandB", Shape = Enum.PartType.Cylinder, Size = Vector3.new(d * 0.16, d * 1.02, d * 1.02), Color = Color3.fromRGB(30, 30, 40), Parent = model })
	self.carrier = makePart({ Name = "TrailCarrier", Size = Vector3.one * 0.2, Transparency = 1, Parent = model })
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, self.radius * 0.22, 0); a0.Parent = self.carrier
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -self.radius * 0.22, 0); a1.Parent = self.carrier
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.18
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.4
	trail.Color = ColorSequence.new(Config.Ball.Color, Color3.fromRGB(255, 220, 120))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = self.carrier
	self.trail = trail
	model.Parent = parent or workspace
	self.model = model
	movement:AddIgnore(model)
	self.rot = CFrame.identity
	self.spin = Vector3.zero
	self.up = UP
	return self
end

function BallView:Update(dt)
	local mv = self.movement
	local S = self.S
	local feet = mv.renderPos * S
	local vel = mv.vel * S
	local grounded = mv.mostlyGrounded

	local targetUp = grounded and mv.groundNormal or UP
	self.up = M.unit(self.up:Lerp(targetUp, M.expAlpha(14, dt)))
	local center = feet + self.up * self.radius
	if grounded then
		self.spin = self.up:Cross(vel) / self.radius
	else
		self.spin *= math.exp(-0.3 * dt)
	end
	local w = self.spin
	if w.Magnitude > 1e-4 then
		self.rot = CFrame.fromAxisAngle(w.Unit, w.Magnitude * dt) * self.rot
	end
	local cf = CFrame.new(center) * self.rot
	self.ball.CFrame = cf
	self.bandA.CFrame = cf
	self.bandB.CFrame = cf * CFrame.Angles(0, math.rad(90), 0)
	self.carrier.CFrame = CFrame.new(center)
	self.trail.Enabled = Config.Ball.Trail and vel.Magnitude > 60
end

function BallView:SetVisible(on)
	self.visible = on
	self.model.Parent = on and (self.parent or workspace) or nil
	self.movement:refreshFilter()
end

function BallView:Destroy()
	self.model:Destroy()
end

return BallView
