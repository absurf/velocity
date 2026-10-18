local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

local Missiles = {}
if RunService:IsServer() then return Missiles end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local Traps = require(ReplicatedStorage.Shared.Modules.Speed.Traps)
local MapClient = require(script.Parent.SpeedMapClient)
local VFX = require(script.Parent.SpeedVFXClient)
local Race: any = nil   -- (SpeedRaceClient, on first use)

local S = SpeedConfig.Studs

-- [ FEEL ]-- STARTING VALUES, NOT TUNED.
local LIVE_RANGE = 2600
local PASSED = 80
local RING = {
	Color = Color3.fromRGB(255, 40, 40),
	Edge = 0.6,               -- the disc's see-through
	Fill = 0.25,              -- the fill's
	Lift = 0.3,               -- studs off the ground
	Linger = 0.12,            -- s the ring stays after the blast starts
}

local SOUND = { Shoot = { Min = 15, Max = 200, Volume = 0.5 }, Blast = { Min = 25, Max = 320, Volume = 0.6 } }
local PARK = CFrame.new(0, -50000, 0)
local TILT = CFrame.Angles(-math.pi / 2, 0, 0)   -- a missile model's nose is its +Y

-- [ STATE ]--
local Folder: Folder? = nil
local Towers: { [any]: any } = {}
local Fresh: { any } = {}
local Stats = { Towers = 0, Live = 0, Flying = 0 }

-- // PRIVATE //--

local function Kit(): Instance?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	node = node and node:FindFirstChild("Speed")
	node = node and node:FindFirstChild("Traps")
	return node and node:FindFirstChild("MissileKit")
end

local function GetFolder(): Folder
	if Folder and Folder.Parent then return Folder end
	local f = Instance.new("Folder")
	f.Name = "SpeedMissiles"
	CollectionService:AddTag(f, "SpeedCameraIgnore")
	f.Parent = workspace
	Folder = f
	return f
end

local function Disc(name: string, transparency: number, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = RING.Color
	p.Transparency = transparency
	p.Size = Vector3.new(0.2, 1, 1)
	p.CFrame = PARK
	p.Parent = parent
	return p
end

local function NewSound(template: Instance?, parent: Instance, range): Sound?
	if not (template and template:IsA("Sound")) then return nil end
	local s = template:Clone()
	s.RollOffMode = Enum.RollOffMode.LinearSquare
	s.RollOffMinDistance, s.RollOffMaxDistance = range.Min, range.Max
	s.Volume = (template :: Sound).Volume * (range.Volume or 1)
	local root = SoundService:FindFirstChild("SpeedSounds")
	local group = root and root:FindFirstChild("Traps")
	if group and group:IsA("SoundGroup") then s.SoundGroup = group end
	s.Parent = parent
	return s
end

local function Build(tower): boolean
	local kit = Kit()
	if not kit then return false end
	local trap = tower.Trap
	local holder = Instance.new("Folder")
	holder.Name = "Tower" .. tostring(trap.Id)
	local tubes = #trap.Tubes
	local shootTemplate, impactTemplate = kit:FindFirstChild("Shoot"), kit:FindFirstChild("Impact")
	tower.Shoots = {}
	for i = 1, tubes do
		local part = shootTemplate and shootTemplate:Clone()
		if part then
			part.CFrame = PARK
			part.Parent = holder
		end
		tower.Shoots[i] = { Part = part, Rot = shootTemplate and shootTemplate.CFrame.Rotation,
			Sound = if i == 1 and part then NewSound(kit:FindFirstChild("ShootSound"), part, SOUND.Shoot) else nil }
	end
	tower.Slots = {}
	for k = 1, tubes * 2 do
		local missile = kit.Missile:Clone()
		local pivot = missile:GetPivot()
		local slot: any = { Missile = missile, Parts = {}, Rel = {}, Emitters = {}, Trails = {} }
		for _, d in missile:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(slot.Parts, d)
				table.insert(slot.Rel, pivot:ToObjectSpace(d.CFrame))
			elseif d:IsA("ParticleEmitter") then
				d.Enabled = false
				table.insert(slot.Emitters, d)
			elseif d:IsA("Trail") then
				d.Enabled = false
				table.insert(slot.Trails, d)
			end
		end
		missile:PivotTo(PARK)
		missile.Parent = holder
		local r = trap.Radius * S
		slot.Ring = Disc("Ring", RING.Edge, holder)
		slot.Ring.Size = Vector3.new(0.2, r * 2, r * 2)   -- (its size never changes: set once)
		slot.Fill = Disc("Fill", RING.Fill, holder)
		if impactTemplate then
			slot.Impact = impactTemplate:Clone()
			slot.Impact.CFrame = PARK
			slot.Impact.Parent = holder
			slot.ImpactRot = impactTemplate.CFrame.Rotation
			slot.Sound = NewSound(kit:FindFirstChild("ExplosionSound"), slot.Impact, SOUND.Blast)
		end
		tower.Slots[k] = slot
	end
	holder.Parent = GetFolder()
	tower.Holder = holder
	return true
end

local function Normal(data, at: Vector3): Vector3
	local h = data.Height
	local dx = h(at.X + 1, at.Z) - h(at.X - 1, at.Z)
	local dz = h(at.X, at.Z + 1) - h(at.X, at.Z - 1)
	return Vector3.new(-dx / 2, 1, -dz / 2).Unit
end

local function Flat(normal: Vector3, at: Vector3): CFrame
	local side = normal:Cross(if math.abs(normal.Z) < 0.9 then Vector3.zAxis else Vector3.xAxis).Unit
	return CFrame.fromMatrix(at, normal, side)
end

local function Push(parts, cframes, part: BasePart?, cf: CFrame)
	if not part then return end
	table.insert(parts, part)
	table.insert(cframes, cf)
end

local function StopFlying(slot, parts, cframes)
	if not slot.Flying then return end
	slot.Flying = false
	for _, e in slot.Emitters do e.Enabled = false end
	for _, t in slot.Trails do t.Enabled = false end
	for _, p in slot.Parts do Push(parts, cframes, p, PARK) end
end

local function StopRing(slot, parts, cframes)
	if not slot.Ringing then return end
	slot.Ringing = false
	Push(parts, cframes, slot.Ring, PARK)
	Push(parts, cframes, slot.Fill, PARK)
end

local function PutAway(tower, parts, cframes)
	for _, slot in tower.Slots or {} do
		StopFlying(slot, parts, cframes)
		StopRing(slot, parts, cframes)
	end
end

local function IsLive(tower, camera: Vector3): boolean
	local e, trap = tower.Entry, tower.Trap
	if (e.Pivot.Position - camera).Magnitude > LIVE_RANGE then return false end
	if not Race then
		local ok, mod = pcall(require, script.Parent.SpeedRaceClient)
		Race = if ok then mod else false
	end
	if not Race then return true end
	local last, track = Race:Field()
	if not (last and track) then return true end
	if tower.Track ~= track then
		tower.Track = track
		local p = e.Data.PointAt(trap.WindowTo)
		local ok, along = pcall(function() return (track:Progress(p * S)) end)
		tower.EndAlong = if ok then along else nil
	end
	return not (tower.EndAlong and last > tower.EndAlong + PASSED)
end

local function PlayTower(tower, now: number, parts, cframes)
	local e, trap = tower.Entry, tower.Trap
	local tubes = #trap.Tubes

	Push(parts, cframes, e.Head, e.Pivot * CFrame.Angles(0, Traps.Turn(trap, now), 0) * e.HeadRel)
	local used = {}
	local ringFor = trap.Flight + trap.Blast + RING.Linger
	local R = trap.Radius * S
	Traps.EachShot(trap, now, function(n, i, launch, from, to)
		local k = (n % 2) * tubes + i
		local slot = tower.Slots[k]
		if not slot then return end
		used[k] = true
		local key = n * 16 + i
		if slot.Key ~= key then
			StopFlying(slot, parts, cframes)
			slot.Key = key
			slot.Ground = Flat(Normal(e.Data, to), to * S)
			slot.Ground += slot.Ground.RightVector * RING.Lift
		end
		local age = now - launch
		local u = age / trap.Flight

		if launch > tower.Last then
			local shoot = tower.Shoots[i]
			if shoot and shoot.Part then
				shoot.Part.CFrame = CFrame.new(from * S) * shoot.Rot
				pcall(VFX.Emit, VFX, shoot.Part)
				if shoot.Sound then shoot.Sound:Play() end
			end
		end
		if u < 1 then
			if not slot.Flying then
				slot.Flying = true
				for _, em in slot.Emitters do em.Enabled = true end
				table.insert(Fresh, slot)
			end
			local pos, way = Traps.Flight(trap, from, to, u)
			local p = pos * S
			local up = if way.Magnitude > 1e-6 and math.abs(way.Unit.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
			local frame = CFrame.lookAt(p, p + way, up) * TILT
			for idx, part in slot.Parts do Push(parts, cframes, part, frame * slot.Rel[idx]) end
			Stats.Flying += 1
		else
			StopFlying(slot, parts, cframes)
			-- came down since last frame: the blast
			if launch + trap.Flight > tower.Last and slot.Impact then
				slot.Impact.CFrame = CFrame.new(to * S) * slot.ImpactRot
				pcall(VFX.Emit, VFX, slot.Impact)
				if slot.Sound then slot.Sound:Play() end
			end
		end

		if age < ringFor then
			slot.Ringing = true
			local fill = math.clamp(math.ceil(u * 20) / 20, 0.05, 1)
			if slot.FillAt ~= fill then
				slot.FillAt = fill
				slot.Fill.Size = Vector3.new(0.3, R * 2 * fill, R * 2 * fill)
			end
			Push(parts, cframes, slot.Ring, slot.Ground)
			Push(parts, cframes, slot.Fill, slot.Ground)
		else
			StopRing(slot, parts, cframes)
		end
	end)
	for k, slot in tower.Slots do
		if not used[k] then
			StopFlying(slot, parts, cframes)
			StopRing(slot, parts, cframes)
		end
	end
end

local function Step(t: number?)
	local now = t or Traps.Clock()
	local camera = workspace.CurrentCamera
	local at = if camera then camera.CFrame.Position else Vector3.zero
	local parts, cframes = {}, {}
	local seen = {}
	Stats.Towers, Stats.Live, Stats.Flying = 0, 0, 0
	MapClient:EachTrap(function(e)
		if e.Trap.Kind ~= "Missile" or not e.Head then return end
		seen[e] = true
		Stats.Towers += 1
		local tower = Towers[e]
		if not tower then
			tower = { Entry = e, Trap = e.Trap, Last = now }
			Towers[e] = tower
		end
		if IsLive(tower, at) and (tower.Holder or Build(tower)) then
			if not tower.Live then tower.Last = now end
			tower.Live = true
			Stats.Live += 1
			PlayTower(tower, now, parts, cframes)
		elseif tower.Live then
			tower.Live = false
			PutAway(tower, parts, cframes)
		end
		tower.Last = now
	end)
	for e, tower in Towers do
		if not seen[e] then   -- (its map's gone)
			if tower.Holder then tower.Holder:Destroy() end
			Towers[e] = nil
		end
	end
	if #parts > 0 then workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) end

	for _, slot in Fresh do
		if slot.Flying then
			for _, tr in slot.Trails do
				tr:Clear()
				tr.Enabled = true
			end
		end
	end
	table.clear(Fresh)
end

-- // PUBLIC //--

function Missiles:Step(t: number?)
	Step(t)
end

function Missiles:Stats()
	return table.clone(Stats)
end

function Missiles:Init()
	RunService:BindToRenderStep("SpeedMissiles", Enum.RenderPriority.Camera.Value + 2, function() Step() end)
end

return Missiles
