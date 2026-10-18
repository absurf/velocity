local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local Graph = require(ReplicatedStorage.Shared.Modules.Speed.CourierGraph)
local Clips = require(ReplicatedStorage.Shared.Modules.Speed.CourierClips)

local HumanView = {}
HumanView.__index = HumanView

function HumanView.new(movement, parent, userId)
	local self = setmetatable({}, HumanView)
	self.movement = movement
	self.parent = parent
	self.S = Config.Studs
	local human = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Speed"):WaitForChild("Human")
	local model = human:WaitForChild("Rig"):Clone()
	model.Name = "__SpeedHuman"
	self:_Use(model)
	self.clips = Clips.new(human:WaitForChild("Clips"))
	self.graph = Graph.new()
	self.acc, self.wsum = {}, {}
	self.visible = false
	if userId then self:_Await(userId) end
	self.conns = {
		movement.Landed.Event:Connect(function(info)
			self.graph:Land(info.kind, movement.input.dive)
		end),
		movement.Hit.Event:Connect(function(kind, damage, normal)
			local side = 0
			if typeof(normal) == "Vector3" then
				side = (-normal):Dot(movement.visualCF.RightVector)
				side = side > 0.35 and 1 or (side < -0.35 and -1 or 0)
			end
			self.graph:Damage(side)
		end),
	}

	task.spawn(function()
		for i, name in ipairs(Graph.ClipNames()) do
			self.clips:Get(name)
			if i % 4 == 0 then task.wait() end
		end
	end)
	return self
end

function HumanView:_Use(model)
	self.model = model
	self.hrp = model:WaitForChild("HumanoidRootPart")
	self.rootHeight = model:GetAttribute("RootHeight") or 3.19
	self.motors = {}
	for _, m in ipairs(model:GetDescendants()) do
		if m:IsA("Motor6D") and m.Part1 then self.motors[m.Part1.Name] = m end
	end
	self.movement:AddIgnore(model)
end

function HumanView:_Await(userId)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(Config.Avatars, 60)
		if not folder or self.dead then return end
		local key = tostring(userId)
		local avatar = folder:FindFirstChild(key)
		if avatar then
			self:_Wear(avatar)
			return
		end
		self.avatarConn = folder.ChildAdded:Connect(function(child)
			if child.Name == key then self:_Wear(child) end
		end)
	end)
end

function HumanView:_Wear(template)
	if self.dead then return end
	if self.avatarConn then
		self.avatarConn:Disconnect()
		self.avatarConn = nil
	end
	local old = self.model
	local model = template:Clone()
	model.Name = old.Name
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.CanCollide, p.CanQuery, p.CanTouch = false, false, false end
	end
	local ignore = self.movement.ignore
	local at = ignore and table.find(ignore, old)
	if at then table.remove(ignore, at) end
	self:_Use(model)
	if self.visible then model.Parent = old.Parent end
	old:Destroy()
	self.movement:refreshFilter()
	if self.OnWear then self.OnWear(model) end
end

function HumanView:SetVisible(on)
	self.visible = on
	self.model.Parent = on and (self.parent or workspace) or nil
	self.movement:refreshFilter()
end

function HumanView:state()
	local mv = self.movement
	local inp = mv.input
	local x, y = inp.x, inp.y
	local mag = math.min(math.sqrt(x * x + y * y), 1)
	local relX, relY = 0, 0
	if mag > 0.2 then
		local yawCF = CFrame.fromEulerAnglesYXZ(0, math.rad(mv.yaw), 0)
		local dir = (yawCF.RightVector * x + yawCF.LookVector * y).Unit
		local loc = mv.visualCF:VectorToObjectSpace(dir)
		relX, relY = loc.X * mag, -loc.Z * mag
	end
	local v = mv.vel
	return {
		mode = mv.mode,
		speed = v.Magnitude / Config.Pace,
		isGrounded = mv.isGrounded,
		mostlyGrounded = mv.mostlyGrounded,
		velUnitY = v.Magnitude > 1e-4 and v.Unit.Y or 0,
		relX = relX,
		relY = relY,
		fastFall = inp.dive,
		charging = inp.fastRunHeld and mv.mostlyGrounded and mv.sinceSwitch > 0.1,
	}
end

function HumanView:Update(dt)
	if not self.visible then return end
	local mv = self.movement
	local draw = self.graph:Step(self:state(), dt, self.clips)
	local acc, wsum = self.acc, self.wsum
	table.clear(acc)
	table.clear(wsum)
	for _, d in ipairs(draw) do
		self.clips:Accumulate(d.name, d.time, d.weight, acc, wsum)
	end
	for name, motor in pairs(self.motors) do
		motor.Transform = acc[name] or CFrame.identity
	end
	local feet = mv.renderPos * self.S
	self.hrp.CFrame = CFrame.new(feet) * mv.visualCF.Rotation * CFrame.new(0, self.rootHeight, 0)
end

function HumanView:GetState()
	return self.graph.state
end

function HumanView:Destroy()
	self.dead = true
	if self.avatarConn then self.avatarConn:Disconnect() end
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.model:Destroy()
end

return HumanView
