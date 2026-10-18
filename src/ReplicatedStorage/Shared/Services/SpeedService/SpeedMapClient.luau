local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Service = {}
if RunService:IsServer() then return Service end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local SpeedSim = require(ReplicatedStorage.Shared.Modules.Speed.SpeedSim)
local Generated = require(ReplicatedStorage.Shared.Modules.Speed.Courses.Generated)
local Traps = require(ReplicatedStorage.Shared.Modules.Speed.Traps)

local S = SpeedConfig.Studs
local VOX = 4               -- studs a voxel
local CH = 16
local SHELL = 40            -- studs of ground under each column's top
local UNDER_KILL = 40
local CLIFF = 160

local LIFT = -1.8
local STEEP = 0.8
local BUDGET = 0.006        -- s of painting a frame
local GRASS = Color3.new(0.281, 0.576, 0.242)   -- Speed's Forest_Theme_Grass_Normal
local PROP_BUDGET = 0.003   -- s of placing props a frame
local SEE_THROUGH = { Trees = true, Bushes = true, Debris = true }   -- kinds the camera doesn't stop at
-- [ FEEL ]-- (STARTING VALUES)
local PHASE = { See = 0.8, In = 0.1, Out = 0.8 }
local LEAVES = {
	See = 0.75,     -- how see-through leaves on your way go
	In = 0.12,
	Out = 0.5,      -- s to come back once they're off your way
	Ahead = 0.7,
	Margin = 6,     -- studs round each point of the way
	Step = 10,      -- studs between the points checked
	Cell = 64,      -- studs: the leaves' grid
}

-- [ STATE ]--
local Started = false
local Painted: { [Instance]: { { number } } } = {}
local Painting: { [Instance]: boolean } = {}          -- courses being painted now
local PropsOf: { [Instance]: Folder } = {}            -- course -> its props' folder
local PaintProgress: { [Instance]: number } = {}
local PropProgress: { [Instance]: number } = {}       -- course -> how far its props are, 0..1
local Turbo = 1
local LeafGrid: { [Instance]: { [number]: { any } } } = {}
type Fade = { Leaf: number, Phase: number, Shown: number, LeafSeen: number, PhaseUntil: number }
local Fades: { [BasePart]: Fade } = {}               -- parts fading now
local TrapsOf: { [Instance]: { any } } = {}
local Frame = 0
local Movement: any = nil

local ChunkInfo: { [number]: { Owner: Instance, Y0: number, Y1: number } } = {}
local function ChunkKey(xa: number, za: number): number
	return math.floor(xa / (CH * VOX) + 0.5) * 65536 + math.floor(za / (CH * VOX) + 0.5)
end

local function IsGenerated(course: Instance): boolean
	return course:IsA("Model") and course:GetAttribute("Heightfield") == "Generated"
end

local function Clear(xa: number, za: number, y0: number, y1: number)
	local height = y1 - y0
	workspace.Terrain:FillBlock(CFrame.new(xa + CH * VOX / 2, y0 + height / 2, za + CH * VOX / 2), Vector3.new(CH * VOX, height, CH * VOX), Enum.Material.Air)
end

local function Wipe(chunks: { { number } }, course: Instance?)
	local clock = os.clock()
	for _, c in chunks do
		local key = ChunkKey(c[1], c[2])
		local info = ChunkInfo[key]
		if info and course and info.Owner ~= course then continue end
		ChunkInfo[key] = nil
		Clear(c[1], c[2], c[3], c[4])
		if os.clock() - clock > BUDGET then
			task.wait()
			clock = os.clock()
		end
	end
end

local function PaintChunk(field, xa: number, za: number, killY: number, floating: ((number, number) -> number?)?): { number }?
	local tops, normals = {}, {}
	local floor = killY - UNDER_KILL
	local lo, hi, any = math.huge, -math.huge, false
	for i = 0, CH + 1 do
		tops[i], normals[i] = {}, {}
		for k = 0, CH + 1 do
			local h, n = field:Sample((xa + (i - 0.5) * VOX) / S, (za + (k - 0.5) * VOX) / S)
			local top = if h then h * S + LIFT else -math.huge
			tops[i][k], normals[i][k] = top, n
			if i >= 1 and i <= CH and k >= 1 and k <= CH and top > floor then
				any = true
				hi = math.max(hi, top)
			end
		end
	end
	if not any then return nil end

	local bottoms, islands = {}, {}
	for i = 1, CH do
		bottoms[i], islands[i] = {}, {}
		for k = 1, CH do
			local top = tops[i][k]
			local low = math.min(top - SHELL, tops[i - 1][k], tops[i + 1][k], tops[i][k - 1], tops[i][k + 1])
			local bottom = math.max(low, floor, top - CLIFF)
			local under = floating and top > floor and floating((xa + (i - 0.5) * VOX) / S, (za + (k - 0.5) * VOX) / S)
			if under then
				bottom = top - math.max(under * S, VOX)
				islands[i][k] = true
			end
			bottoms[i][k] = bottom
			if top > floor then lo = math.min(lo, bottom) end
		end
	end
	local y0 = math.floor(lo / VOX) * VOX
	local y1 = math.ceil((hi + VOX) / VOX) * VOX
	local ny = (y1 - y0) / VOX
	local mats, occ = table.create(CH), table.create(CH)
	for i = 1, CH do
		local mi, oi = table.create(ny), table.create(ny)
		for j = 1, ny do
			mi[j], oi[j] = table.create(CH, Enum.Material.Air), table.create(CH, 0)
		end
		for k = 1, CH do
			local top, bottom = tops[i][k], bottoms[i][k]
			if top > floor then
				local n = normals[i][k]
				local mat = if n and n.Y < STEEP then Enum.Material.Rock else Enum.Material.Grass
				local skin = if islands[i][k] then top - 2 * VOX else -math.huge   -- an island: rock under its grass
				for j = 1, ny do
					local vb = y0 + (j - 1) * VOX
					if vb + VOX > bottom and vb < top then
						local o = math.clamp((top - vb) / VOX, 0, 1)
						mi[j][k], oi[j][k] = if vb + VOX < skin then Enum.Material.Rock else mat, o
					end
				end
			end
		end
		mats[i], occ[i] = mi, oi
	end
	workspace.Terrain:WriteVoxels(Region3.new(Vector3.new(xa, y0, za), Vector3.new(xa + CH * VOX, y1, za + CH * VOX)), VOX, mats, occ)
	return { xa, za, y0, y1 }
end

local function Paint(course: Instance)
	if Painted[course] or Painting[course] then return end
	Painting[course] = true
	local chunks = {}
	local field = SpeedSim.GetField(course)   -- yields while it's built
	if not field or not course.Parent then
		Painting[course] = nil
		return
	end
	workspace.Terrain:SetMaterialColor(Enum.Material.Grass, GRASS)
	local killY = tonumber(course:GetAttribute("KillY")) or -math.huge
	local floating = Generated.ForCourse(course).Floating   -- (built already: GetField asked for it)
	local start = course:FindFirstChild("Start")
	local from = if start and start:IsA("BasePart") then start.Position else Vector3.zero

	local x0 = math.floor(field.ox * S / (CH * VOX)) * CH * VOX
	local z0 = math.floor(field.oz * S / (CH * VOX)) * CH * VOX
	local x1 = (field.ox + (field.nx - 1) * field.sp) * S
	local z1 = (field.oz + (field.nz - 1) * field.sp) * S
	local order = {}
	for xa = x0, x1, CH * VOX do
		for za = z0, z1, CH * VOX do
			local dx, dz = xa + CH * VOX / 2 - from.X, za + CH * VOX / 2 - from.Z
			table.insert(order, { xa, za, dx * dx + dz * dz })
		end
	end
	table.sort(order, function(a, b) return a[3] < b[3] end)
	local clock = os.clock()
	for k, c in order do
		if not course.Parent then break end
		local key = ChunkKey(c[1], c[2])
		local before = ChunkInfo[key]
		if before and before.Owner ~= course then   -- (another map's ground here: gone first)
			Clear(c[1], c[2], before.Y0, before.Y1)
			ChunkInfo[key] = nil
		end
		local done = PaintChunk(field, c[1], c[2], killY, floating)
		if done then
			table.insert(chunks, done)
			ChunkInfo[key] = { Owner = course, Y0 = done[3], Y1 = done[4] }
		end
		PaintProgress[course] = k / #order
		if os.clock() - clock > BUDGET * Turbo then
			task.wait()
			clock = os.clock()
		end
	end
	Painting[course] = nil
	if course.Parent then
		PaintProgress[course] = 1
		Painted[course] = chunks
	else
		Wipe(chunks, course)   -- replaced mid-paint: its own chunks go
	end
end

local function Gone(course: Instance)
	local props = PropsOf[course]
	PropsOf[course] = nil
	PaintProgress[course], PropProgress[course] = nil, nil
	TrapsOf[course] = nil
	LeafGrid[course] = nil
	if props then props:Destroy() end
	local chunks = Painted[course]
	if not chunks then return end
	Painted[course] = nil
	Wipe(chunks, course)
end

local function LavaGround(data, from: Vector3, dir: Vector3, most: number): number   -- units along dir
	local lo, hi = 0, most
	local y = data.Height(from.X + dir.X * hi, from.Z + dir.Z * hi)
	if from.Y + dir.Y * hi > y then return most end
	for _ = 1, 14 do
		local mid = (lo + hi) / 2
		local p = from + dir * mid
		if p.Y > data.Height(p.X, p.Z) then lo = mid else hi = mid end
	end
	return hi
end

local function SpawnTraps(course: Instance, holder: Instance, data)
	local list = data.Traps
	local library = ReplicatedStorage:FindFirstChild("Assets")
	library = library and library:FindFirstChild("Speed")
	library = library and library:FindFirstChild("Traps")
	if not (list and list[1] and library) then return end
	local folder = Instance.new("Folder")
	folder.Name = "Traps"
	CollectionService:AddTag(folder, "SpeedCameraIgnore")
	local entries = {}
	for _, trap in list do
		local asset = library:FindFirstChild(trap.Asset)
		if not asset then continue end
		local model = asset:Clone()
		local entry: any = { Trap = trap, Data = data, Parts = {}, Rel = {} }
		local pivot
		if trap.Kind == "Spinner" then
			local hub = trap.Hub * S
			pivot = CFrame.lookAt(hub, hub + trap.Axis)
			model:PivotTo(pivot)
			local rotor = model:FindFirstChild("Rotor")
			for _, p in (rotor and rotor:GetDescendants() or {}) do
				if p:IsA("BasePart") then
					table.insert(entry.Parts, p)
					table.insert(entry.Rel, pivot:ToObjectSpace(p.CFrame))
				end
			end
		elseif trap.Kind == "Cage" then
			model:ScaleTo(trap.Scale)
			pivot = CFrame.new(trap.Centre * S)
			model:PivotTo(pivot)
			for _, p in model:GetDescendants() do
				if p:IsA("BasePart") then
					table.insert(entry.Parts, p)
					table.insert(entry.Rel, pivot:ToObjectSpace(p.CFrame))
				end
			end
		elseif trap.Kind == "Missile" then

			if trap.Scale and trap.Scale ~= 1 then model:ScaleTo(trap.Scale) end
			pivot = CFrame.new(trap.Foot * S)
			model:PivotTo(pivot)
			entry.Model = model
			entry.Head = model:FindFirstChild("Head")
			entry.HeadRel = entry.Head and pivot:ToObjectSpace(entry.Head.CFrame)
		else
			pivot = CFrame.lookAt(trap.Base * S, trap.Base * S - Vector3.yAxis, Vector3.zAxis)
			model:PivotTo(pivot)
			local beam = model:FindFirstChild("Beam")
			entry.End = beam and beam:FindFirstChild("End")
			entry.Area = beam and beam:FindFirstChild("AreaBeam")
			entry.AreaSize = entry.Area and entry.Area.Size
			entry.AreaRot = entry.Area and (pivot:ToObjectSpace(entry.Area.CFrame) - pivot:ToObjectSpace(entry.Area.CFrame).Position)
			for _, p in model:GetDescendants() do
				if p:IsA("BasePart") and p ~= entry.End and p ~= entry.Area then
					table.insert(entry.Parts, p)
					table.insert(entry.Rel, pivot:ToObjectSpace(p.CFrame))
				elseif p:IsA("Beam") then
					entry.Beams = entry.Beams or {}
					table.insert(entry.Beams, p)
				elseif p:IsA("ParticleEmitter") then
					entry.Emitters = entry.Emitters or {}
					table.insert(entry.Emitters, p)
				end
			end
		end
		entry.Pivot = pivot
		model.Parent = folder
		table.insert(entries, entry)
	end
	folder.Parent = holder
	TrapsOf[course] = entries
end

local TRAP_FAR = 2000
local function StepTraps(t: number?)
	if next(TrapsOf) == nil then return end
	local now = t or Traps.Clock()
	local parts, cframes = {}, {}
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	for _, entries in TrapsOf do
		for _, e in entries do
			local trap = e.Trap
			local frame
			if trap.Kind == "Missile" then continue end   -- (SpeedMissileClient plays them)
			if eye and e.Pivot and (e.Pivot.Position - eye).Magnitude > TRAP_FAR then
				if not e.Far then
					e.Far = true
					for _, b in e.Beams or {} do b.Enabled = false end
					for _, p in e.Emitters or {} do p.Enabled = false end
					e.Size = nil
				end
				continue
			end
			e.Far = false
			if trap.Kind == "Spinner" then
				frame = e.Pivot * CFrame.Angles(0, 0, Traps.Turn(trap, now))
			elseif trap.Kind == "Cage" then
				frame = e.Pivot * Traps.Tumble(trap, now)
			else
				local dir, size = Traps.Beam(trap, now)
				if dir then e.Dir = dir end
				local way = e.Dir or -Vector3.yAxis
				local nozzle = Traps.Nozzle(trap, now)
				local from = nozzle * S
				frame = CFrame.lookAt(from, from + way, if math.abs(way.Z) > 0.9 then Vector3.xAxis else Vector3.zAxis)
				e.From = from
				if size > 0 then
					local reach = LavaGround(e.Data, nozzle, way, trap.Drop * 3) * S
					e.Reach = reach
					if e.End then
						table.insert(parts, e.End)
						table.insert(cframes, frame * CFrame.new(0, 0, -reach))
					end
					if e.Area then
						if e.AreaReach ~= reach then   -- (a size write only when it changes)
							e.AreaReach = reach
							e.Area.Size = Vector3.new(reach, e.AreaSize.Y, e.AreaSize.Z)
						end
						table.insert(parts, e.Area)
						table.insert(cframes, frame * CFrame.new(0, 0, -reach / 2) * e.AreaRot)
					end
				end
				if e.Size ~= size then
					e.Size = size
					for _, b in e.Beams or {} do
						b.Enabled = size > 0.02
						b.Width0 = (b:GetAttribute("W0") or b.Width0) * size
						b.Width1 = (b:GetAttribute("W1") or b.Width1) * size
					end
					for _, p in e.Emitters or {} do p.Enabled = size > 0.6 end
				end
			end
			for i, p in e.Parts do
				table.insert(parts, p)
				table.insert(cframes, frame * e.Rel[i])
			end
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function SpawnProps(course: Instance)
	if PropsOf[course] then return end
	local library = ReplicatedStorage:FindFirstChild("Assets")
	library = library and library:FindFirstChild("Speed")
	library = library and library:FindFirstChild("Props")
	if not library then
		PropProgress[course] = 1
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = course.Name
	PropsOf[course] = holder
	PropProgress[course] = 0
	local list, counts = Generated.Props(Generated.ForCourse(course), true)
	if PropsOf[course] ~= holder or not course.Parent then
		holder:Destroy()
		return
	end
	table.sort(list, function(a, b) return a.Along < b.Along end)   -- from the start on
	local root = workspace:FindFirstChild("SpeedMapProps")
	if not root then
		root = Instance.new("Folder")
		root.Name = "SpeedMapProps"
		root.Parent = workspace
	end
	holder.Parent = root
	SpawnTraps(course, holder, Generated.ForCourse(course))
	local folders = {}
	local leaves = {}
	LeafGrid[course] = leaves
	local clock = os.clock()
	for k, p in list do
		if PropsOf[course] ~= holder then return end   -- the map went: its folder's gone with it
		PropProgress[course] = k / #list
		local folder = folders[p.Kind]
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = p.Kind
			if SEE_THROUGH[p.Kind] then CollectionService:AddTag(folder, "SpeedCameraIgnore") end
			folder.Parent = holder
			folders[p.Kind] = folder
		end
		local kind = library:FindFirstChild(p.Kind)
		local asset = kind and kind:FindFirstChild(p.Asset)
		if asset then
			local model = asset:Clone()
			model:ScaleTo(p.Scale)
			model:PivotTo(p.CFrame)
			if p.Ramp then

				CollectionService:RemoveTag(model, "SpeedProp")
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then d.CanCollide, d.CanQuery = false, false end
				end
			end
			if p.NoShadow then
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then d.CastShadow = false end
				end
			end
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("Leaves") then

					local cf, half = d.CFrame, d.Size / 2
					local extent = Vector3.new(
						math.abs(cf.RightVector.X) * half.X + math.abs(cf.UpVector.X) * half.Y + math.abs(cf.LookVector.X) * half.Z,
						math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z,
						math.abs(cf.RightVector.Z) * half.X + math.abs(cf.UpVector.Z) * half.Y + math.abs(cf.LookVector.Z) * half.Z)
					local entry = { Part = d, Lo = cf.Position - extent, Hi = cf.Position + extent }
					for i = math.floor(entry.Lo.X / LEAVES.Cell), math.floor(entry.Hi.X / LEAVES.Cell) do
						for j = math.floor(entry.Lo.Z / LEAVES.Cell), math.floor(entry.Hi.Z / LEAVES.Cell) do
							local key = i * 1048576 + j
							local cell = leaves[key]
							if not cell then
								cell = {}
								leaves[key] = cell
							end
							table.insert(cell, entry)
						end
					end
				end
			end
			model.Parent = folder
		end
		if os.clock() - clock > PROP_BUDGET * Turbo then
			task.wait()
			clock = os.clock()
		end
	end
	local said = {}
	for name, n in counts do if name ~= "FlatArea" then table.insert(said, n .. " " .. name:lower()) end end
	table.sort(said)
	PropProgress[course] = 1
	print(("[SpeedMap] %s: %s"):format(course.Name, table.concat(said, ", ")))
end

local function FadeOf(part: BasePart): Fade
	local f = Fades[part]
	if not f then
		f = { Leaf = 0, Phase = 0, Shown = 0, LeafSeen = -1, PhaseUntil = 0 }
		Fades[part] = f
	end
	return f
end

local function Phase(prop: Instance)
	local untilTime = os.clock() + (SpeedConfig.PropPhase or 1)
	for _, d in prop:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then FadeOf(d).PhaseUntil = untilTime end
	end
end

local function SeeLeaves(grid: { [number]: { any } }, from: Vector3, to: Vector3)
	local span = to - from
	local steps = math.max(math.ceil(span.Magnitude / LEAVES.Step), 1)
	local m = LEAVES.Margin
	for s = 0, steps do
		local p = from + span * (s / steps)
		local cell = grid[math.floor(p.X / LEAVES.Cell) * 1048576 + math.floor(p.Z / LEAVES.Cell)]
		if cell then
			for _, e in cell do
				local lo, hi = e.Lo, e.Hi
				if p.X > lo.X - m and p.X < hi.X + m and p.Y > lo.Y - m and p.Y < hi.Y + m and p.Z > lo.Z - m and p.Z < hi.Z + m then
					FadeOf(e.Part).LeafSeen = Frame
				end
			end
		end
	end
end

local function Toward(value: number, target: number, rate: number, dt: number): number
	if value < target then return math.min(value + rate * dt, target) end
	return math.max(value - rate * dt, target)
end

local function StepFades(dt: number)
	Frame += 1
	local mv = Movement
	if mv and next(LeafGrid) then
		local you = mv:GetPosition() + Vector3.new(0, 4, 0)
		local ahead = you + mv:GetVelocity() * LEAVES.Ahead
		local camera = workspace.CurrentCamera.CFrame.Position
		for _, grid in LeafGrid do
			SeeLeaves(grid, camera, you)
			SeeLeaves(grid, you, ahead)
		end
	end
	if next(Fades) == nil then return end
	local now = os.clock()
	for part, f in Fades do
		if not part.Parent then
			Fades[part] = nil
			continue
		end
		local leafWant = if f.LeafSeen == Frame then LEAVES.See else 0
		local phaseWant = if now < f.PhaseUntil then PHASE.See else 0
		f.Leaf = Toward(f.Leaf, leafWant, LEAVES.See / (if leafWant > f.Leaf then LEAVES.In else LEAVES.Out), dt)
		f.Phase = Toward(f.Phase, phaseWant, PHASE.See / (if phaseWant > f.Phase then PHASE.In else PHASE.Out), dt)
		local show = math.max(f.Leaf, f.Phase)
		if show ~= f.Shown then
			part.LocalTransparencyModifier = show
			f.Shown = show
		end
		if show == 0 and leafWant == 0 and phaseWant == 0 then Fades[part] = nil end
	end
end

function Service:PaintCourse(course: Instance)
	Paint(course)
end

function Service:WipeCourse(course: Instance)
	Gone(course)
end

function Service:SpawnProps(course: Instance)
	SpawnProps(course)
end

function Service:StepTraps(t: number?)
	StepTraps(t)
end

function Service:LoadProgress(course: Instance): (number, number)
	if not IsGenerated(course) then return 1, 1 end
	return PaintProgress[course] or (if Painted[course] then 1 else 0), PropProgress[course] or 0
end

function Service:SetTurbo(on: boolean)
	Turbo = if on then 6 else 1
end

function Service:EachTrap(fn: (any) -> ())
	for _, entries in TrapsOf do
		for _, e in entries do fn(e) end
	end
end

local PhaseConnection: RBXScriptConnection? = nil
function Service:UseMovement(movement)
	Movement = movement
	if PhaseConnection then PhaseConnection:Disconnect() end
	PhaseConnection = movement.PropBroken.Event:Connect(Phase)
	RunService:UnbindFromRenderStep("SpeedMapFades")
	RunService:BindToRenderStep("SpeedMapFades", Enum.RenderPriority.Camera.Value + 4, StepFades)
end

function Service:Init()
	if Started then return end
	Started = true
	RunService:BindToRenderStep("SpeedMapTraps", Enum.RenderPriority.Camera.Value - 2, function() StepTraps() end)
	task.spawn(function()
		local world = workspace:WaitForChild("World")
		local folder = world:WaitForChild(SpeedConfig.Courses or "Courses")
		folder.ChildAdded:Connect(function(course)
			if IsGenerated(course) then
				task.spawn(Paint, course)
				task.spawn(SpawnProps, course)
			end
		end)
		folder.ChildRemoved:Connect(function(course)
			task.spawn(Gone, course)
		end)
		for _, course in folder:GetChildren() do
			if IsGenerated(course) then
				task.spawn(Paint, course)
				task.spawn(SpawnProps, course)
			end
		end
	end)

	task.spawn(function()
		local Backend = require(script.Parent.SpeedServiceClient)
		local movement = Backend:GetMovement()
		while not movement do
			task.wait(0.2)
			movement = Backend:GetMovement()
		end
		Service:UseMovement(movement)
	end)
end

return Service
