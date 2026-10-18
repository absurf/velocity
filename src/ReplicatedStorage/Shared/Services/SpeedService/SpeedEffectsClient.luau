local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local M = require(ReplicatedStorage.Shared.Modules.Speed.MathUtil)
local FX = Config.Fx

local UP = Vector3.yAxis

local Effects = {}
Effects.__index = Effects

local function invisiblePart(name)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	return p
end

local NORMALS = {
	[Enum.NormalId.Top] = Vector3.yAxis, [Enum.NormalId.Bottom] = -Vector3.yAxis,
	[Enum.NormalId.Right] = Vector3.xAxis, [Enum.NormalId.Left] = -Vector3.xAxis,
	[Enum.NormalId.Back] = Vector3.zAxis, [Enum.NormalId.Front] = -Vector3.zAxis,
}

local function MakeLines(parent)
	local node = ReplicatedStorage:FindFirstChild("Assets")
	node = node and node:FindFirstChild("Speed")
	node = node and node:FindFirstChild("VFX")
	local template = node and node:FindFirstChild("ScreenLines")
	if not template then
		warn("SpeedEffectsClient: no Assets.Speed.VFX.ScreenLines (SpeedTools.VFXBuilder): no speed lines")
		return nil
	end
	local copy = template:Clone()

	local middle = if copy:IsA("Model") then copy:GetPivot().Position elseif copy:IsA("BasePart") then copy.Position else Vector3.zero
	local lines = { Folder = copy, Strips = {}, On = false, Color = nil }
	local back = if FX.ScreenLines.Away then -Vector3.zAxis else Vector3.zAxis
	for _, part in { copy, unpack(copy:GetDescendants()) } do
		if not part:IsA("BasePart") then continue end
		local emitters, dir = {}, nil
		for _, e in part:GetChildren() do
			if e:IsA("ParticleEmitter") then
				table.insert(emitters, { Emitter = e, Rate = e.Rate, Color = e.Color, Now = -1 })
				dir = dir or NORMALS[e.EmissionDirection] * (if e.ShapeInOut == Enum.ParticleEmitterShapeInOut.Inward then -1 else 1)
				e.Enabled = false
				e.LockedToPart = true
			end
		end
		if #emitters == 0 then continue end
		local size = part.Size
		local axis = if size.X >= size.Y and size.X >= size.Z then Vector3.xAxis elseif size.Y >= size.Z then Vector3.yAxis else Vector3.zAxis
		if math.abs(axis:Dot(dir)) > 0.9 then continue end
		local along = part.CFrame:VectorToWorldSpace(axis)
		local at = part.Position - middle
		local across = math.abs(along.X) >= math.abs(along.Y)
		local edge = if across then Vector3.xAxis else Vector3.yAxis
		local own = CFrame.fromMatrix(Vector3.zero, axis, (dir - axis * dir:Dot(axis)).Unit)
		local want = CFrame.fromMatrix(Vector3.zero, edge, back)
		table.insert(lines.Strips, {
			Part = part, Emitters = emitters, Axis = axis, Size = size, Length = math.max(size.X, size.Y, size.Z), Now = -1,
			Across = across, Side = if across then (if at.Y >= 0 then 1 else -1) else (if at.X >= 0 then 1 else -1),
			Turn = want * own:Inverse(),
		})
	end
	copy.Name = "ScreenLines"
	copy.Parent = parent
	return lines
end

function Effects.new(movement, playerGui)
	local self = setmetatable({}, Effects)
	self.mv = movement
	self.S = Config.Studs
	self.rng = Random.new(7)

	self.airM = 1   -- the speed lines' air multiplier (eased)
	self.linesOn = true

	local cam = workspace.CurrentCamera
	self.look = Instance.new("ColorCorrectionEffect")
	self.look.Name = "__SpeedLook"
	self.look.Saturation = FX.Saturation
	self.look.Parent = cam
	self.bloom = Instance.new("BloomEffect")
	self.bloom.Name = "__SpeedBloom"
	self.bloom.Intensity, self.bloom.Size, self.bloom.Threshold = FX.Bloom, 28, 1.1
	self.bloom.Parent = cam
	self.dof = Instance.new("DepthOfFieldEffect")
	self.dof.Name = "__SpeedSpeedBlur"
	self.dof.FarIntensity, self.dof.NearIntensity = 0, 0
	self.dof.FocusDistance, self.dof.InFocusRadius = 20, 10
	self.dof.Enabled = FX.SpeedBlur
	self.dof.Parent = cam

	-- world VFX around the ball
	local model = Instance.new("Model")
	model.Name = "__SpeedFx"

	self.streak = invisiblePart("DiveStreak")
	self.streak.Parent = model
	self.wisps = {}
	local r = Config.Ball.Radius * self.S
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + self.rng:NextNumber(-0.2, 0.2)
		local rr = r * self.rng:NextNumber(1.05, 1.35)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(math.cos(a) * rr * 0.75, math.sin(a) * rr * 0.75, -r * 0.8)
		a0.Parent = self.streak
		local a1 = Instance.new("Attachment")
		a1.Parent = self.streak
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = a0, a1
		b.FaceCamera = true
		b.Segments = 1
		b.Width0, b.Width1 = 0.3, 0.8
		b.LightEmission = 0.5
		b.Color = ColorSequence.new(Color3.new(1, 1, 1))
		b.Transparency = NumberSequence.new(1)
		b.Parent = self.streak
		table.insert(self.wisps, {
			beam = b, a1 = a1, x = math.cos(a) * rr, y = math.sin(a) * rr,
			len = r * self.rng:NextNumber(3, 5), phase = self.rng:NextNumber(), rate = self.rng:NextNumber(0.9, 1.4),
		})
	end
	self.spin = 0
	self.anchor = invisiblePart("FxAnchor")
	self.anchor.Parent = model
	local att = Instance.new("Attachment")
	att.Parent = self.anchor
	self.att = att
	local function emitter(props)
		local e = Instance.new("ParticleEmitter")
		e.Rate = 0
		e.LockedToPart = false
		for k, v in pairs(props) do e[k] = v end
		e.Parent = att
		return e
	end
	self.burst = emitter({
		Lifetime = NumberRange.new(0.35, 0.8), Speed = NumberRange.new(25, 55), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(Color3.fromRGB(90, 235, 255)), LightEmission = 1, Drag = 3,
	})
	self.boost = emitter({
		Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 170, 60)), LightEmission = 1,
	})
	self.lines = MakeLines(model)
	model.Parent = workspace
	self.model = model
	movement:AddIgnore(model)
	self.fastfallFor = 0
	self.landConn = movement.Landed.Event:Connect(function(info)
		if info.kind == "Perfect" then
			self.burst:Emit(45)
		end
	end)
	return self
end

function Effects:SetSpeedPreset(color, amount)
	self.presetColor, self.presetAmount, self.presetAge = color, amount or 1, 0
end

function Effects:SetLines(on)
	self.linesOn = on
end

function Effects:_Lines(cam, strength, dt)
	local lines = self.lines
	if not lines then return end
	local cfg = FX.ScreenLines
	local amount = M.clamp01((strength - cfg.From) / (1 - cfg.From))
	if not (FX.SpeedLines and self.linesOn and amount > 0) then
		if lines.On then
			lines.On = false
			for _, s in lines.Strips do
				for _, e in s.Emitters do e.Emitter.Enabled = false end
			end
		end
		self.aim = nil
		return
	end
	lines.On = true

	local camCF = cam.CFrame
	local look = camCF.LookVector
	local target = look
	local vel = self.mv.vel
	if vel.Magnitude > 1e-3 and vel.Unit:Dot(look) > 0 then
		target = look:Lerp(vel.Unit, cfg.Follow).Unit
	end
	self.aim = if self.aim then self.aim:Lerp(target, M.expAlpha(10, dt)).Unit else target
	local frame = CFrame.lookAt(camCF.Position, camCF.Position + self.aim, camCF.UpVector)
	local d = cfg.Distance
	local tan = math.tan(math.rad(cam.FieldOfView) / 2)
	local vp = cam.ViewportSize
	local hy = cfg.Fill[2] * d * tan
	local hx = cfg.Fill[1] * d * tan * vp.X / math.max(vp.Y, 1)
	local color = if self.presetColor and self.presetAge < 0.25 then ColorSequence.new(self.presetColor) else nil
	for _, s in lines.Strips do
		local length = 2 * (if s.Across then hx else hy)
		local x = if s.Across then 0 else s.Side * hx
		local y = if s.Across then s.Side * hy else 0
		s.Part.CFrame = frame * CFrame.new(x, y, -d) * s.Turn
		if math.abs(length - s.Now) > 0.05 then
			s.Now = length
			s.Part.Size = s.Size * (Vector3.one - s.Axis) + s.Axis * length
		end

		local share = length / s.Length
		for _, e in s.Emitters do
			local rate = e.Rate * share * amount * cfg.Rate
			if math.abs(rate - e.Now) > 0.5 then
				e.Now = rate
				e.Emitter.Rate = rate
			end
			if not e.Emitter.Enabled then e.Emitter.Enabled = true end
			local want = color or e.Color
			if e.Tint ~= want then
				e.Tint = want
				e.Emitter.Color = want
			end
		end
	end
end

function Effects:Update(dt)
	local mv = self.mv
	local cam = workspace.CurrentCamera
	local S = self.S
	local speed = mv.vel.Magnitude
	local paceRatio = speed / Config.Pace
	local fast = mv.mode == "Fast"

	local k = Config.Camera.SpeedFps / 60
	if mv.mostlyGrounded or mv.fastFalling then
		self.airM = M.lerp(self.airM, 1, M.expAlpha(2 * k, dt))
	else
		self.airM = M.lerp(self.airM, 0.7, M.expAlpha(0.5 * k, dt))
	end
	self.presetAge = (self.presetAge or 10) + dt
	self:_Lines(cam, M.clamp01(paceRatio / 100 * self.airM), dt)

	if self.dof.Enabled then
		local camDist = (cam.CFrame.Position - mv.renderPos * S).Magnitude
		self.dof.FocusDistance = camDist
		self.dof.InFocusRadius = math.max(camDist * FX.BlurFocusBand, 2)
		self.dof.NearIntensity = FX.BlurMax * M.invLerp(FX.BlurSpeedRange[1], FX.BlurSpeedRange[2], speed) * (fast and 1 or 0)
	end

	if mv.fastFalling and fast then
		self.fastfallFor = M.moveTowards(self.fastfallFor, 3.25, dt)
	else
		self.fastfallFor = M.moveTowards(self.fastfallFor, 0, dt * 3)
	end
	local center = mv.renderPos * S + UP * (mv.bodyCenter or Config.Ball.Radius) * S

	local opacity = M.clamp01(self.fastfallFor - 0.25)
	local build = M.clamp01((self.fastfallFor - 0.25) / 3)
	if FX.DiveStreak and opacity > 0 and speed > 1 then
		local dir = mv.vel.Unit
		self.spin += dt * 0.5 * math.pi
		self.streak.CFrame = CFrame.lookAt(center, center + dir) * CFrame.Angles(0, 0, self.spin)
		local peak = 1 - 0.65 * opacity
		for _, w in ipairs(self.wisps) do
			w.phase = (w.phase + dt * w.rate * 1.6) % 1
			local p = 0.12 + 0.6 * w.phase
			w.a1.Position = Vector3.new(w.x, w.y, w.len * (0.6 + 0.4 * build))
			w.beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(p - 0.1, 1),
				NumberSequenceKeypoint.new(p, peak),
				NumberSequenceKeypoint.new(math.min(p + 0.25, 0.999), 1),
				NumberSequenceKeypoint.new(1, 1),
			})
			w.beam.Enabled = true
		end
	elseif self.wisps[1].beam.Enabled then
		for _, w in ipairs(self.wisps) do w.beam.Enabled = false end
	end

	local contact = mv.renderPos * S
	local back = speed > 1 and -mv.vel.Unit or -mv.visualCF.LookVector
	self.anchor.CFrame = CFrame.lookAt(contact, contact - back) -- Back face points along `back`
	self.boost.Rate = mv.speedBoost > 0 and 40 or 0
end

function Effects:Destroy()
	if self.landConn then self.landConn:Disconnect() end
	self.model:Destroy()
	self.look:Destroy()
	self.bloom:Destroy()
	self.dof:Destroy()
end

return Effects
