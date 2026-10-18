local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = {}
if RunService:IsServer() then return Sounds end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local Traps = require(ReplicatedStorage.Shared.Modules.Speed.Traps)
local Perf = require(ReplicatedStorage.Shared.Modules.Speed.SpeedPerf)

local CONFIG = SpeedConfig.Sound
local PACE = SpeedConfig.Pace
local S = SpeedConfig.Studs
local UP = Vector3.yAxis
local VOICES = 3

-- [ STATE ]--
local Started = false
local Enabled = CONFIG.Enabled ~= false
local Library: Instance? = nil
local Groups: { [string]: SoundGroup } = {}
local SetCache: { [string]: { Sound } } = {}
local LastPick: { [string]: Sound } = {}
local Rng = Random.new()
local Flat: Folder? = nil                     -- your sounds and the race's: in your ears
local Voices = setmetatable({}, { __mode = "k" }) :: { [Instance]: { [Sound]: { Sound } } }
local SurfaceParams = RaycastParams.new()
local PropParams = RaycastParams.new()
local Movement: any = nil
local Backend: any, Runners: any, MapClient: any = nil, nil, nil
local Me: any = nil                           -- your runner's tracking (NewMe)
local Copies: { [number]: any } = {}          -- other runners' tracking, by runner id
local TrapSounds: { [any]: any } = {}         -- trap entry -> its emitters
local Count: { GoAt: number, Fired: { [number]: boolean } }? = nil
local LastPlaceSound = 0
local Frame = 0

-- // PRIVATE //--

local function Lerp(a: number, b: number, t: number): number return a + (b - a) * t end

local function Set(path: string): { Sound }
	local list = SetCache[path]
	if list then return list end
	list = {}
	for part in path:gmatch("[^|]+") do
		local where, prefix = part:match("^([^:]*):?(.*)$")
		local node: Instance? = Library
		for name in (where or ""):gmatch("[^/]+") do
			node = node and node:FindFirstChild(name)
		end
		if node and node:IsA("Sound") then
			table.insert(list, node)
		elseif node then
			for _, child in node:GetChildren() do
				if child:IsA("Sound") and (prefix == "" or child.Name:sub(1, #prefix) == prefix) then table.insert(list, child) end
			end
		end
	end
	table.sort(list, function(a, b) return a.Name < b.Name end)
	if #list == 0 and Library then warn("[SpeedSound] no sounds for " .. path) end
	SetCache[path] = list
	return list
end

local function Pick(path: string): Sound?
	local list = Set(path)
	local n = #list
	if n == 0 then return nil end
	local pick = list[Rng:NextInteger(1, n)]
	if n > 1 and pick == LastPick[path] then pick = list[(table.find(list, pick) :: number) % n + 1] end
	LastPick[path] = pick
	return pick
end

local function Voice(parent: Instance, template: Sound): Sound
	local byTemplate = Voices[parent]
	if not byTemplate then
		byTemplate = {}
		Voices[parent] = byTemplate
	end
	local list = byTemplate[template]
	if not list then
		list = {}
		byTemplate[template] = list
	end
	for _, s in list do
		if not s.IsPlaying then return s end
	end
	if #list < VOICES then
		local s = template:Clone()
		s.Looped = false
		s.Parent = parent
		table.insert(list, s)
		return s
	end
	local oldest = list[1]
	for _, s in list do
		if s.TimePosition > oldest.TimePosition then oldest = s end
	end
	return oldest
end

local function Range(sound: Sound, near: number, far: number)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = near
	sound.RollOffMaxDistance = far
end

local function GroundAt(feet: Vector3?)
	local name = CONFIG.DefaultSurface
	if feet then
		local hit = workspace:Raycast(feet + UP * 3, -UP * 12, SurfaceParams)
		name = hit and CONFIG.Surfaces[hit.Material.Name] or name
	end
	return CONFIG.Ground[name] or CONFIG.Ground[CONFIG.DefaultSurface]
end

local function Play(layers: { any }?, parent: Instance?, group: SoundGroup?, opts: any?)
	if not (Enabled and layers and parent) then return end
	local scale = (opts and opts.Scale or 1) * CONFIG.Gain
	for _, layer in layers do
		if layer[5] and Rng:NextNumber() > layer[5] then continue end
		local template = Pick(layer[1])
		if not template then continue end
		local s = Voice(parent, template)
		local variation = layer[4] or 0.1
		s.SoundGroup = group
		s.Volume = (layer[2] or 0.1) * scale
		s.PlaybackSpeed = math.max((opts and opts.Pitch or layer[3] or 1) + Rng:NextNumber(-variation / 2, variation / 2), 0.05)
		if opts and opts.Range then Range(s, opts.Range[1], opts.Range[2]) end
		s.TimePosition = 0
		s:Play()
	end
end

local function Loop(path: string, parent: Instance, group: SoundGroup?, range: { number }?): Sound?
	local template = Set(path)[1]
	if not template then return nil end
	local s = template:Clone()
	s.Looped = true
	s.Volume = 0
	s.SoundGroup = group
	if range then Range(s, range[1], range[2]) end
	s.Parent = parent
	return s
end

local function SetLoop(s: Sound?, level: number, pitch: number?, fromStart: boolean?)
	if not s then return end
	local on = Enabled and level > 0.0015
	s.Volume = level * CONFIG.Gain
	if pitch then s.PlaybackSpeed = math.max(pitch, 0.05) end
	if on and not s.IsPlaying then
		s.TimePosition = if fromStart or s.TimeLength <= 0 then 0 else Rng:NextNumber(0, s.TimeLength)
		s:Play()
	elseif not on and s.IsPlaying then
		s:Stop()
	end
end

local function Anchor(name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = workspace.Terrain
	return a
end

local function PlayAt(layers: { any }, at: Vector3, group: SoundGroup?, far: number, pitch: number?)
	if not Enabled then return end
	local a = Anchor("SpeedOneShot")
	a.WorldPosition = at
	Play(layers, a, group, { Range = { far * CONFIG.NearShare, far }, Pitch = pitch })
	task.delay(4, function() a:Destroy() end)
end

local function NewAnim(parent: Instance, group: SoundGroup?, range: { number }?)
	return { Entry = nil, Since = 0, Half = 0, Clock = 0, Queue = {},
		Charge = Loop(CONFIG.Anim.Charge.Set, parent, group, range), ChargeLevel = 0 }
end

local ENDS_FLIGHT = { Running = true, Land1 = true, Land3 = true, Land4 = true, FastFallLand = true, DamageGround = true, SlowMovement = true }

local function StepAnim(anim, view: any, dt: number, emit: (string, string) -> ())
	local anims = CONFIG.Anim
	anim.Clock += dt
	local graph = view and view.graph
	local top = graph and graph.active[#graph.active]
	local state = top and top.state
	if top and top ~= anim.Entry then

		anim.Entry, anim.Since = top, 0
		anim.Half = math.floor(top.time * 2)
		if ENDS_FLIGHT[state] then
			for i = #anim.Queue, 1, -1 do
				if anim.Queue[i].Kind == "Flip" then table.remove(anim.Queue, i) end
			end
		end
		if anims.TakeoffStates[state] then emit("Takeoff", state) end
		for _, at in anims.Flips[state] or {} do table.insert(anim.Queue, { At = anim.Clock + at, Kind = "Flip" }) end
		local land = anims.LandStates[state]
		if land then
			emit(land, state)
			for _, at in anims.RunOut do table.insert(anim.Queue, { At = anim.Clock + at, Kind = "Step" }) end
		end
		if state == "FastFallStart" then emit("DiveStart", state) elseif state == "FastFallEnd" then emit("DiveEnd", state) end
		if anims.HitStates[state] then emit("Hit", state) end
	elseif top then
		anim.Since += dt
	end

	if top and CONFIG.Steps.States[state] then
		local half = math.floor(top.time * 2)
		if half > anim.Half then emit("Step", state) end
		anim.Half = half
	end

	for i = #anim.Queue, 1, -1 do
		local q = anim.Queue[i]
		if anim.Clock >= q.At then
			table.remove(anim.Queue, i)
			emit(q.Kind, state or "")
		end
	end

	local charge = anims.Charge
	local level, pitch = 0, nil
	if state == "DashStart" then
		local t = anim.Since
		level = if t < 0.5 then charge.Volume[1] * t / 0.5 else Lerp(charge.Volume[1], charge.Volume[2], math.min((t - 0.5) / 0.5, 1))
		pitch = charge.Pitch * math.min(t, 1)
		if anim.ChargeLevel <= 0 and anim.Charge then anim.Charge:Stop() end   -- a new hold: from its start
		anim.ChargeLevel = level
	else
		anim.ChargeLevel = math.max(anim.ChargeLevel - dt * 20 * charge.Volume[2], 0)   -- (Speed's loop follows at 20/s)
		level = anim.ChargeLevel
	end
	SetLoop(anim.Charge, level, pitch, true)
end

local function StepSound(state: string, speed: number, ground, parent: Instance, group: SoundGroup?, range: { number }?)
	local steps = CONFIG.Steps
	local walk = steps.States[state] == "Walk"
	if walk and speed < steps.WalkFrom then return end
	local opts = { Range = range }
	Play(if walk then steps.Walk else steps.Run, parent, group, opts)
	Play(ground.Step, parent, group, { Range = range, Scale = if walk then steps.WalkGround else 1 })
end

local function AnimSound(kind: string, state: string, speed: number, feet: Vector3, parent: Instance, group: SoundGroup?, range: { number }?)
	local anims = CONFIG.Anim
	if kind == "Step" then
		StepSound(if CONFIG.Steps.States[state] then state else "Running", speed, GroundAt(feet), parent, group, range)
	elseif kind == "Land1" or kind == "Land2" then
		Play(anims[kind], parent, group, { Range = range })
		Play({ { GroundAt(feet).Land, anims.LandGround } }, parent, group, { Range = range })
	elseif anims[kind] then
		Play(anims[kind], parent, group, { Range = range })
	end
end

-- ── YOUR RUNNER ──

local function Feet(): Vector3 return Movement.renderPos * S end

local function NewMe()
	local you = Groups.You
	local wind = CONFIG.Wind
	local flat = Flat :: Folder
	return {
		Wind = {
			Grounded = { Sound = Loop(wind.Grounded.Set, flat, you), Level = 0 },
			Air = { Sound = Loop(wind.Air.Set, flat, you), Level = 0 },
			Fall = { Sound = Loop(wind.Fall.Set, flat, you), Level = 0 },
		},
		Ambience = Loop(wind.Ambience.Set, flat, you),
		AmbienceLevel = wind.Ambience.Ground,
		Anim = NewAnim(flat, you, nil),
		Passby = { Left = { At = 0 }, Right = { At = 0 } },
	}
end

local function BindMovement(mv)
	Movement = mv
	Me = NewMe()
	local you = CONFIG.You
	mv.Landed.Event:Connect(function(info)
		local grade = you.Grades[info.kind]
		if not grade then return end
		Play(grade, Flat, Groups.You)
		if info.kind ~= "Bad" then Play(you.Energy, Flat, Groups.You, { Pitch = 0.5 + (info.energy or mv.energy or 0) }) end
	end)
	mv.Hit.Event:Connect(function(kind)
		Play(you.Stinger, Flat, Groups.You)
		if kind == "Trap" then Play(you.Trap, Flat, Groups.You) end
	end)
	mv.PropBroken.Event:Connect(function(prop, at)

		local kind = prop and prop.Parent and prop.Parent.Name or ""
		local set = if kind:find("Tree") or kind:find("Bush") or kind:find("Log") then you.Break.Tree else you.Break.Rock
		PlayAt(set, at or Feet(), Groups.You, you.Break.Far)
	end)
	mv.ModeChanged.Event:Connect(function(mode)
		if mode ~= "Fast" then return end

		if mv.sinceSwitch < 5 then Play(you.Go, Flat, Groups.You) else Play(you.Respawn, Flat, Groups.You) end
	end)
end

local function StepPassby(now: number, speed: number)
	local pass = CONFIG.You.Passby
	local props = workspace:FindFirstChild("SpeedMapProps")
	if not props or speed < pass.From or Movement.mode ~= "Fast" then return end
	local vel = Movement.vel
	local flat = Vector3.new(vel.X, 0, vel.Z)
	if flat.Magnitude < 1e-3 then return end
	local fwd = flat.Unit
	local right = fwd:Cross(UP)
	PropParams.FilterDescendantsInstances = { props }
	local from = Feet() + UP * pass.Height + fwd * pass.Ahead
	for side, dir in { Left = -right, Right = right } do
		local st = Me.Passby[side]
		if now - st.At < pass.Cooldown then continue end
		local hit = workspace:Raycast(from, dir * pass.Side, PropParams)
		local prop = hit and hit.Instance:FindFirstAncestorWhichIsA("Model")
		if prop and prop ~= st.Prop then
			st.At, st.Prop = now, prop
			PlayAt(pass.Layers, hit.Position, Groups.You, CONFIG.World.Far * 2, pass.Pitch + pass.PerSpeed * speed)
		end
	end
end

local function StepMe(dt: number, now: number)
	local mv = Movement
	local wind = CONFIG.Wind
	local vel = mv.vel
	local speed = vel.Magnitude / PACE          -- Speed's m/s
	local down = math.max(-vel.Y / PACE, 0)
	local grounded = mv.mostlyGrounded
	local fast = mv.mode == "Fast"

	local on = speed >= wind.From and fast
	local targets = {
		Grounded = if on and grounded then math.min(wind.Grounded.Volume * speed, wind.Max) else 0,
		Air = if on and not grounded then math.min(wind.Air.Volume * speed, wind.Max) else 0,
		Fall = if on then math.min(wind.Fall.Volume * down, wind.Max) else 0,
	}
	local pitches = { Grounded = 1 + wind.Grounded.Pitch * speed, Air = 1 + wind.Air.Pitch * speed, Fall = 1 + wind.Fall.Pitch * down }
	local cut = mv:GetTimeScale() < 0.1
	for name, loop in Me.Wind do
		loop.Level = if cut then 0 else loop.Level + (targets[name] - loop.Level) * math.min(wind.Fade * dt, 1)
		SetLoop(loop.Sound, loop.Level, if on then pitches[name] else nil)
	end

	local amb = wind.Ambience
	local height = math.max((mv.distanceToGround or 0), 1)   -- Speed's m
	local target = amb.High + (amb.Ground - amb.High) / height
	Me.AmbienceLevel += (target - Me.AmbienceLevel) * math.min(amb.Rate * dt, 1)
	SetLoop(Me.Ambience, Me.AmbienceLevel)

	-- your body's animations
	local feet = Feet()
	StepAnim(Me.Anim, Backend:GetBody(), dt * mv:GetTimeScale(), function(kind, state)
		AnimSound(kind, state, speed, feet, Flat :: Folder, Groups.You, nil)
	end)

	StepPassby(now, speed)
end

-- ── OTHER RUNNERS ──

local function NewCopy(id: number)
	local anchor = Anchor("SpeedRunnerSound" .. id)
	local world = { CONFIG.World.Near, CONFIG.World.Far }
	return {
		Anchor = anchor,
		Anim = NewAnim(anchor, Groups.Others, world),
		Grounded = true, Air = 0, Mode = nil, Scale = 1,
		PassAt = 0, HitAt = 0,
	}
end

local function StepCopies(dt: number, now: number)
	local others = CONFIG.Others
	local world = { CONFIG.World.Near, CONFIG.World.Far }
	local group = Groups.Others
	local camera = workspace.CurrentCamera.CFrame.Position
	local myVel = if Movement then Movement.vel * S else Vector3.zero
	Frame += 1
	Runners:EachCopy(function(id: number, proxy: any, view: any, at: Vector3)
		local c = Copies[id]
		if not c then
			c = NewCopy(id)
			Copies[id] = c
		end
		c.Seen = Frame
		c.Anchor.WorldPosition = at + UP * 2
		local far = (at - camera).Magnitude
		local heard = far < world[2]
		local vel = proxy.vel * S
		local speed = proxy.vel.Magnitude / PACE
		local fast = proxy.mode == "Fast"
		local grounded = proxy.isGrounded
		local scale = proxy.timeScale or 1

		StepAnim(c.Anim, view, dt * scale, function(kind, state)
			if not heard or (kind == "Step" and far > CONFIG.Steps.Within) then return end
			AnimSound(kind, state, speed, at, c.Anchor, group, world)
		end)
		if not heard then
			c.Mode, c.Grounded, c.Scale = proxy.mode, grounded, scale
			c.Air = if grounded then 0 else c.Air + dt
			return
		end

		-- a launch: Slow -> Fast
		if c.Mode == "Slow" and fast then Play(CONFIG.You.Go, c.Anchor, group, { Range = world }) end
		c.Mode = proxy.mode

		if grounded and not c.Grounded and c.Air >= others.LandAir and fast then
			AnimSound(others.Land, "", speed, at, c.Anchor, group, world)
			for _, t in CONFIG.Anim.RunOut do table.insert(c.Anim.Queue, { At = c.Anim.Clock + t, Kind = "Step" }) end
		end
		c.Air = if grounded then 0 else c.Air + dt
		c.Grounded = grounded

		-- a hit: its clock in a hit-stop
		if scale < 0.5 and c.Scale >= 0.5 and now - c.HitAt > 0.3 then
			c.HitAt = now
			Play(others.Hit, c.Anchor, group, { Range = world })
		end
		c.Scale = scale

		-- flying past you
		local pass = others.Passby
		local rel = vel - myVel
		local closing = rel.Magnitude / S / PACE
		if far < pass.Within and closing > pass.Closing and (at - camera):Dot(rel) < 0 and now - c.PassAt > pass.Cooldown then
			c.PassAt = now
			Play(pass.Layers, c.Anchor, group, { Range = world, Pitch = pass.Pitch + pass.PerSpeed * closing })
		end
	end)
	-- gone runners: their sounds go
	for id, c in Copies do
		if c.Seen ~= Frame then
			c.Anchor:Destroy()
			Copies[id] = nil
		end
	end
end

-- ── TRAPS ──

local function TrapLoops(defs: { any }, anchor: Attachment)
	local loops = {}
	for _, def in defs do
		table.insert(loops, { Def = def, Sound = Loop(def.Set, anchor, Groups.Traps, { def.Far * (CONFIG.TrapNear or CONFIG.NearShare), def.Far }) })
	end
	return loops
end

local function NewTrapSound(e)
	local def = CONFIG.Traps
	local kind = e.Trap.Kind
	local t = { Kind = kind, Anchor = Anchor("SpeedTrapSound") }
	if kind == "Spinner" then
		t.Loops = TrapLoops(def.Spinner.Hub, t.Anchor)
		t.Tip = Anchor("SpeedTrapSound")
		t.TipLoops = TrapLoops({ def.Spinner.Beam }, t.Tip)
	elseif kind == "Cage" then
		t.Loops = TrapLoops(def.Cage, t.Anchor)
	elseif kind == "Lava" then
		t.Loops = TrapLoops(def.Lava, t.Anchor)
	else
		t.Anchor:Destroy()
		return nil
	end
	return t
end

local function DropTrapSound(t)
	t.Anchor:Destroy()
	if t.Tip then t.Tip:Destroy() end
end

local function SetLoops(loops, scale: number)
	for _, l in loops do SetLoop(l.Sound, l.Def.Volume * scale, l.Def.Pitch) end
end

local function StepTraps(now: number)
	local camera = workspace.CurrentCamera.CFrame.Position
	local within = CONFIG.Traps.Within
	local clock = Traps.Clock()
	local seen = {}
	MapClient:EachTrap(function(e)
		local trap = e.Trap
		local at = if e.Pivot then e.Pivot.Position else nil
		if not at then return end
		local t = TrapSounds[e]
		if (at - camera).Magnitude > within * (if t then 1.1 else 1) then return end
		if not t then
			t = NewTrapSound(e)
			if not t then return end
			TrapSounds[e] = t
		end
		seen[e] = true
		if t.Kind == "Spinner" then
			t.Anchor.WorldPosition = at
			SetLoops(t.Loops, 1)

			local hub, turn = trap.Hub * S, Traps.Turn(trap, clock)
			local best, bestDistance = hub, math.huge
			for _, spoke in trap.Spokes or {} do
				local ang = spoke + turn
				local tip = hub + (trap.Right * math.cos(ang) + trap.Up * math.sin(ang)) * trap.Arm * S
				local d = (tip - camera).Magnitude
				if d < bestDistance then best, bestDistance = tip, d end
			end
			t.Tip.WorldPosition = best
			SetLoops(t.TipLoops, 1)
		elseif t.Kind == "Cage" then
			t.Anchor.WorldPosition = at
			SetLoops(t.Loops, 1)
		else
			-- a lava beam: where it lands, x its size
			local size = e.Size or 0
			if size > 0.01 and e.From and e.Dir and e.Reach then t.Anchor.WorldPosition = e.From + e.Dir * e.Reach end
			SetLoops(t.Loops, size)
		end
	end)
	for e, t in TrapSounds do
		if not seen[e] then
			DropTrapSound(t)
			TrapSounds[e] = nil
		end
	end
end

-- ── THE RACE ──

local function StepCount()
	local count = Count
	if not count then return end
	local beats = SpeedConfig.Hud.Countdown
	local now = workspace:GetServerTimeNow()
	for n = beats.Beats, 0, -1 do
		local mark = count.GoAt - n * beats.Beat
		if now >= mark and not count.Fired[n] then
			count.Fired[n] = true

			if now - mark < 0.3 then Play(if n == 0 then CONFIG.Race.Go else CONFIG.Race.Beat, Flat, Groups.Ui) end
		end
	end
	if now > count.GoAt + 1 then Count = nil end
end

local function Update(dt: number)
	if not Movement then return end
	Perf.Begin("Speed.Sound")
	local now = os.clock()
	StepMe(dt, now)
	StepCopies(dt, now)
	StepTraps(now)
	StepCount()
	Perf.End()
end

local function MakeGroups()
	local root = SoundService:FindFirstChild("SpeedSounds") :: SoundGroup?
	if not root then
		local made = Instance.new("SoundGroup")
		made.Name = "SpeedSounds"
		made.Parent = SoundService
		root = made
	end
	local master = root :: SoundGroup
	master.Volume = CONFIG.Master or 1
	for name, volume in CONFIG.Mix do
		local group = (master:FindFirstChild(name) or Instance.new("SoundGroup")) :: SoundGroup
		group.Name = name
		group.Volume = volume
		group.Parent = master
		Groups[name] = group
	end
	local flat = Instance.new("Folder")
	flat.Name = "SpeedFlatSounds"
	flat.Parent = SoundService
	Flat = flat
end

local function Start()
	local assets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Speed")
	Library = assets:WaitForChild(CONFIG.Folder, 30)
	if not Library then
		warn("[SpeedSound] no ReplicatedStorage.Assets.Speed." .. CONFIG.Folder .. " (SpeedTools.SoundsBuilder): no sounds")
		return
	end
	MakeGroups()
	local world = workspace:WaitForChild("World")
	SurfaceParams.FilterType = Enum.RaycastFilterType.Include
	SurfaceParams.FilterDescendantsInstances = { workspace.Terrain, world }
	PropParams.FilterType = Enum.RaycastFilterType.Include
	Backend = require(script.Parent.SpeedServiceClient)
	Runners = require(script.Parent.SpeedRunnersClient)
	MapClient = require(script.Parent.SpeedMapClient)
	local mv
	repeat
		mv = Backend:GetMovement()
		if not mv then task.wait(0.1) end
	until mv
	BindMovement(mv)

	RunService:BindToRenderStep("SpeedSounds", Enum.RenderPriority.Camera.Value + 5, Update)
end

-- // PUBLIC //--

function Sounds:Countdown(goAt: number)
	Count = { GoAt = goAt, Fired = {} }
end

function Sounds:Place(place: number, last: number?)
	if not last or place == last then return end
	local now = os.clock()
	if now - LastPlaceSound < CONFIG.Race.PlaceGap then return end
	LastPlaceSound = now
	Play(if place < last then CONFIG.Race.PlaceUp else CONFIG.Race.PlaceDown, Flat, Groups.Ui)
end

function Sounds:Finish()
	Play(CONFIG.Race.Finish, Flat, Groups.Ui)
end

function Sounds:Play(path: string, volume: number?)
	Play({ { path, volume or 0.25 } }, Flat, Groups.You)
end

function Sounds:SetEnabled(on: boolean)
	Enabled = on
	if on then return end
	for _, parent in { Flat, workspace.Terrain } do
		for _, d in if parent then parent:GetDescendants() else {} do
			if d:IsA("Sound") then d:Stop() end
		end
	end
end

function Sounds:Stats()
	local copies, traps, playing = 0, 0, 0
	for _ in Copies do copies += 1 end
	for _ in TrapSounds do traps += 1 end
	for _, parent in { Flat, workspace.Terrain } do
		for _, d in if parent then parent:GetDescendants() else {} do
			if d:IsA("Sound") and d.IsPlaying then playing += 1 end
		end
	end
	return { Copies = copies, Traps = traps, Playing = playing }
end

function Sounds:Init()
	if Started then return end
	Started = true
	task.spawn(Start)
end

return Sounds
