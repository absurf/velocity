local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFX = {}
if RunService:IsServer() then return VFX end

local ForgeVFX = require(ReplicatedStorage.Shared.Packages.ForgeVFX)
local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local Perf = require(ReplicatedStorage.Shared.Modules.Speed.SpeedPerf)

-- [ FEEL ]-- STARTING VALUES, NOT TUNED.
local LIFE = 3
local LIFT = 2.5
local LAND_AIR = 0.45
local RUN_FROM = 50
local BAD_LOCK = 0.35
local FLAT = 0.6
local STAMPS = 4
local NEAR = { Land = 600, BadLand = 600, Spawn = 800, Run = 260 }

local S = SpeedConfig.Studs
local PACE = SpeedConfig.Pace
local UP = Vector3.yAxis
local LANDINGS = { Ok = true, Good = true, Perfect = true }
local FEET = { "LeftFoot", "RightFoot" }
local RUN_STATES = {}
for state, kind in SpeedConfig.Sound.Steps.States do
	if kind == "Run" then RUN_STATES[state] = true end
end

type Watch = { Entry: any?, Half: number, Air: number, Grounded: boolean, Spawn: number?, Bad: boolean, BadAt: number,
	Seen: number, At: Vector3? }
type Item = { Instance: Instance, Emitters: { { Emitter: ParticleEmitter, Count: number } } }
type Pool = { Items: { Item }, Next: number, Lift: number }

-- [ STATE ]--
local Started = false
local Folder: Folder? = nil
local Live: { { Model: Model, Follow: () -> Vector3?, Way: Vector3, Until: number, Lift: number } } = {}
local Warned: { [string]: true } = {}
local Pools: { [string]: Pool | false } = {}
local Movement: any = nil
local Backend: any, Runners: any = nil, nil
local Mine: Watch? = nil                   -- your runner's
local Copies: { [number]: Watch } = {}     -- other runners', by runner id
local Frame = 0

-- // PRIVATE //--

local function Start()
	if Started then return end
	Started = true
	ForgeVFX.init()
end

local function Template(name: string): Instance?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	node = node and node:FindFirstChild("Speed")
	node = node and node:FindFirstChild("VFX")
	node = node and node:FindFirstChild(name)
	if not node and not Warned[name] then
		Warned[name] = true
		warn("SpeedVFXClient: no effect at Assets.Speed.VFX." .. name .. " (SpeedTools.VFXBuilder)")
	end
	return node
end

local function LiftOf(template: Instance): number
	local lift = template:GetAttribute("Lift")
	return if type(lift) == "number" then lift else LIFT
end

local function GetFolder(): Folder
	if not Folder or not Folder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "SpeedVFX"
		folder.Parent = workspace
		Folder = folder
	end
	return Folder :: Folder
end

local function Pooled(name: string): (Pool?, Item?)
	local pool = Pools[name]
	if pool == nil then
		local template = Template(name)
		if not template then
			Pools[name] = false
			return nil, nil
		end
		local made: Pool = { Items = {}, Next = 0, Lift = LiftOf(template) }
		for i = 1, STAMPS do
			local copy = template:Clone()
			local emitters = {}
			for _, d in copy:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					local count = d:GetAttribute("EmitCount")
					table.insert(emitters, { Emitter = d, Count = if type(count) == "number" then count else 1 })
				end
			end
			copy.Parent = GetFolder()
			made.Items[i] = { Instance = copy, Emitters = emitters }
		end
		Pools[name] = made
		pool = made
	end
	if not pool then return nil, nil end
	pool.Next = pool.Next % #pool.Items + 1
	return pool, pool.Items[pool.Next]
end

local function Put(item: Item, cframe: CFrame)
	local instance = item.Instance
	if instance:IsA("BasePart") then
		instance.CFrame = cframe
	elseif instance:IsA("PVInstance") then
		instance:PivotTo(cframe)
	end
end

local function Play(name: string, instance: Instance)
	Start()
	local ok, err = pcall(ForgeVFX.emit, instance)
	if not ok then warn("SpeedVFXClient: " .. name .. " didn't play: " .. tostring(err)) end
end

local function Up(normal: Vector3?): Vector3
	if normal and normal.Magnitude > 1e-3 then
		local n = normal.Unit
		if n:Dot(UP) >= FLAT then return n end
	end
	return UP
end

local function OnGround(feet: Vector3, up: Vector3, vel: Vector3?, look: Vector3?, lift: number): CFrame
	local fwd: Vector3? = nil
	for _, v in { vel or Vector3.zero, look or Vector3.zero, Vector3.zAxis, Vector3.xAxis } do
		local flat = v - up * v:Dot(up)
		if flat.Magnitude > 1e-3 then
			fwd = flat.Unit
			break
		end
	end
	local way = fwd :: Vector3
	return CFrame.fromMatrix(feet + up * lift, way:Cross(up), up)
end

local function Ground(name: string, feet: Vector3, up: Vector3, vel: Vector3?, look: Vector3?)
	local pool, item = Pooled(name)
	if not (pool and item) then return end
	Put(item, OnGround(feet, up, vel, look, pool.Lift))
	Play(name, item.Instance)
end

local function Puff(name: string, feet: Vector3, up: Vector3, vel: Vector3?, look: Vector3?)
	local pool, item = Pooled(name)
	if not (pool and item) then return end
	Put(item, OnGround(feet, up, vel, look, pool.Lift))
	for _, e in item.Emitters do e.Emitter:Emit(e.Count) end
end

local function Planted(view: any, feet: Vector3, up: Vector3): Vector3
	local model = view and view.model
	if not model then return feet end
	local best: BasePart? = nil
	local low = math.huge
	for _, name in FEET do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local h = (part.Position - feet):Dot(up)
			if h < low then best, low = part, h end
		end
	end
	if not best then return feet end
	local p = best.Position
	p -= up * (p - feet):Dot(up)
	return if (p - feet).Magnitude < 4 then p else feet
end

local function NewWatch(): Watch
	return { Entry = nil, Half = 0, Air = 0, Grounded = true, Spawn = nil, Bad = false, BadAt = -math.huge, Seen = 0, At = nil }
end

local function Stepped(w: Watch, view: any): boolean
	local graph = view and view.graph
	local top = graph and graph.active[#graph.active]
	if not top then
		w.Entry = nil
		return false
	end
	local half = math.floor(top.time * 2)
	if top ~= w.Entry then
		w.Entry, w.Half = top, half
		return false
	end
	local stepped = RUN_STATES[top.state] == true and half > w.Half
	w.Half = half
	return stepped
end

local function DustOn(): boolean
	return SpeedConfig.Fx.Dust ~= false
end

-- ── YOUR RUNNER ──

local function Feet(): Vector3
	return Movement.renderPos * S
end

local function BindMovement(mv)
	Movement = mv
	Mine = NewWatch()
	mv.Landed.Event:Connect(function(info)
		local kind = info.kind
		local up = Up(mv.groundNormal)
		if kind == "Bad" then
			Ground("BadLand", Feet(), up, mv.vel, mv.visualCF.LookVector)
		elseif LANDINGS[kind] or (kind == "Hop" and (info.airTime or 0) >= LAND_AIR) then
			Ground("Land", Feet(), up, mv.vel, mv.visualCF.LookVector)
		end
	end)
	mv.ModeChanged.Event:Connect(function(mode)

		if mode == "Fast" and mv.sinceSwitch >= 5 then
			VFX:Burst("Spawn", Feet, mv.vel)
		end
	end)
end

local function StepMine()
	local mv, w = Movement, Mine
	if not (mv and w) then return end
	local view = Backend:GetBody()
	if Stepped(w, view) and DustOn() and mv.mode == "Fast" and mv.mostlyGrounded and mv.vel.Magnitude / PACE >= RUN_FROM then
		local feet = Feet()
		local up = Up(mv.groundNormal)
		Puff("Run", Planted(view, feet, up), up, mv.vel, mv.visualCF.LookVector)
	end
end

-- ── OTHER RUNNERS ──

local function StepCopies(dt: number, now: number)
	Frame += 1
	local camera = workspace.CurrentCamera.CFrame.Position
	Runners:EachCopy(function(id: number, proxy: any, view: any, at: Vector3)
		local w = Copies[id]
		if not w then

			w = NewWatch()
			w.Spawn, w.Bad, w.Grounded = proxy.spawn, proxy.bad == true, proxy.isGrounded == true
			Copies[id] = w
		end
		w.Seen, w.At = Frame, at
		local far = (at - camera).Magnitude
		local fast = proxy.mode == "Fast"
		local grounded = proxy.isGrounded == true
		local up = Up(proxy.groundNormal)
		local look = proxy.visualCF.LookVector

		-- its steps
		if Stepped(w, view) and fast and proxy.mostlyGrounded and far < NEAR.Run and DustOn()
			and proxy.vel.Magnitude / PACE >= RUN_FROM then
			Puff("Run", Planted(view, at, up), up, proxy.vel, look)
		end

		-- a bad landing: its Bad flag going up
		local bad = proxy.bad == true
		if bad and not w.Bad then
			w.BadAt = now
			if far < NEAR.BadLand then Ground("BadLand", at, up, proxy.vel, look) end
		end
		w.Bad = bad

		-- touching down after a while up
		if grounded and not w.Grounded and w.Air >= LAND_AIR and fast and now - w.BadAt > BAD_LOCK and far < NEAR.Land then
			Ground("Land", at, up, proxy.vel, look)
		end
		w.Air = if grounded then 0 else w.Air + dt
		w.Grounded = grounded

		local spawn = proxy.spawn
		if spawn ~= w.Spawn then
			if w.Spawn ~= nil and fast and far < NEAR.Spawn then
				VFX:Burst("Spawn", function()
					local c = Copies[id]
					return if c and c.Seen == Frame then c.At else nil
				end, proxy.vel)
			end
			w.Spawn = spawn
		end
	end)
	-- gone runners
	for id, w in Copies do
		if w.Seen ~= Frame then Copies[id] = nil end
	end
end

-- ── BURSTS ──

local function Place(entry)
	local at = entry.Follow()
	if not at then return end
	at += Vector3.yAxis * entry.Lift
	entry.Model:PivotTo(CFrame.lookAt(at, at + entry.Way))
end

local function StepBursts()
	if #Live == 0 then return end
	local now = os.clock()
	for i = #Live, 1, -1 do
		local entry = Live[i]
		if now >= entry.Until or not entry.Model.Parent then
			entry.Model:Destroy()
			table.remove(Live, i)
		else
			Place(entry)
		end
	end
end

local function Update(dt: number)
	Perf.Begin("Speed.VFX")
	if Movement and Runners then
		StepMine()
		StepCopies(dt, os.clock())
	end
	StepBursts()
	Perf.End()
end

-- // PUBLIC //--

function VFX:Emit(instance: Instance)
	Start()
	return ForgeVFX.emit(instance)
end

function VFX:Burst(name: string, follow: () -> Vector3?, way: Vector3?, lift: number?)
	local template = Template(name)
	if not template then return end
	local flat = if way then Vector3.new(way.X, 0, way.Z) else Vector3.zero
	local model: Model
	if template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		template:Clone().Parent = model
	end
	local entry = { Model = model, Follow = follow, Way = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1),
		Until = os.clock() + LIFE, Lift = lift or LiftOf(template) }
	Place(entry)
	model.Parent = GetFolder()
	table.insert(Live, entry)
	Play(name, model)
end

function VFX:Stamp(name: string, cframe: CFrame)
	local _, item = Pooled(name)
	if not item then return end
	Put(item, cframe)
	Play(name, item.Instance)
end

function VFX:Test(what: string)
	local mv = Movement
	if not mv then return end
	local feet = Feet()
	local up = Up(mv.groundNormal)
	local look = mv.visualCF.LookVector
	if what == "spawn" then
		VFX:Burst("Spawn", Feet, mv.vel)
	elseif what == "bad" or what == "badland" then
		Ground("BadLand", feet, up, mv.vel, look)
	elseif what == "run" then
		Puff("Run", Planted(Backend and Backend:GetBody(), feet, up), up, mv.vel, look)
	else
		Ground("Land", feet, up, mv.vel, look)
	end
end

function VFX:Init()
	Start()

	RunService:BindToRenderStep("SpeedVFX", Enum.RenderPriority.Camera.Value + 4, Update)
	task.spawn(function()
		Backend = require(script.Parent.SpeedServiceClient)
		local mv
		repeat
			mv = Backend:GetMovement()
			if not mv then task.wait(0.1) end
		until mv
		BindMovement(mv)
		Runners = require(script.Parent.SpeedRunnersClient)
		for _, name in { "Land", "BadLand", "Run" } do Pooled(name) end
	end)
end

return VFX
