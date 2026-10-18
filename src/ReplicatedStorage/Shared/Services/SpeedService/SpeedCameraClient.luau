local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local M = require(ReplicatedStorage.Shared.Modules.Speed.MathUtil)
local C = Config.Camera

local CameraRig = {}
CameraRig.__index = CameraRig

function CameraRig.new(movement)
	local self = setmetatable({}, CameraRig)
	self.movement = movement
	self.camera = workspace.CurrentCamera
	self.S = Config.Studs
	self.smoothVel = Vector3.zero -- Speed units
	self.lastVel = Vector3.zero
	self.wobbleVel = Vector3.zero
	self.wobblePos = Vector3.zero
	self.fovVel, self.fovPos = 0, 0
	self.fovMult = 1
	self.airMult = 1
	self.currentOffset = C.OffsetSlow
	self.shakes = {}
	self.seed = math.random() * 1000
	self.mouseLocked = true
	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	self.params.RespectCanCollide = true
	movement.camera = self
	return self
end

function CameraRig:Shake(amount, duration)
	if amount <= 0 or duration <= 0 then return end
	table.insert(self.shakes, { amount = amount, duration = duration, left = duration, freq = 15 })
end

function CameraRig:AddWobble(forceUnits)
	self.wobbleVel += forceUnits
end

function CameraRig:AddFovImpulse(force)
	self.fovVel += force
end

function CameraRig:Snap()
	self.wobbleVel, self.wobblePos = Vector3.zero, Vector3.zero
	self.smoothVel = self.movement.vel
	self.lastVel = self.movement.vel
	self.fovVel, self.fovPos = 0, 0
end

function CameraRig:ToggleMouseLock()
	self.mouseLocked = not self.mouseLocked
end

function CameraRig:SetCursorFree(free: boolean)
	self.cursorFree = free
end

function CameraRig:PlayIntro(at: number)
	self.intro = { At = at }
end

function CameraRig:StopIntro()
	self.intro = nil
end

local function Smoother(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * u * (u * (u * 6 - 15) + 10)
end

function CameraRig:introShot(t: number, chase: CFrame, chaseFov: number): (CFrame, number)
	local R, RC = Config.Race, Config.Race.Camera
	local mv = self.movement
	local S = self.S
	local face = M.flat(mv.visualCF.LookVector)
	if face.Magnitude < 1e-3 then face = M.flat(mv:lookCFrame().LookVector) end
	face = face.Unit
	local right = Vector3.new(-face.Z, 0, face.X)
	local head = mv.renderPos * S + Vector3.yAxis * RC.Head

	local creep = 1 - RC.Push * Smoother(t / R.Hold)
	local front = head + (face * RC.Ahead + right * RC.Side) * creep + Vector3.yAxis * RC.Up
	if t <= R.Hold then
		return CFrame.lookAt(front, head), RC.Fov
	end

	local u = Smoother((t - R.Hold) / R.Sweep)
	local function Polar(p: Vector3): (number, number, number)
		local d = p - head
		return math.atan2(d.Z, d.X), Vector3.new(d.X, 0, d.Z).Magnitude, d.Y
	end
	local a0, r0, y0 = Polar(front)
	local a1, r1, y1 = Polar(chase.Position)
	local da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
	local mid = a0 + da / 2
	if Vector3.new(math.cos(mid), 0, math.sin(mid)):Dot(right * math.sign(RC.Side + 1e-6)) < 0 then
		da -= math.sign(da) * 2 * math.pi
	end
	local a, r, y = a0 + da * u, r0 + (r1 - r0) * u, y0 + (y1 - y0) * u
	local at = head + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
	local turn = CFrame.lookAt(at, head).Rotation:Lerp(chase.Rotation, Smoother((u - 0.45) / 0.55))
	return CFrame.new(at) * turn, RC.Fov + (chaseFov - RC.Fov) * u
end

function CameraRig:Update(dt)
	local mv = self.movement
	local cam = self.camera
	cam.CameraType = Enum.CameraType.Scriptable
	local locked = self.mouseLocked and not self.cursorFree
	UserInputService.MouseBehavior = locked and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not locked
	local S = self.S

	local velU = mv.vel
	local fast = mv.mode == "Fast"

	local k = C.SpeedFps / 60
	if mv.mostlyGrounded or mv.fastFalling or not fast then
		self.airMult = M.lerp(self.airMult, 1, M.expAlpha(2 * k, dt))
	else
		self.airMult = M.lerp(self.airMult, C.AirFovMult, M.expAlpha(0.25 * k, dt))
	end
	self.fovVel = M.lerp(self.fovVel, -self.fovPos * C.FovSpring, M.expAlpha(C.FovDrag * k, dt))
	self.fovPos += self.fovVel * dt
	local speed01 = M.easeInOut(M.invLerp(C.FovSpeedRange[1], C.FovSpeedRange[2], self.smoothVel.Magnitude))
	self.fovMult = M.lerp(self.fovMult, M.lerp(1, C.MaxFovMult, speed01) * self.airMult, M.expAlpha(2 * k, dt))
	cam.FieldOfView = math.clamp(C.BaseFov * self.fovMult + self.fovPos, 20, C.MaxFov)

	-- rotation from the look angles
	local rot = mv:lookCFrame()

	-- position
	self.smoothVel = M.lerpV(self.smoothVel, velU, M.expAlpha(C.SmoothVel, dt))
	local up = Vector3.yAxis
	local feet = mv.renderPos * S
	local targetPos = feet + self.smoothVel * C.Prediction * S
	local wantOffset = fast and C.OffsetFast or C.OffsetSlow
	self.currentOffset = self.currentOffset:Lerp(wantOffset, math.min(dt * C.OffsetLerp, 1))
	local o = self.currentOffset

	local offset = (rot.LookVector * o.Z + up * o.Y + rot.RightVector * o.X) / (self.fovMult ^ 2 + 1)

	local dv = velU - self.lastVel
	dv = Vector3.new(dv.X * 0.3, dv.Y, dv.Z * 0.3)
	if dv.Y < 0 and mv.input.dive then
		dv = Vector3.new(dv.X, dv.Y * 1.5, dv.Z)
	end
	self.wobbleVel += -dv * C.Wobble
	self.wobbleVel = M.lerpV(self.wobbleVel, -self.wobblePos * C.WobbleSpring, M.expAlpha(C.WobbleDrag, dt))
	self.wobblePos += self.wobbleVel * dt
	self.lastVel = velU

	local camPos = targetPos + offset * S + self.wobblePos * S

	local ignore = mv.params.FilterDescendantsInstances
	for _, inst in CollectionService:GetTagged("SpeedCameraIgnore") do table.insert(ignore, inst) end
	self.params.FilterDescendantsInstances = ignore
	local pivot = targetPos + rot.UpVector * C.PivotUp * S
	local toCam = camPos - pivot
	if toCam.Magnitude > 1e-3 then
		local start = pivot + toCam.Unit * 0.5 * S
		local dir = camPos - start
		if dir:Dot(toCam) > 0 then
			local hit = workspace:Spherecast(start, C.ObstructionRadius * S, dir, self.params)
			if hit then
				camPos = start + dir.Unit * hit.Distance
			end
		end
	end

	local sx, sy = 0, 0
	local t = os.clock()
	for i = #self.shakes, 1, -1 do
		local s = self.shakes[i]
		local frac = s.left / s.duration
		sx += math.noise(t * s.freq, self.seed, i * 1.3) * s.amount * frac
		sy += math.noise(self.seed, t * s.freq, i * 2.1) * s.amount * frac
		s.left -= dt
		if s.left < 0 then table.remove(self.shakes, i) end
	end

	if mv.field then
		local h = mv.field:Sample(camPos.X / S, camPos.Z / S)
		if h and camPos.Y < (h + 0.6) * S then
			camPos = Vector3.new(camPos.X, (h + 0.6) * S, camPos.Z)
		end
	end

	local final = CFrame.new(camPos) * rot * CFrame.fromEulerAnglesYXZ(math.rad(-sx), math.rad(sy), 0)

	local intro = self.intro
	if intro then
		local t = workspace:GetServerTimeNow() - intro.At
		if t >= Config.Race.Hold + Config.Race.Sweep then
			self.intro = nil
		else
			local fov
			final, fov = self:introShot(t, final, cam.FieldOfView)
			cam.FieldOfView = fov
		end
	end
	cam.CFrame = final
end

return CameraRig
