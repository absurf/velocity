local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Parent.Configs.SpeedConfig)
local M = require(script.Parent.MathUtil)
local Heightfield = require(script.Parent.Heightfield)
local Perf = require(script.Parent.SpeedPerf)
local Traps = require(script.Parent.Traps)

local UP = Vector3.yAxis
local DOWN = -Vector3.yAxis
local ZERO = Vector3.zero
local FINISH_DAMP = 0.6

local Movement = {}
Movement.__index = Movement

local SolidList: { Instance }? = nil
local function Solids(): { Instance }
	if not SolidList then
		SolidList = CollectionService:GetTagged(Config.SolidTag)
		CollectionService:GetInstanceAddedSignal(Config.SolidTag):Connect(function() SolidList = CollectionService:GetTagged(Config.SolidTag) end)
		CollectionService:GetInstanceRemovedSignal(Config.SolidTag):Connect(function() SolidList = CollectionService:GetTagged(Config.SolidTag) end)
	end
	return SolidList :: { Instance }
end

local fieldCache = {}
local fieldBuilding = {} -- key -> true while it's being built

function Movement.new()
	local self = setmetatable({}, Movement)
	self.S = Config.Studs
	self.dt = 1 / Config.TickRate
	self.accumulator = 0

	self.Landed = Instance.new("BindableEvent")
	self.Hit = Instance.new("BindableEvent")
	self.ModeChanged = Instance.new("BindableEvent")
	self.CloseCall = Instance.new("BindableEvent") -- (side "Left" / "Right")
	self.RunStarted = Instance.new("BindableEvent")
	self.PropBroken = Instance.new("BindableEvent")
	self.TrapTouched = Instance.new("BindableEvent")
	self.GrappleEvent = Instance.new("BindableEvent")
	self.grapple, self.yank = nil, nil
	self.phased = {}
	self.trapReady = {}
	self.camera = nil

	self.collisionTime, self.hitStopHold, self.hitStopRate = 1, 0, 5
	self.closeLeft, self.closeRight = 10, 10

	self.mode = "Slow"
	self.pos, self.prevPos, self.lastPos, self.renderPos = ZERO, ZERO, ZERO, ZERO
	self.vel, self.tickVel, self.pending, self.accel = ZERO, ZERO, ZERO, ZERO
	self.gravityDir, self.groundNormal = DOWN, UP
	self.isGrounded, self.mostlyGrounded, self.mostlyGroundedFor = false, false, 0
	self.sinceGrounded, self.lastAirTime = 10, 0
	self.sinceSwitch, self.sinceRestart, self.sinceTerrain, self.sinceJumped = 10, 10, 10, 10
	self.dontLandFor, self.knockedDownFor, self.invulnerability, self.perfectLandingsFor = 0, 0, 0, 0
	self.isBreaking, self.fastFalling, self.forceFalling = false, false, false
	self.turnAmount, self.distanceToGround = 0, 0
	self.speedBoost, self.speedLossResistance = 0, 0
	self.abilityTurnRate, self.itemTurnRate = 1, 1
	self.energy, self.charge, self.sinceChargeShake = 0, 0, 0.1
	self.frozen = false
	self.speedMults, self.speedMult = {}, 1
	self.autoSteer, self.waypointIndex = false, 1
	self.lastLanding, self.landingLog = nil, {}
	self.groundContact = false
	self:SetBody(Config.Body or "Ball")

	self.yaw, self.pitchDown, self.autoLook = 0, Config.BasePitch, 0
	self.visualCF = CFrame.lookAt(ZERO, Vector3.new(0, 0, -1))
	self.input = { x = 0, y = 0, dive = false, fastRunHeld = false, fastRunPressed = false, lookX = 0, lookY = 0, magnitude = 0 }
	self.fastRunWasHeld = false

	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	self.params.RespectCanCollide = true
	self.ignore = {}
	self:refreshFilter()
	return self
end

function Movement:AddIgnore(inst)
	table.insert(self.ignore, inst)
	self:refreshFilter()
end

function Movement:refreshFilter()
	local list = {}
	for _, inst in ipairs(self.ignore) do
		if inst.Parent then table.insert(list, inst) end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(list, player.Character) end
	end
	if self.field then
		table.insert(list, workspace.Terrain)
	end
	for prop in self.phased do
		if prop.Parent then table.insert(list, prop) end -- props you're phasing through (breakProp)
	end
	self.params.FilterDescendantsInstances = list
	self.filterAge = 0
end

function Movement.FindCourse(name)
	local world = workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild(Config.Courses or "Courses")
	return folder and folder:FindFirstChild(name)
end

function Movement.GetField(course)
	local fieldName = course and course:GetAttribute("Heightfield")
	if not fieldName then return nil end
	local module = script.Parent.Courses:FindFirstChild(fieldName)
	if not module then return nil end
	local def = require(module)
	local key = fieldName
	if def.ForCourse then
		key = fieldName .. ":" .. course.Name
		def = def.ForCourse(course)
	end
	while fieldBuilding[key] do task.wait() end
	if fieldCache[key] then return fieldCache[key] end
	local field = Heightfield.new({ origin = def.Origin, size = def.Size, spacing = def.Spacing, height = def.height })
	fieldBuilding[key] = field   -- (its progress: FieldProgress)
	field:Build(160)
	if key ~= fieldName then
		for other in fieldCache do
			if other:sub(1, #fieldName + 1) == fieldName .. ":" then fieldCache[other] = nil end
		end
	end
	fieldCache[key] = field
	fieldBuilding[key] = nil
	return field
end

function Movement.FieldProgress(course): number
	local fieldName = course and course:GetAttribute("Heightfield")
	if not fieldName then return 1 end
	local module = script.Parent.Courses:FindFirstChild(fieldName)
	local def = module and require(module)
	local key = if def and def.ForCourse then fieldName .. ":" .. course.Name else fieldName
	if fieldCache[key] then return 1 end
	local building = fieldBuilding[key]
	return if type(building) == "table" then building.progress or 0 else 0
end

function Movement:SetCourse(name)
	local course = Movement.FindCourse(name)
	local field = Movement.GetField(course)
	self.courseName, self.course, self.field = name, course, field
	self.openEdges = course ~= nil and course:GetAttribute("OpenEdges") == true

	self.genData, self.safePos = nil, nil
	local module = course and course:GetAttribute("Heightfield") == "Generated" and script.Parent.Courses:FindFirstChild("Generated")
	if module then self.genData = require(module).ForCourse(course) end
	self:refreshFilter()
end

function Movement:cast(fromU, toU)
	Perf.Count("#rays")
	local best
	if self.field then
		best = self.field:Raycast(fromU, toU)
	end
	local S = self.S
	local dir = (toU - fromU) * S
	if dir.Magnitude > 1e-4 then
		local r = workspace:Raycast(fromU * S, dir, self.params)
		if r then
			local dist = r.Distance / S
			if not best or dist < best.distance then
				best = { position = r.Position / S, normal = r.Normal, instance = r.Instance, distance = dist }
			end
		end
	end
	return best
end

function Movement:liftOut(p)
	local hit = self:cast(p + UP * Config.SnapRayUp, p)
	if hit and hit.position.Y > p.Y and M.angle(UP, hit.normal) < Config.WallAngle
		and not (hit.instance and self:tagged(hit.instance, "SpeedProp")) then
		return hit.position
	end
	return p
end

function Movement:fieldBounds()
	local f = self.field
	if not f or self.openEdges then return end
	local e = Config.FieldEdgeMargin
	local minX, maxX = f.ox + e, f.ox + (f.nx - 1) * f.sp - e
	local minZ, maxZ = f.oz + e, f.oz + (f.nz - 1) * f.sp - e
	local p = self.pos
	local n
	if p.X < minX then n = Vector3.xAxis; p = Vector3.new(minX, p.Y, p.Z)
	elseif p.X > maxX then n = -Vector3.xAxis; p = Vector3.new(maxX, p.Y, p.Z) end
	if p.Z < minZ then n = (n or ZERO) + Vector3.zAxis; p = Vector3.new(p.X, p.Y, minZ)
	elseif p.Z > maxZ then n = (n or ZERO) - Vector3.zAxis; p = Vector3.new(p.X, p.Y, maxZ) end
	if not n then return end
	n = n.Unit
	self.pos = p
	local into = self.vel:Dot(n)
	if into < 0 then
		self.vel -= n * into * (1 + Config.WallBounce)
		self:shake(5, 0.2)
	end
end

function Movement:fieldUnstick()
	local f = self.field
	if not f then return end
	local y = f:Sample(self.pos.X, self.pos.Z)
	if y and self.pos.Y < y - Config.SnapRayUp then
		self.pos = Vector3.new(self.pos.X, y, self.pos.Z)
	end
end

function Movement:tagged(inst, tag)
	while inst and inst ~= workspace do
		if CollectionService:HasTag(inst, tag) then return inst end
		inst = inst.Parent
	end
	return nil
end

function Movement:shake(amount, duration)
	if self.camera then self.camera:Shake(amount, duration) end
end

function Movement:mostlyGroundedValue()
	return 1 - M.clamp01(M.clamp01(self.sinceGrounded - 0.2) * 5)
end

function Movement:fullyAirborneValue()
	return M.clamp01(M.clamp01(self.sinceGrounded - 0.2) * 5)
end

function Movement:getBoost()
	return math.clamp(self.speedBoost + Config.Boost, 0, 5)
end

function Movement:setVelocity(v)
	self.pending += v - self.vel
end

function Movement:invulnerable()
	return self.invulnerability > 0
end

function Movement:SetInputSource(fn)
	self.inputSource = fn
end

function Movement:sampleInput(dt)
	local inp = self.input
	inp.x, inp.y, inp.magnitude, inp.lookX, inp.lookY, inp.dive, inp.fastRunHeld = 0, 0, 0, 0, 0, false, false
	if self.inputSource then self.inputSource(inp, dt) end
	if self.forceSteerX then inp.x, inp.magnitude = self.forceSteerX, 1 end -- test hook ("steer <x>"): a held steer
	if self.autoSteer and self.mode == "Fast" then
		inp.x = self.forceSteerX or self:autoSteerX()
		inp.dive = inp.dive or self:autoDive()
		inp.dive = inp.dive or os.clock() < (self.forceDiveUntil or 0) -- test hook ("dive <seconds>")
	end
	local held = inp.fastRunHeld
	inp.fastRunPressed = inp.fastRunPressed or (held and not self.fastRunWasHeld)
	self.fastRunWasHeld = held
end

function Movement:updateLook(dt)
	local inp = self.input
	if self.mode == "Fast" then

		local localLook = self.visualCF:VectorToObjectSpace(self:lookDir())
		local target = math.clamp(math.abs(inp.x) - math.abs(inp.lookX), -1, 1)
		self.autoLook = M.lerp(self.autoLook, target, math.min(dt * 2, 1))
		self.yaw += localLook.X * Config.MovementLookSpring * dt * M.clamp01(self.autoLook)
		local extra = (self.fastFalling and not self.mostlyGrounded) and Config.DivePitch or 0
		local pitchTarget = extra + Config.BasePitch - M.unit(self.vel).Y * 20
		self.pitchDown = M.lerp(self.pitchDown, pitchTarget, math.min(dt, 1))
	end
	self.yaw -= inp.lookX
	self.pitchDown = math.clamp(self.pitchDown + inp.lookY, -Config.PitchClamp, Config.PitchClamp)
end

function Movement:lookCFrame()
	return CFrame.fromEulerAnglesYXZ(math.rad(-self.pitchDown), math.rad(self.yaw), 0)
end

function Movement:lookDir()
	return self:lookCFrame().LookVector
end

function Movement:worldMoveDir(autoRun)
	local z = self.input.y
	if autoRun and z > -0.01 then z = 1 end
	local yawCF = CFrame.fromEulerAnglesYXZ(0, math.rad(self.yaw), 0)
	return M.unit(yawCF.RightVector * self.input.x + yawCF.LookVector * z)
end

function Movement:commonTimers(dt)
	self.sinceTerrain += dt
	self.sinceSwitch += dt
	self.sinceRestart += dt
	self.sinceJumped += dt
	if self.mostlyGrounded then self.mostlyGroundedFor += dt else self.mostlyGroundedFor = 0 end
	self.invulnerability = math.max(self.invulnerability - dt, 0)
	self.perfectLandingsFor = math.max(self.perfectLandingsFor - dt, 0)
	self.dontLandFor -= dt
	self.knockedDownFor -= dt
	self.tickVel = self.vel
	self.pending, self.accel = ZERO, ZERO
end

function Movement:tickFast(dt)
	self:commonTimers(dt)
	self.fastFalling = false
	if Config.AllowSlowMode and self.sinceSwitch > 0.1 and self.isGrounded
		and ((Config.AutoSlowOnLowSpeed and self.vel.Magnitude < Config.SlowSwitchSpeed) or self.input.fastRunPressed) then
		self.input.fastRunPressed = false
		self:enterSlow()
		return
	end
	self.input.fastRunPressed = false

	if self.finishWay and self.isGrounded and self.vel.Magnitude < Config.SlowSwitchSpeed then
		self:SetSpeedMultiplier("Finish", nil)
		self.finishWay = nil
		self:enterSlow()
		return
	end

	self:checkDistanceToGround()
	if self.isGrounded then
		self:groundMovement(dt)
	else
		self:airMovement(dt)
	end
	self:grappleTick(dt)
	self:boostTick(dt)
	local grounded, snap = self:groundCollision(dt)
	self.isGrounded = grounded
	if grounded then
		if self.sinceGrounded > 0 then
			self.lastAirTime = self.sinceGrounded
			self.sinceGrounded = 0
		end
		self.safePos, self.safeSpeed = self.pos, self.vel.Magnitude   -- (a fall goes back from here: fallBack)
	else
		self.sinceGrounded += dt
	end
	self.lastPos = self.pos
	self:applySpeedMults(dt)
	if self.finishWay then

		local h = Vector3.new(self.vel.X, 0, self.vel.Z)
		if h.Magnitude > 1e-3 then h = M.rotateTowards(h, self.finishWay * h.Magnitude, dt * 6) end
		local k = math.max(1 - FINISH_DAMP * dt, 0)
		self.vel = Vector3.new(h.X * k, self.vel.Y, h.Z * k)
	end

	local velBefore = self.vel
	self.vel = self.vel + self.pending + self.accel * dt
	local before = snap or self.pos
	self.pos = before + self.vel * dt
	self:solidCollide(before, Solids())
	self:fieldBounds()
	self:fieldUnstick()
	self:checkTraps()

	if grounded and self.wasGrounded then
		local turn = M.angle(velBefore, self.vel)
		self.jitter = M.lerp(self.jitter or 0, turn, 0.05)
		local dvy = math.abs((self.vel.Y - velBefore.Y) - (self.lastDvy or 0))
		self.jitterY = M.lerp(self.jitterY or 0, dvy, 0.05)
		self.lastDvy = self.vel.Y - velBefore.Y
	end
	self.wasGrounded = grounded
end

function Movement:checkDistanceToGround()
	local hit = self:cast(self.pos + UP, self.pos + DOWN * 800)
	self.distanceToGround = hit and hit.distance or 800
	self.belowNormal = hit and hit.normal or nil
end

function Movement:groundMovement(dt)
	local t = M.invLerp(Config.GroundGravityBlend[1], Config.GroundGravityBlend[2], self.vel.Magnitude)
	local gravityDir = M.lerpV(-self.groundNormal, self.gravityDir, t)
	self.accel += gravityDir * Config.GroundGravityMult * Config.Gravity
	self:movement(self:worldMoveDir(true), Config.RunSpeed, dt)
	self:applyDrag()
end

function Movement:airMovement(dt)
	self.accel += self.gravityDir * Config.Gravity
	self:movement(self:worldMoveDir(true), M.lerp(Config.AirSpeed, Config.RunSpeed, self:mostlyGroundedValue()), dt)
	self:applyDrag()
	if self.input.dive then
		self:fastFall(dt)
	end
end

function Movement:fastFall(dt)
	self.fastFalling = true
	local ramp = M.clamp01((self.sinceGrounded - 0.2) * 5)
	self.accel += DOWN * ramp * Config.FastFallSpeed
	local n = M.unit(self.vel)
	local y = M.moveTowards(n.Y, -0.8, Config.FastFallLerp * dt)
	self.vel = M.unit(Vector3.new(n.X, y, n.Z)) * self.vel.Magnitude
end

function Movement:applyDrag()
	self:setVelocity(self.vel * (1 - Config.Drag))
end

function Movement:movement(dir, force, dt)
	force *= 1 + self:getBoost()
	force *= self.speedMult
	self.accel += dir * force * dt
	local h = M.flat(self.vel)
	if M.angle(dir, h) > Config.BrakeAngle then
		self.isBreaking = true
	end
	if self.isBreaking then
		self:applyBreak()
		if self.input.x ~= 0 and self.input.y ~= 0 then
			self:turnTowards(dir, 0.5, dt)
		end
		if M.angle(dir, h) < Config.BrakeReleaseAngle or dir == ZERO then
			self.isBreaking = false
		end
	else
		self:turnTowards(dir, 1, dt)
	end
	local speed = self.vel.Magnitude
	local floor = Config.MinSpeed * self.speedMult
	if not self.isBreaking and speed < floor then
		self.vel = M.lerpV(self.vel, M.unit(self.vel) * floor, dt * Config.MinSpeedRate * (1 - speed / floor))
	end
end

function Movement:applyBreak()
	self:applyDrag()
	if self.isGrounded then
		self:applyDrag()
		self:shake(0.25, 0.1)
	else
		self:shake(0.1, 0.1)
	end
end

function Movement:turnTowards(dir, mult, dt)
	local v = self.vel
	local h = Vector3.new(v.X, 0, v.Z)
	local k = M.invLerp(0, Config.TurnRampAngle, M.angle(dir, h))
	self.turnAmount = h:Cross(dir).Y < 0 and -k or k
	h = M.rotateTowards(h, dir, k * dt * Config.TurnSpeed * self.abilityTurnRate * self.itemTurnRate * mult)
	self:setVelocity(h + Vector3.new(0, v.Y, 0))
end

function Movement:groundCollision(dt)
	if self.forceFalling then return false end
	local hit = self:cast(self.lastPos + UP * Config.SnapRayUp, self.pos + UP * Config.SnapRayUp)
	if not hit and self.dontLandFor <= 0 then
		hit = self:cast(self.pos + UP * Config.SnapRayUp, self.pos)
	end
	self:checkMostlyGrounded()
	if not hit then return false end
	local prop = hit.instance and self:tagged(hit.instance, "SpeedProp")
	if prop and not prop:GetAttribute("Runnable") then
		self:edgeLanding(hit, prop)
		return false
	end
	if self.sinceRestart < 0.5 then
		self:touchGround(self:getLanding(hit), dt)
		return true
	end
	local landing = self:getLanding(hit)
	local moving = hit.instance and hit.instance:IsA("BasePart") and not hit.instance.Anchored
	if M.angle(-self.gravityDir, hit.normal) > Config.WallAngle or moving then
		self:edgeLanding(hit, prop)
		return false
	end
	if not self.isGrounded then
		self:land(landing)
	else
		self:touchGround(landing, dt)
	end
	return true, hit.position
end

function Movement:checkMostlyGrounded()
	local hit = self:cast(self.pos + UP * Config.SnapRayUp, self.pos + DOWN * Config.MostlyGroundedDown)
	self.mostlyGrounded = hit ~= nil
end

function Movement:getLanding(hit)
	local L = { hit = hit, normal = hit.normal }
	L.velBefore = self.vel
	L.speedBefore = self.vel.Magnitude
	L.velAfter = M.lerpV(M.projectOnPlane(self.vel, hit.normal), self.vel, Config.LandingBlend)
	L.speedAfter = L.velAfter.Magnitude
	L.score = L.speedBefore > 1e-4 and L.speedAfter / L.speedBefore or 1
	L.airTime = self.sinceGrounded
	if M.angle(UP, hit.normal) < Config.GroundNormalAccept then
		self.groundNormal = hit.normal
	end
	return L
end

function Movement:emitLanding(kind, L)
	if kind == "Hop" and L.airTime < 0.3 then return end
	local impact = L.speedBefore > 1e-4 and math.deg(math.asin(math.clamp(math.abs(M.unit(L.velBefore):Dot(L.normal)), 0, 1))) or 0
	local info = { kind = kind, score = L.score, impactAngle = impact, speedBefore = L.speedBefore * self.S, airTime = L.airTime, energy = self.energy, time = os.clock() }
	self.lastLanding = info
	table.insert(self.landingLog, info)
	if #self.landingLog > 20 then table.remove(self.landingLog, 1) end
	self.Landed:Fire(info)
end

function Movement:addEnergy(amount)
	self.energy = M.clamp01(self.energy + amount)
end

function Movement:land(L)
	if self.perfectLandingsFor > 0 then L.score = 1 end
	if L.score < Config.BadLandingThreshold and self.vel.Magnitude > Config.BadLandingMinSpeed then
		self:badLanding(L)
		self:emitLanding("Bad", L)
		return
	end
	self:setVelocity(M.unit(L.velAfter) * L.speedBefore)
	if not (self.sinceGrounded > Config.RewardAirTime) then
		self:emitLanding("Hop", L)
		return
	end
	local kind
	if L.score < Config.GoodCutoff then
		kind = "Ok"
		self:addEnergy(Config.LandingEnergy.Ok)
		self:shake(10, 0.3)
	elseif L.score < Config.PerfectCutoff then
		kind = "Good"
		self:addEnergy(Config.LandingEnergy.Good)
		self:shake(2.5, 0.3)
	else
		kind = "Perfect"
		self:addEnergy(Config.LandingEnergy.Perfect)
		self:lerpSpeedTo(Config.PerfectTargetSpeed, Config.PerfectLerp, Config.PerfectMaxGain)
	end
	self:setVelocity(self.vel * L.score)
	self:emitLanding(kind, L)
end

function Movement:badLanding(L)
	local gp = M.projectOnPlane(M.unit(self.vel), self.gravityDir)
	local inNormal = M.lerpV(L.normal, M.unit(gp), 0.1)
	self.vel = M.reflect(self.vel, inNormal)
	local t = M.invLerp(0, Config.BadLandingThreshold, L.score)
	self.vel *= M.lerp(0.5, Config.BadLandingThreshold, t)
	self.dontLandFor = Config.DontLandAfterBad
	self:shake(10, 0.3)
end

function Movement:touchGround(L, dt)
	self:setVelocity(M.unit(L.velAfter) * L.speedBefore)
	local inst = L.hit.instance
	if inst then
		local pad = self:tagged(inst, "SpeedBoost")
		if pad then
			local fwd = pad.CFrame.LookVector
			self.accel += fwd * dt * (pad:GetAttribute("Boost") or 6000)
			self.vel = M.rotateTowards(self.vel, fwd * self.vel.Magnitude, dt * (pad:GetAttribute("Redirect") or 1))
		end
		if inst:IsA("Terrain") then self.sinceTerrain = 0 end
	else
		self.sinceTerrain = 0 -- heightfield = terrain
	end
end

function Movement:edgeLanding(hit, prop)
	local speed = self.vel.Magnitude
	if not prop then
		local past = (hit.position - (self.pos + UP * Config.SnapRayUp)):Dot(hit.normal)
		local gap = (self.ballBody and Config.Ball and Config.Ball.Radius) or 0.02
		if past > -gap then self.pos += hit.normal * (past + gap) end
	end
	self.lastEdge = { name = hit.instance and hit.instance:GetFullName() or "heightfield", normal = hit.normal, at = hit.position * self.S, from = self.pos * self.S }
	if prop and not prop:GetAttribute("Lethal") then
		if not self:invulnerable() then
			self.Hit:Fire("Prop", prop:GetAttribute("Damage") or 15, hit.normal)
			local loss = speed * Config.PropSpeedLoss * (1 - self.speedLossResistance)
			self.vel = M.unit(self.vel) * (speed - loss)
			self:shake(10, 0.3)
		else
			self:shake(5, 0.3)
		end
		self:HitStop(self:invulnerable())
		self:breakProp(prop, hit.position)
		return
	end
	if M.angle(hit.normal, M.unit(self.vel)) < Config.BonkAngle then
		local d = M.unit(M.projectOnPlane(self.vel, hit.normal))
		d = M.lerpV(d, hit.normal, 0.5)
		self.vel = M.unit(d) * speed
		if not self:invulnerable() then self.Hit:Fire("Bonk", Config.BonkDamage, hit.normal) end
		self:shake(10, 0.3)
		return
	end
	if not self:invulnerable() then
		self.knockedDownFor = Config.KnockdownTime
		self.Hit:Fire("HeadOn", prop and (prop:GetAttribute("LethalDamage") or Config.HeadOnDamage) or Config.HeadOnDamage, hit.normal)
	end
	local y = self.vel.Y
	local bounce = hit.normal * speed * Config.WallBounce
	self.vel = Vector3.new(bounce.X, y, bounce.Z)
	self:shake(10, 0.2)
end

function Movement:checkTraps()
	local list = self.genData and self.genData.Traps
	if not (list and list[1]) or self.mode ~= "Fast" then return end
	local now = Traps.Clock()
	local a, b = self.lastPos + UP, self.pos + UP
	for _, trap in list do
		if (self.trapReady[trap] or 0) <= now and Traps.Touches(trap, a, b, now) then
			self.trapReady[trap] = now + (trap.Cooldown or 5)
			if not self:invulnerable() then
				local hit = Config.Map.Traps and Config.Map.Traps.Hit
				local speed = self.vel.Magnitude
				self.vel = M.unit(self.vel) * speed * (1 - (hit and hit.SpeedLoss or 0.35) * (1 - self.speedLossResistance))
				self:shake(12, 0.3)
				self:HitStop(false)
				self.Hit:Fire("Trap", 51, -M.unit(self.vel))
				self.TrapTouched:Fire(trap)
			end
		end
	end
end

function Movement:breakProp(prop, at)
	self.phased[prop] = os.clock() + (Config.PropPhase or 1)
	self:refreshFilter()
	self.PropBroken:Fire(prop, at and at * self.S)
end

function Movement:updatePhased()
	if next(self.phased) == nil then return end
	local now, changed = os.clock(), false
	for prop, untilTime in self.phased do
		if now >= untilTime or not prop.Parent then
			self.phased[prop] = nil
			changed = true
		end
	end
	if changed then self:refreshFilter() end
end

function Movement:lerpSpeedTo(target, amount, maxChange)
	local m0 = self.tickVel.Magnitude
	local m = math.clamp(M.lerp(m0, target, amount), 0, m0 + maxChange)
	if not (m0 > m) then
		self.vel = M.unit(self.tickVel) * m
	end
end

function Movement:applySpeedMults(dt)
	local now = os.clock()
	local mult = 1
	for source, entry in pairs(self.speedMults) do
		if entry.untilTime and now > entry.untilTime then
			self.speedMults[source] = nil
		else
			mult *= entry.mult
		end
	end
	self.speedMult = mult
	if mult < 1 then
		self.pending += -self.vel * (1 - mult) * dt * 1.5
	end
end

function Movement:solidCollide(fromFeet, solids)
	if solids and #solids == 0 then self.sphereCenter = nil return end
	local params = self.solidParams
	if not params then
		params = RaycastParams.new()
		params.RespectCanCollide = true
		self.solidParams = params
	end
	if solids then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = solids
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = self.params.FilterDescendantsInstances
	end
	local S = self.S
	local ballR = Config.Ball and Config.Ball.Radius
	local asBall = self.ballBody and ballR

	local up = (asBall and self.isGrounded and self.groundNormal.Y > 0.3) and self.groundNormal or UP
	local lift = up * (asBall and (ballR + 0.1) or Config.SphereHeight)
	local radius = (asBall and ballR or Config.SphereRadius) * S

	local from = self.sphereCenter or (fromFeet + lift) * S
	local to = (self.pos + lift) * S
	for i = 1, 3 do
		local dir = to - from
		if dir.Magnitude < 1e-3 then break end
		local hit = workspace:Spherecast(from, radius, dir, params)
		if not hit then break end
		local n = hit.Normal
		local contact = from + dir.Unit * math.max(hit.Distance - 0.02, 0)
		local into = self.vel:Dot(n)
		if into < 0 then self.vel -= n * into end
		if M.angle(UP, n) < 60 then self.groundContact = true end
		local rest = dir - dir.Unit * hit.Distance
		rest -= n * rest:Dot(n)

		from, to = contact, (i < 3) and (contact + rest) or contact
	end
	self.pos = to / S - lift
	self.sphereCenter = to
end

function Movement:slowControl()
	local a = self.isGrounded and 1 or Config.Slow.AirControl
	return M.lerp(a, 0.1, M.clamp01(1 - self.sinceSwitch * 0.75))
end

function Movement:slowMoveDir()
	local look = self:lookCFrame()
	local fwd = M.unit(M.flat(look.LookVector))
	local right = M.unit(M.flat(look.RightVector))
	if self.isGrounded and self.groundNormal ~= ZERO then
		fwd = M.unit(M.projectOnPlane(fwd, self.groundNormal))
		right = M.unit(M.projectOnPlane(right, self.groundNormal))
	end
	return M.unit(fwd * self.input.y + right * self.input.x)
end

function Movement:tickSlow(dt)
	self:commonTimers(dt)
	local control = self:slowControl()
	if not self.frozen then
		self.accel += self:slowMoveDir() * Config.Slow.Speed * control * self.input.magnitude
	end
	self.accel += DOWN * Config.Slow.Gravity * self.sinceGrounded
	self.vel -= self.vel * dt * Config.Slow.Drag * control
	local grounded, snap = false, nil
	if self.sinceJumped >= 0.2 then
		grounded, snap = self:slowGroundCollision()
		grounded = grounded or self.groundContact
	end
	self.groundContact = false
	self.isGrounded = grounded
	if grounded then self.sinceGrounded = 0 else self.sinceGrounded += dt end
	self.lastPos = self.pos
	self.turnAmount = 0
	self.vel = self.vel + self.pending + self.accel * dt
	local before = snap or self.pos
	self.pos = before + self.vel * dt
	self:solidCollide(before, nil) -- slow mode collides with everything
	self:fieldBounds()
	self:fieldUnstick()
end

function Movement:slowGroundCollision()
	if self.forceFalling then return false end
	local hit = self:cast(self.pos + UP * Config.SnapRayUp, self.lastPos + UP * Config.SnapRayUp)
	if not hit then

		hit = self:cast(self.pos + UP * Config.SnapRayUp, self.pos + DOWN * (self.ballBody and 0.15 or 0.05))
	end
	self.mostlyGrounded = hit ~= nil
	if not hit then return false end
	local moving = hit.instance and hit.instance:IsA("BasePart") and not hit.instance.Anchored
	if M.angle(-self.gravityDir, hit.normal) > 70 or moving then
		return false
	end
	self.vel = M.projectOnPlane(self.vel, hit.normal)
	self.groundNormal = hit.normal
	if not (hit.instance and hit.instance:IsA("BasePart")) then self.sinceTerrain = 0 end
	return true, hit.position
end

function Movement:updateCharge(dt)
	if self.input.fastRunHeld and self.mostlyGrounded and self.sinceSwitch > 0.1 then
		self.charge = M.moveTowards(self.charge, 1.1, dt)
		self.sinceChargeShake += dt
		if self.sinceChargeShake > 0.1 then
			self:shake(self.charge, 0.4)
			self.sinceChargeShake = 0
		end
		local fwd = M.flat(self:lookDir())
		if fwd.Magnitude > 1e-3 then
			self.visualCF = self.visualCF:Lerp(CFrame.lookAt(ZERO, fwd), math.min(dt * 20, 1))
		end
		if self.charge > Config.ChargeTime then
			self:goFast()
		end
	else
		self.charge = M.moveTowards(self.charge, 0, dt)
	end
end

function Movement:goFast()
	self.charge = 0
	local dir = self:lookDir()
	if self.mostlyGrounded then
		dir = M.projectOnPlane(dir, self.groundNormal)
	end
	self:enterFast()
	self.vel = M.unit(dir) * Config.LaunchSpeed
	if self.camera then self.camera:AddWobble(-M.unit(dir) * 60) end
	self:shake(15, 0.5)
end

function Movement:enterFast()
	if self.mode == "Fast" then return end
	self.mode = "Fast"
	self.sinceSwitch = 0
	self.ModeChanged:Fire("Fast")
end

function Movement:enterSlow()
	if self.mode == "Slow" then return end
	self.mode = "Slow"
	self.sinceSwitch = 0
	self.sinceGrounded = 0
	self.charge = 0
	self.ModeChanged:Fire("Slow")
end

function Movement:GetSpeed() return self.vel.Magnitude * self.S end

function Movement:SetBody(name)
	self.body = name
	self.ballBody = name == "Ball"
	self.bodyCenter = self.ballBody and Config.Ball.Radius or (Config.HumanCenter or 1)
	self.sphereCenter = nil
end
function Movement:GetVelocity() return self.vel * self.S end -- studs/s
function Movement:GetPosition() return self.renderPos * self.S end -- studs, drawn (interpolated)

function Movement:ApplyImpulse(studsPerSecond)
	self.vel += studsPerSecond / self.S
end

function Movement:BoostImpulse(addStuds)
	if self.mode ~= "Fast" then return end
	local add = addStuds / self.S
	self.vel = M.unit(self.vel) * (self.vel.Magnitude + add)
	self:shake(add * 1.3, 0.3)
end

function Movement:SetSpeedMultiplier(source, mult, seconds)
	if mult == 1 or mult == nil then
		self.speedMults[source] = nil
	else
		self.speedMults[source] = { mult = mult, untilTime = seconds and (os.clock() + seconds) or nil }
	end
end

function Movement:SetFrozen(frozen)
	self.frozen = frozen
	if frozen then self.vel = ZERO end
end

function Movement:Finish(way: Vector3?)
	local flat = way and Vector3.new(way.X, 0, way.Z)
	if flat and flat.Magnitude > 1e-3 then
		self.finishWay = flat.Unit
		self:SetSpeedMultiplier("Finish", Config.Race and Config.Race.FinishBrake or 0.05)
	else
		self.finishWay = nil
		self:SetSpeedMultiplier("Finish", nil)
	end
end

function Movement:IsProtected() return self.invulnerability > 0 end
function Movement:Protect(seconds) self.invulnerability = math.max(self.invulnerability, seconds) end

function Movement:Redirect(direction, strengthRadians)
	if self.mode ~= "Fast" then return end
	self.vel = M.rotateTowards(self.vel, M.unit(direction) * self.vel.Magnitude, strengthRadians)
end

function Movement:Launch(directionStuds, speedStuds)
	self:enterFast()
	self.vel = M.unit(directionStuds) * (speedStuds / self.S)
	self.isGrounded, self.sinceGrounded = false, 0
end

local function GrappleConfig()
	return Config.Items and Config.Items.Grapple
end

function Movement:Grapple(at: Vector3 | (() -> Vector3?))
	local G = GrappleConfig()
	if not G then return end
	local runner = type(at) == "function"
	local first = if runner then (at :: () -> Vector3?)() else at :: Vector3
	if not first then return end
	self:enterFast()
	local speed = self.vel.Magnitude
	local lerpTo = G.LerpTo * Config.Pace
	local target = if speed < lerpTo then M.lerp(speed, lerpTo, G.LerpAmount) else speed
	self.grapple = {
		Point = if runner then nil else first / self.S,
		Runner = if runner then at else nil,
		Speed = target * G.Multiplier,
		Pull = math.max(speed, lerpTo) * G.PullSpeed,
		Reach = math.max((first / self.S - self.pos).Magnitude, 1),
		Since = 0,
		Hold = if runner then G.Pull else G.Hold,
	}
	self:shake(G.Shake[1], G.Shake[2])
	if self.camera then self.camera:AddFovImpulse(G.Fov) end
end

function Movement:GrappleRelease()
	local G = GrappleConfig()
	if not self.grapple then return end
	self.grapple = nil
	if G then self:shake(G.Release[1], G.Release[2]) end
	self.GrappleEvent:Fire("Release")
end

function Movement:IsGrappling(): boolean
	return self.grapple ~= nil
end

function Movement:Yank(from: () -> Vector3?, seconds: number?)
	local G = GrappleConfig()
	if not G then return end
	self.yank = { From = from, Since = 0, Duration = seconds or G.Yank, Was = self.vel }
	self:shake(8, 0.25)
end

function Movement:Boost(mult: number, seconds: number)
	local D = Config.Items and Config.Items.Drink
	local G = GrappleConfig()
	local base = math.max(self.vel.Magnitude, (G and G.LerpTo or 120) * Config.Pace)
	self:enterFast()
	self.boost = { Floor = base * mult, Until = os.clock() + seconds, Rate = D and D.Rate or 4 }
	self:shake(6, 0.25)
	if self.camera then self.camera:AddFovImpulse(12) end
end

function Movement:Boosting(): boolean
	return self.boost ~= nil
end

function Movement:Slow(keep: number)
	self.vel *= math.clamp(keep, 0, 1)
	self:shake(12, 0.35)
	self:HitStop(false)
	self.GrappleEvent:Fire("Slowed")
end

function Movement:boostTick(dt)
	local b = self.boost
	if not b then return end
	if os.clock() > b.Until then
		self.boost = nil
		return
	end
	local m = self.vel.Magnitude
	if m < b.Floor and m > 1e-3 then
		self.vel = M.unit(self.vel) * M.lerp(m, b.Floor, math.min(dt * b.Rate, 1))
	end
end

function Movement:grappleTick(dt)
	local G = GrappleConfig()
	local g = self.grapple
	if g and G then
		g.Since += dt
		local at = if g.Runner then g.Runner() else nil
		local point = if at then at / self.S else g.Point
		if g.Since > g.Hold or not point then
			self:GrappleRelease()
		elseif g.Runner then

			local chest = self.pos + UP
			local to = point + UP - chest
			if to.Magnitude * self.S <= G.Meet then
				local fling = math.min(math.max(self.vel.Magnitude, g.Pull) * G.Boost, G.Cap / self.S)
				self.vel = M.unit(self.vel) * fling
				self.grapple = nil
				self:shake(14, 0.35)
				if self.camera then self.camera:AddFovImpulse(G.Fov * 2) end
				self.GrappleEvent:Fire("Slingshot")
			else
				self.vel = self.vel:Lerp(M.unit(to) * g.Pull, math.min(dt * G.PullRate, 1))
			end
		else
			-- Speed's five pulls
			local T = g.Speed
			local away = self.pos - point
			local dist = away.Magnitude
			local toHook = M.unit(-away)
			local swing = M.unit(M.projectOnPlane(self.vel, away))
			local k = M.clamp01(M.invLerp(g.Reach * 0.5, g.Reach, dist)) * M.clamp01(M.invLerp(30, 90, M.angle(self.vel, -away)))
			self.vel = self.vel:Lerp(toHook * T, math.min(dt * G.Towards, 1))
			self.vel = self.vel:Lerp(self:lookDir() * T, math.min(dt * G.Camera, 1))
			self.vel = self.vel:Lerp(UP * T, math.min(dt * G.Up, 1))
			self.vel = self.vel:Lerp(swing * T, math.min(dt * G.Swing * k, 1))
			self.vel = M.unit(self.vel) * M.lerp(self.vel.Magnitude, T, math.min(dt * G.SpeedRate, 1))
		end
	end
	local y = self.yank
	if y and G then
		y.Since += dt
		local from = y.From()
		if from and y.Since < y.Duration then
			local back = M.unit(from / self.S - self.pos) * y.Was.Magnitude * 0.5
			self.vel = self.vel:Lerp(back, math.min(dt * (G.YankRate or 4), 1))
		else

			self.vel = M.unit(if y.Was.Magnitude > 1e-3 then y.Was else self.vel) * y.Was.Magnitude * G.Keep
			self.yank = nil
			self:shake(10, 0.3)
			self:HitStop(false)
			self.GrappleEvent:Fire("Free")
		end
	end
end

local function yawOf(look)
	return math.deg(math.atan2(-look.X, -look.Z))
end

function Movement:resetState(cframe)

	self.spawnCount = ((self.spawnCount or 0) + 1) % 256
	self.pos = cframe.Position / self.S
	self.prevPos, self.lastPos, self.renderPos = self.pos, self.pos, self.pos
	self.sphereCenter = nil
	self.accumulator = 0
	self.isGrounded, self.sinceGrounded = false, 0
	self.knockedDownFor, self.dontLandFor = 0, 0
	self.isBreaking = false
	self.groundNormal = UP
	local look = cframe.LookVector
	self.yaw = yawOf(look)
	self.pitchDown = Config.BasePitch
	self.visualCF = CFrame.lookAt(ZERO, M.flat(look).Magnitude > 1e-3 and M.flat(look) or Vector3.new(0, 0, -1))
	self.waypointIndex = 1
	self.grapple, self.yank, self.boost = nil, nil, nil
end

function Movement:Respawn(cframe, launchStuds)
	self.mode = "Fast"
	self:resetState(cframe)
	self.vel = cframe.LookVector * math.max(Config.RestartSpeed, (launchStuds or 0) / self.S)
	self.sinceRestart = 0
	self.sinceSwitch = 10
	self:Protect(1)
	self.ModeChanged:Fire("Fast")
	if self.camera then self.camera:Snap() end
end

function Movement:RespawnStill(cframe)
	self.mode = "Slow"
	self:resetState(cframe)
	local hit = self:cast(self.pos + UP * 200, self.pos + DOWN * 600)
	if hit then
		self.pos = hit.position
		self.prevPos, self.lastPos, self.renderPos = self.pos, self.pos, self.pos
	end
	self.vel = ZERO
	self.sinceSwitch = 10
	self.ModeChanged:Fire("Slow")
	if self.camera then self.camera:Snap() end
end

function Movement:courseStart(name)
	local course = Movement.FindCourse(name)
	return course and course:FindFirstChild("Start")
end

function Movement:RespawnAtCourse(name, still)
	local start = self:courseStart(name)
	if not start then return false end
	if name ~= self.courseName then self:SetCourse(name) end
	if still then self:RespawnStill(start.CFrame) else self:Respawn(start.CFrame) end
	self.RunStarted:Fire(name)
	return true
end

function Movement:RespawnAtStart()
	self:RespawnAtCourse(self.courseName or Config.CourseName)
end

function Movement:killY()
	return self.course and self.course:GetAttribute("KillY") or Config.KillY
end

function Movement:fallingIntoVoid()
	local top = self.course and self.course:GetAttribute("VoidTop")
	if not top or self.mode ~= "Fast" or self.sinceGrounded < 1.2 or self.vel.Y > 0 then return false end
	local data = self.genData
	if data and data.GapRim and data.GapRim(self.pos.X, self.pos.Z) then return false end
	return (self.pos.Y - self.distanceToGround) * self.S < top
end

function Movement:fallenIn()
	local data = self.genData
	if not (data and data.GapRim) or self.mode ~= "Fast" then return false end
	local rim = data.GapRim(self.pos.X, self.pos.Z)
	if not rim then return false end
	local fall = Config.Map.Pieces and Config.Map.Pieces.Fall
	return self.pos.Y < rim - (fall and fall.Below or 12) * Config.Map.Scale
end

function Movement:fallBack()
	local data, at = self.genData, self.safePos
	if not (data and data.FallBack and at) then return false end
	local n, aim = data.FallBack(at.X, at.Z)
	if n < 1 then return false end
	local fall = Config.Map.Pieces and Config.Map.Pieces.Fall
	local speed = math.max((self.safeSpeed or 0) * (fall and fall.Keep or 0.9) * self.S, fall and fall.Speed or 0)
	local wps = aim and self.course and self.course:FindFirstChild("Waypoints")
	local wp = wps and wps:FindFirstChild(tostring(n))
	if wp then
		local from = wp.Position - Vector3.new(0, 3.5, 0)
		self:Respawn(CFrame.lookAt(from, aim * self.S + Vector3.new(0, 0.5, 0)), speed)
		self.sinceRestart = 10
		self.waypointIndex = n + 1
	elseif not self:RespawnAtWaypoint(n, speed) then
		return false
	end
	self:Protect(fall and fall.Protect or 4)
	return true
end

function Movement:RespawnAtWaypoint(n, speedStuds)
	local wps = self.course and self.course:FindFirstChild("Waypoints")
	local a = wps and wps:FindFirstChild(tostring(n))
	local b = wps and wps:FindFirstChild(tostring(n + 1))
	if not (a and b) then return false end
	local from = a.Position - Vector3.new(0, 3.5, 0)
	self:Respawn(CFrame.lookAt(from, Vector3.new(b.Position.X, from.Y, b.Position.Z)), speedStuds or 300)
	self.sinceRestart = 10
	self.waypointIndex = n + 1
	return true
end

function Movement:SetAutoSteer(on)
	self.autoSteer = on
	self.waypointIndex = 1
end

function Movement:autoDive()
	if self.mostlyGrounded or self.sinceGrounded < 0.15 or not self.belowNormal then return false end
	if self.distanceToGround * self.S < 6 then return false end
	local heading = M.flat(self.vel)
	if heading.Magnitude < 1e-3 then return false end
	local along = M.unit(M.projectOnPlane(heading, self.belowNormal))
	return M.unit(self.vel).Y > along.Y - 0.04
end

function Movement:autoSteerX()
	local wps = self.course and self.course:FindFirstChild("Waypoints")
	if not wps then return 0 end
	local here = self.pos * self.S
	local wp = wps:FindFirstChild(tostring(self.waypointIndex))
	while wp do
		local to = M.flat(wp.Position - here)
		if to.Magnitude < 90 or M.flat(self.vel):Dot(to) <= 0 then
			self.waypointIndex += 1
			wp = wps:FindFirstChild(tostring(self.waypointIndex))
		else
			break
		end
	end
	if not wp then return 0 end
	local heading = M.flat(self.vel)
	if heading.Magnitude < 1e-3 then heading = M.flat(self.visualCF.LookVector) end
	local a = M.signedAngle(heading, M.flat(wp.Position - here), UP)
	return math.clamp(-a / 12, -1, 1)
end

function Movement:HitStop(invulnerable)
	self.collisionTime = 0.05
	self.hitStopHold = invulnerable and 0.05 or 0.1
	self.hitStopRate = invulnerable and 20 or 5
end

function Movement:GetTimeScale()
	return self.collisionTime
end

function Movement:updateTime(realDt)
	if self.hitStopHold > 0 then
		self.hitStopHold -= realDt
	elseif self.collisionTime < 1 then
		self.collisionTime = M.moveTowards(self.collisionTime, 1, realDt * self.hitStopRate)
	end
end

function Movement:checkCloseCalls(dt)
	if self.headless then return end
	self.closeLeft += dt
	self.closeRight += dt
	if self.mode ~= "Fast" or self.vel.Magnitude < 70 * Config.Pace then return end
	local side = M.unit(M.unit(self.vel):Cross(UP))
	if side.Magnitude < 1e-3 then return end
	local chest = self.pos + UP
	local S = self.S
	for _, entry in ipairs({ { dir = side, key = "closeRight", name = "Right" }, { dir = -side, key = "closeLeft", name = "Left" } }) do
		if self[entry.key] > 0.3 then
			local r = workspace:Raycast(chest * S, entry.dir * 10 * S, self.params)
			if r and self:tagged(r.Instance, "SpeedProp") then
				self[entry.key] = 0
				self.CloseCall:Fire(entry.name)
			end
		end
	end
end

function Movement:FrameInput(frameDt)
	self:sampleInput(frameDt)
	self:updateLook(frameDt)
end

function Movement:Step(realDt)
	self:updateTime(realDt)
	local frameDt = realDt * self.collisionTime
	self.filterAge = (self.filterAge or 0) + realDt
	if self.filterAge > 2 then
		Perf.Begin("Speed.Sim.Filter")
		self:refreshFilter()
		Perf.End()
	end
	if self.mode == "Slow" then
		self:updateCharge(frameDt)
	end
	self:updatePhased()
	if self.frozen and self.mode == "Fast" then
		self.vel = ZERO
	else
		self.accumulator = math.min(self.accumulator + frameDt, self.dt * 5)
		Perf.Begin("Speed.Sim.Ticks")
		while self.accumulator >= self.dt do
			self.prevPos = self.pos
			Perf.Count("#ticks")
			if self.mode == "Fast" then
				self:tickFast(self.dt)
			else
				self:tickSlow(self.dt)
			end
			self.accumulator -= self.dt
		end
		Perf.End()
	end
	if self.pos.Y * self.S < self:killY() or (self.mode == "Fast" and self.sinceGrounded > 2 and self.distanceToGround >= 800)
		or self:fallingIntoVoid() or self:fallenIn() then
		if not self:fallBack() then self:RespawnAtStart() end
		return
	end
	Perf.Begin("Speed.Sim.Lift")
	self.renderPos = self:liftOut(self.prevPos:Lerp(self.pos, self.accumulator / self.dt))
	Perf.End()
	self:updateVisual(frameDt)
	Perf.Begin("Speed.Sim.CloseCalls")
	self:checkCloseCalls(frameDt)
	Perf.End()
end

function Movement:updateVisual(dt)
	if self.mode == "Fast" then
		if self.knockedDownFor > 0 then return end
		local vu = M.unit(self.vel)
		local fwd = M.projectOnPlane(vu, self.gravityDir)
		local airUp = M.unit(UP - vu * vu:Dot(UP))
		if airUp.Magnitude < 1e-3 then airUp = self.groundNormal end
		local up = M.unit(M.lerpV(self.groundNormal, airUp, self:fullyAirborneValue()))
		fwd = M.unit(fwd - up * fwd:Dot(up))
		if fwd.Magnitude > 1e-3 then
			self.visualCF = self.visualCF:Lerp(CFrame.lookAt(ZERO, fwd, up), math.min(dt * Config.Visual.TurnRate, 1))
		end
	else
		local dir = self:slowMoveDir()
		local flat = M.flat(dir)
		if flat.Magnitude > 1e-3 then
			self.visualCF = self.visualCF:Lerp(CFrame.lookAt(ZERO, flat), math.min(dt * 20, 1))
		end
	end
end

function Movement:GetDebug()
	return {
		mode = self.mode,
		speed = self:GetSpeed(),
		speedUnits = self.vel.Magnitude,
		grounded = self.isGrounded,
		mostlyGrounded = self.mostlyGrounded,
		sinceGrounded = self.sinceGrounded,
		fastFalling = self.fastFalling,
		braking = self.isBreaking,
		energy = self.energy,
		charge = self.charge,
		height = self.distanceToGround * self.S,
		pos = self.pos * self.S,
		waypoint = self.waypointIndex,
		autoSteer = self.autoSteer,
		course = self.courseName,
		jitter = self.jitter or 0,
		jitterY = self.jitterY or 0,
	}
end

function Movement:Destroy()
	self.Landed:Destroy()
	self.Hit:Destroy()
	self.ModeChanged:Destroy()
	self.CloseCall:Destroy()
	self.RunStarted:Destroy()
	self.TrapTouched:Destroy()
	self.PropBroken:Destroy()
	self.GrappleEvent:Destroy()
end

return Movement
