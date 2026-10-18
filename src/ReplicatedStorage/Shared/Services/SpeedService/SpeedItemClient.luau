local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Items = {}
if RunService:IsServer() then return Items end

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local ControlsConfig = require(ReplicatedStorage.Shared.Modules.Configs.ControlsConfig)
local Generated = require(ReplicatedStorage.Shared.Modules.Speed.Courses.Generated)
local Backend = require(script.Parent.SpeedServiceClient)
local Runners = require(script.Parent.SpeedRunnersClient)
local Sounds = require(script.Parent.SpeedSoundClient)
local VFX = require(script.Parent.SpeedVFXClient)
local ItemHolder = require(ReplicatedStorage.UI.Holders.ItemHolder)
local GUIController = require(ReplicatedStorage.UI.GUIController)
local ReticleUI = require(ReplicatedStorage.UI.Reticle)

local Player = Players.LocalPlayer
local ITEMS = SpeedConfig.Items
local CARDS = ITEMS and ITEMS.Cards
local G = ITEMS and ITEMS.Grapple
local S = SpeedConfig.Studs

-- [ FEEL ]-- STARTING VALUES, NOT TUNED.
local IDLE = {
	Bob = 0.7, BobRate = 2.2,      -- studs up and down, radians a second
	Spin = 75,                     -- degrees a second it turns
	Rock = 7, RockRate = 1.6,      -- degrees it tips, radians a second
	Near = 450,
	Glow = 160,
}
local BURST = { Time = 0.3, Swell = 0.45, Spin = 900, Rise = 2.5, Sparkles = 18 }
local POPIN = 0.4                  -- s a card takes to come back
local BODY = 2.5                   -- studs: a runner's middle over its feet
local ROPE_WIDTH = 0.55
local RETICLE = { Size = 44, Runner = Color3.fromRGB(255, 70, 70), Ground = Color3.fromRGB(255, 255, 255) }
local SOUND = { Min = 20, Max = 320 }
local PARK = CFrame.new(0, -60000, 0)

-- [ STATE ]--
local Started = false
local CourseName: string? = nil
local Cards: { any } = {}
local Taken: { [number]: number } = {}         -- card id -> server time it's back
local Asked: { [number]: number } = {}
local Look: { [number]: any } = {}
local Slots: { any } = {}                      -- the pool
local SlotOf: { [number]: any } = {}           -- card id -> its slot
local Folder: Folder? = nil
local Held: string? = nil
local Using: any = nil                         -- your grapple: { Kind, Id? }
local WasDown = false
local LastMe: Vector3? = nil
local Where: { [number]: Vector3 } = {}
local SpeedOf: { [number]: number } = {}       -- runner id -> its speed (studs/s)
local Ropes: { [number]: any } = {}            -- runner id -> its rope's look
local Reticle: Frame? = nil
local Target: any = nil
local Stats = { Cards = 0, Drawn = 0, Taken = 0, Ropes = 0 }

-- // PRIVATE //--

local function Library(name: string): Instance?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	node = node and node:FindFirstChild("Speed")
	node = node and node:FindFirstChild("Items")
	return node and node:FindFirstChild(name)
end

local function GetFolder(): Folder
	if Folder and Folder.Parent then return Folder end
	local f = Instance.new("Folder")
	f.Name = "SpeedItems"
	CollectionService:AddTag(f, "SpeedCameraIgnore")
	f.Parent = workspace
	Folder = f
	return f
end

local function Group(name: string): SoundGroup?
	local root = SoundService:FindFirstChild("SpeedSounds")
	local g = root and root:FindFirstChild(name)
	return if g and g:IsA("SoundGroup") then g else nil
end

local function PlayAt(name: string, at: Vector3, volume: number?)
	local kit = Library("Grapple")
	local template = kit and kit:FindFirstChild(name)
	if not (template and template:IsA("Sound")) then return end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = at
	anchor.Parent = workspace.Terrain
	local s = template:Clone()
	s.RollOffMode = Enum.RollOffMode.LinearSquare
	s.RollOffMinDistance, s.RollOffMaxDistance = SOUND.Min, SOUND.Max
	if volume then s.Volume = volume end
	s.SoundGroup = Group("Others")
	s.Parent = anchor
	s:Play()
	task.delay(math.max(s.TimeLength, 1) + 0.2, function() anchor:Destroy() end)
end

local function ServerNow(): number
	return workspace:GetServerTimeNow()
end

-- ── the course and its cards ──

local function SetCourse(name: string?)
	if name == CourseName then return end
	CourseName = name
	Cards, Taken, Asked, Look = {}, {}, {}, {}
	for id, slot in SlotOf do
		slot.Card = nil
		slot.Model:PivotTo(PARK)
	end
	table.clear(SlotOf)
	if not name then return end
	local world = workspace:FindFirstChild("World")
	local courses = world and world:FindFirstChild(SpeedConfig.Courses or "Courses")
	local course = courses and courses:FindFirstChild(name)
	if course and course:GetAttribute("Heightfield") == "Generated" then
		local ok, data = pcall(Generated.ForCourse, course)
		if ok and data then Cards = data.Cards or {} end
	end
end

local function NewSlot(): any?
	local template = Library("Card")
	if not template then return nil end
	local model = template:Clone()
	local pivot = model:GetPivot()
	local slot = { Model = model, Parts = {}, Rel = {}, Emitters = {}, Lights = {}, Glow = nil, Base = model:GetScale() }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(slot.Parts, d)
			table.insert(slot.Rel, pivot:ToObjectSpace(d.CFrame))
		elseif d:IsA("ParticleEmitter") then
			table.insert(slot.Emitters, d)
		elseif d:IsA("Light") then
			table.insert(slot.Lights, d)
		end
	end
	model:PivotTo(PARK)
	model.Parent = GetFolder()
	table.insert(Slots, slot)
	return slot
end

local function SetGlow(slot, on: boolean)
	if slot.Glow == on then return end
	slot.Glow = on
	for _, e in slot.Emitters do e.Enabled = on end
	for _, l in slot.Lights do l.Enabled = on end
end

local function Scale(slot, s: number)
	if slot.Scale == s then return end
	slot.Scale = s
	slot.Model:ScaleTo(slot.Base * math.max(s, 0.01))
end

local function Pose(card, clock: number): (CFrame, number)
	local id = card.Id
	local phase = id * 1.37
	local facing = card.Facing or Vector3.new(0, 0, -1)
	local yaw = math.atan2(-facing.X, -facing.Z)
	local bob = math.sin(clock * IDLE.BobRate + phase) * IDLE.Bob
	local spin = math.rad((clock * IDLE.Spin + phase * 57) % 360)
	local rock = math.rad(math.sin(clock * IDLE.RockRate + phase * 0.7) * IDLE.Rock)
	local size, lift = 1, 0
	local look = Look[id]
	if look and look.Burst then
		local t = math.clamp((clock - look.Burst) / BURST.Time, 0, 1)
		size = 1 + BURST.Swell * math.sin(math.pi * t) - t * 0.6
		spin += math.rad(BURST.Spin * t * BURST.Time)
		lift = BURST.Rise * t
	elseif look and look.Pop then
		local t = math.clamp((clock - look.Pop) / POPIN, 0, 1)
		local c1, c3 = 1.70158, 2.70158   -- (Back out)
		size = 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
	end
	local at = card.Position + Vector3.new(0, bob + lift, 0)
	return CFrame.new(at) * CFrame.Angles(0, yaw + spin, 0) * CFrame.Angles(rock, 0, 0), size
end

local function Burst(card, clock: number)
	Look[card.Id] = { Burst = clock, Gone = true }
	local slot = SlotOf[card.Id]
	if slot then
		for _, e in slot.Emitters do e:Emit(BURST.Sparkles) end
	end

	local camera = workspace.CurrentCamera
	local collect = Library("CardCollect")
	if collect and camera and (camera.CFrame.Position - card.Position).Magnitude < IDLE.Near then
		local copy = collect:Clone()
		copy.CFrame = CFrame.new(card.Position)
		copy.Parent = GetFolder()
		pcall(VFX.Emit, VFX, copy)
		task.delay(3, function() copy:Destroy() end)
	end
end

-- which cards are drawn, and how
local function StepCards(clock: number, camera: Vector3, parts, cframes)
	local now = ServerNow()
	local wanted, count = {}, 0
	Stats.Taken = 0
	for _, card in Cards do
		local id = card.Id
		local back = Taken[id]
		local look = Look[id]
		if back and now < back then
			Stats.Taken += 1
			if not (look and look.Gone) then
				Burst(card, clock)
				look = Look[id]
			end
		elseif look and look.Gone and not look.Pop then
			look.Pop, look.Gone, look.Burst = clock, false, nil   -- back: it pops in
			Taken[id] = nil
		end
		local showing = not (look and look.Gone) or (look and look.Burst and clock - look.Burst < BURST.Time)
		if showing then
			local d = (card.Position - camera).Magnitude
			if d <= CARDS.Draw then
				count += 1
				wanted[count] = { Card = card, D = d }
			end
		end
		if look and look.Pop and clock - look.Pop >= POPIN then Look[id] = nil end
	end
	if count > CARDS.Pool then
		table.sort(wanted, function(a, b) return a.D < b.D end)
		for i = count, CARDS.Pool + 1, -1 do wanted[i] = nil end
		count = CARDS.Pool
	end
	local keep = {}
	for i = 1, count do keep[wanted[i].Card.Id] = wanted[i] end
	-- free the slots no longer wanted
	for id, slot in SlotOf do
		if not keep[id] then
			slot.Card, slot.Still = nil, nil
			SlotOf[id] = nil
			Scale(slot, 1)
			SetGlow(slot, false)
			for _, p in slot.Parts do
				table.insert(parts, p)
				table.insert(cframes, PARK)
			end
		end
	end
	local free = {}
	for _, slot in Slots do
		if not slot.Card then table.insert(free, slot) end
	end
	for id, entry in keep do
		local slot = SlotOf[id]
		if not slot then
			slot = table.remove(free) or NewSlot()
			if not slot then continue end
			slot.Card, slot.Still = entry.Card, nil
			SlotOf[id] = slot
		end
		local card = entry.Card
		local look = Look[id]
		local animating = look and (look.Burst or look.Pop)
		SetGlow(slot, entry.D <= IDLE.Glow and not (look and look.Gone))
		if animating then

			local cf, size = Pose(card, clock)
			if look.Burst and clock - look.Burst >= BURST.Time then
				Scale(slot, 1)
				slot.Model:PivotTo(PARK)
			else
				Scale(slot, size)
				slot.Model:PivotTo(cf)
			end
			slot.Still = nil
		elseif entry.D <= IDLE.Near or not slot.Still then
			Scale(slot, 1)
			local cf = Pose(card, if entry.D <= IDLE.Near then clock else id)
			for i, p in slot.Parts do
				table.insert(parts, p)
				table.insert(cframes, cf * slot.Rel[i])
			end
			slot.Still = entry.D > IDLE.Near   -- (a far one is placed once and left)
		end
	end
	Stats.Cards, Stats.Drawn = #Cards, count
end

local function StepPickups(clock: number, me: Vector3)
	local from = LastMe or me
	LastMe = me
	if #Cards == 0 then return end
	local now = ServerNow()
	local path = me - from
	local len2 = path:Dot(path)
	for _, card in Cards do
		local id = card.Id
		if (Taken[id] and now < Taken[id]) or (Asked[id] and clock - Asked[id] < 1) then continue end
		local rel = card.Position - from
		if rel.Magnitude > path.Magnitude + CARDS.Reach + 20 then continue end
		local t = if len2 > 1e-6 then math.clamp(rel:Dot(path) / len2, 0, 1) else 0
		if (from + path * t - card.Position).Magnitude <= CARDS.Reach then
			Asked[id] = clock
			Taken[id] = now + CARDS.Respawn
			Burst(card, clock)
			Sounds:Play("Extra/Ui/PowerUp", 0.3)
			Backend:Request("card " .. id)
		end
	end
end

-- ── your item, the hands ──

local function KeyLabel(): string
	local action = ControlsConfig.Actions.UseItem
	return action and action.Labels and action.Labels.MouseKeyboard or "LMB"
end

local function ModelAt(path: string): Instance?
	local node: Instance? = nil
	for name in path:gmatch("[^/]+") do
		node = if node then node:FindFirstChild(name) else Library(name)
	end
	return node
end

local function ShowItem(name: string?)
	Held = name
	local show = name and ITEMS.Show and ITEMS.Show[name]
	if show then
		ItemHolder.SetItem({ Name = show.Icon or name, Display = show.Display, Key = KeyLabel(), Uses = 1, MaxUses = 1,
			Model = if show.Model then ModelAt(show.Model) else nil })
	else
		ItemHolder.Clear()
	end
end

local HandOf: { [number]: string } = {}
local Sips: { [number]: number } = {}
local HandSeen: { [number]: number } = {}
local Hands: { [number]: any } = {}
local Views: { [number]: any } = {}           -- runner id -> its drawn body (this frame)

local function DropHand(id: number)
	local hand = Hands[id]
	if hand then
		hand.Model:Destroy()
		Hands[id] = nil
	end
end

local function NewHand(name: string): any?
	local template = Library(name)
	if not (template and template:IsA("Model")) then return nil end
	local show
	for _, s in ITEMS.Show do
		if s.Hand == name then show = s end
	end
	local scale = if name == "Can" then 1 else (show and show.HandScale or 1)
	local model = template:Clone()
	if scale ~= 1 then model:ScaleTo(model:GetScale() * scale) end
	local pivot = model:GetPivot()
	local hand = { Name = name, Model = model, Parts = {}, Rel = {}, Scale = scale }
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(hand.Parts, p)
			table.insert(hand.Rel, pivot:ToObjectSpace(p.CFrame))
		end
	end
	local hold = template:GetAttribute("Hold") or CFrame.new()
	hand.Hold = CFrame.new(hold.Position * scale) * hold.Rotation
	local muzzle = template:GetAttribute("Muzzle")
	hand.Muzzle = if muzzle then muzzle * scale else nil
	hand.HookRef = model:FindFirstChild("hookRef")
	model.Parent = GetFolder()
	return hand
end

local function Grip(id: number): Attachment?
	local view = Views[id]
	local model = view and view.model
	local hand = model and model:FindFirstChild("RightHand")
	return hand and hand:FindFirstChild("RightGripAttachment") :: Attachment?
end

local function MuzzleOf(id: number, fallback: Vector3?): Vector3?
	local hand = Hands[id]
	if hand and hand.Muzzle and hand.Model.Parent then
		return hand.Model:GetPivot() * hand.Muzzle
	end
	return fallback
end

local function StepHands(clock: number, myId: number?)
	table.clear(Views)
	local need = false
	for _ in HandOf do need = true break end
	for _ in Sips do need = true break end
	if not need and next(Hands) == nil then return end
	Runners:EachCopy(function(id, _, view) Views[id] = view end)
	if myId then
		local body = Backend:GetBody()
		if body then Views[myId] = body end
	end
	local parts, cframes = {}, {}
	local want = {}
	for id, item in HandOf do
		local show = ITEMS.Show[item]
		if show and show.Hand then want[id] = show.Hand end
	end
	for id, untilClock in Sips do
		if clock < untilClock then want[id] = "Can" else Sips[id] = nil end
	end
	for id, hand in Hands do
		if want[id] ~= hand.Name then DropHand(id) end
	end
	for id in HandOf do
		if Where[id] then
			HandSeen[id] = clock
		elseif clock - (HandSeen[id] or clock) > 10 then
			HandOf[id], HandSeen[id] = nil, nil
		else
			HandSeen[id] = HandSeen[id] or clock
		end
	end
	for id, name in want do
		local grip = Grip(id)
		if not grip then
			if Hands[id] then DropHand(id) end
			continue
		end
		local hand = Hands[id] or NewHand(name)
		if not hand then continue end
		Hands[id] = hand
		local cf = grip.WorldCFrame * hand.Hold
		for i, p in hand.Parts do
			table.insert(parts, p)
			table.insert(cframes, cf * hand.Rel[i])
		end
	end
	if #parts > 0 then workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) end
end

local function LockOn(mv, camera: Camera, range: number, lock: number): number?
	local me = mv:GetPosition()
	local cf = camera.CFrame
	local best, bestAngle = nil, nil
	for id, at in Where do
		local d = (at - me).Magnitude
		if d > 8 and d <= range then
			local to = at + Vector3.new(0, BODY, 0) - cf.Position
			local angle = math.deg(math.acos(math.clamp(to.Unit:Dot(cf.LookVector), -1, 1)))
			if angle <= lock and (not bestAngle or angle < bestAngle) then best, bestAngle = id, angle end
		end
	end
	return best
end

local function Aim(mv, camera: Camera): any
	if Held == "Shotgun" then
		local id = LockOn(mv, camera, ITEMS.Shotgun.Range, ITEMS.Shotgun.Lock)
		return if id then { Kind = "runner", Id = id } else nil
	end
	local id = LockOn(mv, camera, G.RunnerRange or G.Range, G.Lock)
	if id then return { Kind = "runner", Id = id } end

	local me = mv:GetPosition()
	local cf = camera.CFrame
	local from = cf:PointToWorldSpace(Vector3.new(0, 14, 0))
	local to = cf:PointToWorldSpace(Vector3.new(0, 40, -(G.Range + (cf.Position - me).Magnitude)))
	local hit = workspace:Spherecast(from, G.Probe, to - from, mv.params)
	if hit and (hit.Position - me).Magnitude <= G.Range then return { Kind = "point", Point = hit.Position } end
	return nil
end

-- ── the ropes: elastic ──

local function DropRopeNow(rope)
	if rope.Reel then rope.Reel:Stop() end
	rope.A0:Destroy()
	rope.A1:Destroy()
	if rope.Hook then rope.Hook:Destroy() end
end

local function DropRope(id: number, hit: Vector3?)
	local rope = Ropes[id]
	if not rope or rope.Back then return end
	rope.Back = os.clock()
	rope.BackFrom = rope.HookAt
	if rope.Reel then rope.Reel:Stop() end
	if hit then
		local kit = Library("Grapple")
		local burst = kit and kit:FindFirstChild("PlayerHit")
		if burst then
			local copy = burst:Clone()
			copy.CFrame = CFrame.new(hit)
			copy.Parent = GetFolder()
			pcall(VFX.Emit, VFX, copy)
			task.delay(3, function() copy:Destroy() end)
		end
		PlayAt("Impact", hit, 0.6)
	end
end

local function NewRope(id: number, kind: string, to: any, untilTime: number?)
	local old = Ropes[id]
	if old then
		DropRopeNow(old)
		Ropes[id] = nil
	end
	local kit = Library("Grapple")
	if not kit then return end
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Name, a1.Name = "SpeedRopeFrom", "SpeedRopeTo"
	a0.Parent, a1.Parent = workspace.Terrain, workspace.Terrain
	local beam = (kit:FindFirstChild("Rope") :: Beam):Clone()
	beam.Width0, beam.Width1 = ROPE_WIDTH, ROPE_WIDTH
	beam.Segments = 24
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Parent = a0
	local hook = kit:FindFirstChild("Hook")
	hook = hook and hook:Clone()
	if hook then hook.Parent = GetFolder() end
	local reel = kit:FindFirstChild("Reel1")
	reel = reel and reel:Clone()
	if reel then
		reel.Looped = true
		reel.RollOffMode = Enum.RollOffMode.LinearSquare
		reel.RollOffMinDistance, reel.RollOffMaxDistance = SOUND.Min, SOUND.Max
		reel.SoundGroup = Group("Others")
		reel.Parent = a0
	end
	Ropes[id] = { Kind = kind, To = to, Until = untilTime, Born = os.clock(), A0 = a0, A1 = a1, Hook = hook, Reel = reel,
		Landed = false, Side = if math.random() < 0.5 then -1 else 1 }
	local from = MuzzleOf(id, Where[id] and Where[id] + Vector3.new(0, BODY, 0))
	if from then PlayAt("Fire", from, 0.6) end
end

local function StepRopes(clock: number, myId: number?, me: Vector3?)
	local now = ServerNow()
	local parts, cframes = {}, {}
	Stats.Ropes = 0
	for id, rope in Ropes do
		local body = if id == myId then me else Where[id]
		local from = MuzzleOf(id, body and body + Vector3.new(0, BODY, 0))
		local to = if rope.Kind == "runner" then Where[rope.To] else rope.To
		if rope.Kind == "runner" and to then to += Vector3.new(0, BODY, 0) end
		local hand = Hands[id]
		if hand and hand.HookRef then hand.HookRef.Transparency = 1 end   -- (its hook's out)
		if not from then
			DropRopeNow(rope)
			Ropes[id] = nil
			continue
		end
		if not rope.Back and (not to or (rope.Until and now > rope.Until)) then
			DropRope(id, if rope.Kind == "runner" and to then to else nil)
		end
		local hookAt, whip
		if rope.Back then
			-- snapping back to the gun, wobbling
			local t = math.clamp((clock - rope.Back) / 0.16, 0, 1)
			hookAt = (rope.BackFrom or from):Lerp(from, t * t)
			whip = G.Whip * 0.6 * (1 - t) * math.sin(t * math.pi * 3)
			if t >= 1 then
				DropRopeNow(rope)
				Ropes[id] = nil
				if hand and hand.HookRef then hand.HookRef.Transparency = 0 end
				continue
			end
		else
			Stats.Ropes += 1
			local age = clock - rope.Born
			local reach = (to - from).Magnitude
			local way = if reach > 1e-3 then (to - from) / reach else Vector3.zAxis
			local f
			if age < G.Fly then
				local u = age / G.Fly
				f = (1 - (1 - u) * (1 - u)) * (1 + G.Overshoot)   -- (out fast, past the spot)
			else
				local tau = age - G.Fly
				f = 1 + G.Overshoot * math.exp(-G.Damp * tau) * math.cos(G.Spring * tau)   -- (springs back to it)
				if not rope.Landed then
					rope.Landed = true
					if rope.Kind == "point" then PlayAt("Impact", to, 0.45) end
					if rope.Reel then rope.Reel:Play() end
				end
			end
			hookAt = from + way * reach * f

			whip = G.Whip * math.exp(-G.WhipDamp * age) * math.sin(G.WhipRate * age) + 0.25 * math.sin(age * 60)
		end
		rope.HookAt = hookAt
		local look = hookAt - from
		local frame = if look.Magnitude > 1e-3 then CFrame.lookAt(from, hookAt) else CFrame.new(from)
		rope.A0.WorldCFrame = frame
		rope.A1.WorldCFrame = frame.Rotation + hookAt
		local beam = rope.A0:FindFirstChildOfClass("Beam")
		if beam then
			beam.CurveSize0 = whip * rope.Side
			beam.CurveSize1 = whip * rope.Side
		end
		if rope.Hook then
			table.insert(parts, rope.Hook)
			table.insert(cframes, CFrame.lookAt(hookAt, hookAt + (if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis)))
		end
	end
	if #parts > 0 then workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) end
end

local Gators: { [number]: any } = {}
local Auras: { [number]: any } = {}

local function Kit(name: string, child: string): Instance?
	local kit = Library(name)
	return kit and kit:FindFirstChild(child)
end

local function NewGator(gid: number, from: number, to: number?, myId: number?, me: Vector3?)
	local template = Library("Gator")
	local start = if from == myId then me else Where[from]
	if not (template and start) then return end
	local GA = ITEMS.Gator
	local model = template:Clone()
	model:ScaleTo(model:GetScale() * GA.ThrownScale)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Trail") then d.Enabled = true end
	end
	model.Parent = GetFolder()
	local aim = if to and Where[to] then Where[to] else nil
	local way = if aim then (aim - start).Unit else Vector3.new(0, 0, -1)
	if way ~= way then way = Vector3.new(0, 0, -1) end
	Gators[gid] = { Model = model, To = to, Position = start + Vector3.new(0, GA.Hover, 0) + way * 8,
		Velocity = way * GA.MinSpeed, Born = os.clock() }
	PlayAt("Fire", start + Vector3.new(0, BODY, 0), 0.4)
end

local function EndGator(gid: number, hit: Vector3?)
	local g = Gators[gid]
	if not g then return end
	Gators[gid] = nil
	g.Model:Destroy()
	if hit then
		local burst = Kit("GatorKit", "GatorImpact")
		if burst then
			local copy = burst:Clone()
			copy.CFrame = CFrame.new(hit)
			copy.Parent = GetFolder()
			pcall(VFX.Emit, VFX, copy)
			task.delay(3, function() copy:Destroy() end)
		end
		PlayAt("Impact", hit, 0.7)
	end
end

local function StepGators(dt: number)
	if next(Gators) == nil then return end
	local GA = ITEMS.Gator
	for gid, g in Gators do
		if os.clock() - g.Born > GA.Life + 1 then
			EndGator(gid)
			continue
		end
		local target = g.To and Where[g.To]
		if target then
			local to = target + Vector3.new(0, GA.Hover, 0) - g.Position
			local speed = math.max(GA.MinSpeed, (SpeedOf[g.To] or 0) * GA.Speed)   -- (as the server flies it)
			local dist = to.Magnitude
			if dist < (GA.Commit or 60) then
				g.Velocity = to.Unit * speed
			else
				local turn = GA.Turn * (1 + 4 * math.clamp(1 - dist / 300, 0, 1))
				g.Velocity = g.Velocity:Lerp(to.Unit * math.max(speed, g.Velocity.Magnitude), math.min(dt * turn, 1))
			end
		end
		g.Position += g.Velocity * dt
		if g.Velocity.Magnitude > 1e-3 then
			g.Model:PivotTo(CFrame.lookAt(g.Position, g.Position + g.Velocity))
		end
	end
end

local function Shot(from: number, to: number, keep: number, myId: number?, me: Vector3?)
	local SG = ITEMS.Shotgun
	local body = if from == myId then me else Where[from]
	local origin = MuzzleOf(from, body and body + Vector3.new(0, BODY, 0))
	local target = Where[to]
	if not (origin and target) then return end
	target += Vector3.new(0, BODY, 0)
	local flash = Kit("ShotgunKit", "MuzzleShot")
	if flash then
		local copy = flash:Clone()
		copy.CFrame = CFrame.lookAt(origin, target)
		copy.Parent = GetFolder()
		pcall(VFX.Emit, VFX, copy)
		task.delay(2, function() copy:Destroy() end)
	end
	local blast = Kit("ShotgunKit", "Blast")
	if blast then
		local anchor = Instance.new("Attachment")
		anchor.WorldPosition = origin
		anchor.Parent = workspace.Terrain
		local s = blast:Clone()
		s.RollOffMode = Enum.RollOffMode.LinearSquare
		s.RollOffMinDistance, s.RollOffMaxDistance = SOUND.Min, SOUND.Max
		s.SoundGroup = Group("Others")
		s.Parent = anchor
		s:Play()
		task.delay(3, function() anchor:Destroy() end)
	end

	local pellet = Kit("ShotgunKit", "Pellet")
	if pellet then
		local reach = (target - origin).Magnitude
		local base = CFrame.lookAt(origin, target)
		local flight = math.clamp(reach / SG.Speed, 0.05, 0.3)
		for i = 1, SG.Pellets do
			local spin = math.random() * math.pi * 2
			local off = math.sqrt(math.random()) * math.rad(SG.Spread)
			local dir = (base * CFrame.Angles(0, 0, spin) * CFrame.Angles(off, 0, 0)).LookVector
			local copy = pellet:Clone()
			copy.CFrame = CFrame.new(origin)
			copy.Parent = GetFolder()
			local tween = TweenService:Create(copy, TweenInfo.new(flight, Enum.EasingStyle.Linear), { CFrame = CFrame.new(origin + dir * reach) })
			tween:Play()
			task.delay(flight + 0.4, function() copy:Destroy() end)
		end
		if keep < 1 then
			task.delay(flight, function()
				local burst = Kit("Grapple", "PlayerHit")
				local at = Where[to]
				if burst and at then
					local copy = burst:Clone()
					copy.CFrame = CFrame.new(at + Vector3.new(0, BODY, 0))
					copy.Parent = GetFolder()
					pcall(VFX.Emit, VFX, copy)
					task.delay(3, function() copy:Destroy() end)
				end
			end)
		end
	end
end

local function NewAura(id: number, untilTime: number)
	local old = Auras[id]
	if old then old.Part:Destroy() end
	local template = Kit("DrinkKit", "Aura")
	if not template then return end
	local part = template:Clone()
	local emitters = {}
	for _, e in part:GetDescendants() do
		if e:IsA("ParticleEmitter") then table.insert(emitters, e) end
	end
	part.Parent = GetFolder()
	pcall(VFX.Emit, VFX, part)
	for _, e in emitters do e.Enabled = true end
	local loop = Kit("DrinkKit", "Loop")
	if loop then
		loop = loop:Clone()
		loop.Looped = true
		loop.RollOffMode = Enum.RollOffMode.LinearSquare
		loop.RollOffMinDistance, loop.RollOffMaxDistance = SOUND.Min, SOUND.Max
		loop.SoundGroup = Group("Others")
		loop.Parent = part
		loop:Play()
	end
	Auras[id] = { Part = part, Emitters = emitters, Until = untilTime }
	Sips[id] = os.clock() + ITEMS.Drink.Sip
end

local function StepAuras(myId: number?, me: Vector3?)
	if next(Auras) == nil then return end
	local now = ServerNow()
	local parts, cframes = {}, {}
	for id, aura in Auras do
		local at = if id == myId then me else Where[id]
		if now > aura.Until or not at then
			Auras[id] = nil
			for _, e in aura.Emitters do e.Enabled = false end
			local loop = aura.Part:FindFirstChildOfClass("Sound")
			if loop then loop:Stop() end
			task.delay(1.5, function() aura.Part:Destroy() end)
			continue
		end
		table.insert(parts, aura.Part)
		table.insert(cframes, CFrame.new(at + Vector3.new(0, BODY, 0)))   -- (it follows them)
	end
	if #parts > 0 then workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) end
end

local InkGui: Frame? = nil
local function Inked()
	local I = ITEMS.Ink
	local gui = Player:FindFirstChild("PlayerGui")
	if not gui then return end
	if not (InkGui and InkGui.Parent) then
		local screen = Instance.new("ScreenGui")
		screen.Name = "SpeedInk"
		screen.IgnoreGuiInset = true
		screen.ResetOnSpawn = false
		screen.DisplayOrder = -1
		local frame = Instance.new("Frame")
		frame.Name = "Ink"
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = screen
		screen.Parent = gui
		InkGui = frame
	end
	local splash = Kit("InkKit", "Splash")
	if splash then
		local s = splash:Clone()
		s.SoundGroup = Group("Ui")
		s.Parent = InkGui
		s:Play()
		task.delay(math.max(s.TimeLength, 1) + 0.2, function() s:Destroy() end)
	end
	local frame = InkGui
	task.spawn(function()
		local splats = {}
		for i = 1, I.Count do
			local splat = Instance.new("ImageLabel")
			splat.Image = I.Image
			splat.BackgroundTransparency = 1
			splat.AnchorPoint = Vector2.new(0.5, 0.5)
			splat.Position = UDim2.fromScale(0.17 + math.random() * 0.68, 0.17 + math.random() * 0.61)
			splat.Size = UDim2.fromScale(0, 0)
			splat.Rotation = math.random(-25, 25)
			splat.Parent = frame
			TweenService:Create(splat, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Size = I.Size }):Play()
			table.insert(splats, splat)
			task.wait(I.Every)
		end
		task.wait(I.Hold)
		for _, splat in splats do
			TweenService:Create(splat, TweenInfo.new(I.Fade, Enum.EasingStyle.Quad), { ImageTransparency = 1 }):Play()
			task.delay(I.Fade + 0.05, function() splat:Destroy() end)
			task.wait(I.FadeEvery)
		end
	end)
end

-- ── using it ──

local LastLock: string? = nil
local AutoSince: number? = nil
local AutoWait: number? = nil
local function StepUse(clock: number, mv, camera: Camera, myId: number?)
	local down = Backend:IsHeld("UseItem")
	local pressed = down and not WasDown
	WasDown = down

	local auto = Backend:IsAuto()
	if auto and Held and not Using then
		local wait = SpeedConfig.Race.Autoplay and SpeedConfig.Race.Autoplay.UseAfter or { 1.2, 3 }
		AutoSince = AutoSince or clock
		AutoWait = AutoWait or (wait[1] + math.random() * (wait[2] - wait[1]))
		if clock - AutoSince >= AutoWait then
			local lock = Held == "Grapple" or Held == "Shotgun"
			if not lock or (Target and (Target.Kind == "runner" or clock - AutoSince > 6)) then pressed = true end
		end
	elseif not Held then
		AutoSince, AutoWait = nil, nil
	end
	-- your grapple running
	if Using then
		local held = down or (auto and clock - (Using.Since or 0) < 0.9)   -- (autoplay holds a ground hook a moment)
		if Using.Kind == "point" and (not held or not mv:IsGrappling()) then
			mv:GrappleRelease()
			Backend:Request("grapple off")
			if myId then DropRope(myId) end
			Using = nil
		elseif Using.Kind == "runner" and not mv:IsGrappling() then
			Using = nil
		end
	end
	-- the lock (grapple / shotgun)
	local aiming = (Held == "Grapple" or Held == "Shotgun") and not Using and not GUIController.HudHidden()
	Target = if aiming then Aim(mv, camera) else nil

	local at = if Target then (if Target.Kind == "runner" then (Where[Target.Id] or Vector3.zero) + Vector3.new(0, BODY, 0) else Target.Point) else nil
	local p, onScreen = nil, false
	if at then p, onScreen = camera:WorldToViewportPoint(at) end
	local lock = if Target then (Target.Kind .. tostring(Target.Id)) else nil
	if at and onScreen then
		ReticleUI.Set(Target.Kind, Vector2.new(p.X, p.Y), KeyLabel())
		if lock ~= LastLock and LastLock ~= nil and Target.Kind == "runner" then ReticleUI.Lock() end
	elseif aiming then
		ReticleUI.Set("search", camera.ViewportSize / 2, KeyLabel())
	else
		ReticleUI.Set(nil)
	end
	LastLock = lock
	if not (pressed and Held) or GUIController.HudHidden() then return end
	local used = true
	local item = Held
	if item == "Grapple" then
		if not Target then return end
		local target = Target
		if mv.camera then mv.camera:AddFovImpulse(G.Kick) end
		if target.Kind == "runner" then
			local id = target.Id
			mv:Grapple(function() return Where[id] end)
			Backend:Request("grapple runner " .. id)
			Using = { Kind = "runner", Id = id, Since = clock }
			if myId then NewRope(myId, "runner", id, ServerNow() + G.Pull) end
		else
			local p = target.Point
			mv:Grapple(p)
			Backend:Request(("grapple point %.1f %.1f %.1f"):format(p.X, p.Y, p.Z))
			Using = { Kind = "point", Since = clock }
			if myId then NewRope(myId, "point", p, nil) end
		end
	elseif item == "Shotgun" then
		if not (Target and Target.Kind == "runner") then return end
		Backend:Request("use shotgun " .. Target.Id)
		if myId then Shot(myId, Target.Id, 0.5, myId, mv:GetPosition()) end
		mv:shake(8, 0.2)
	elseif item == "Drink" then
		mv:Boost(ITEMS.Drink.Boost, ITEMS.Drink.Seconds)
		Backend:Request("use drink")
	elseif item == "Ink" then
		Backend:Request("use ink")
	elseif item == "Gator" then
		Backend:Request("use gator")
	else
		used = false
	end
	if used then
		Held = nil
		ItemHolder.Used()
		task.delay(0.35, function()
			if not Held then ItemHolder.Clear() end
		end)
	end
end

local LastClock = os.clock()
local function Step(clock: number?)
	clock = clock or os.clock()
	local dt = math.clamp(clock - LastClock, 0, 0.1)
	LastClock = clock
	local mv = Backend:GetMovement()
	local camera = workspace.CurrentCamera
	if not (mv and camera and CARDS and G) then return end
	SetCourse(mv.courseName)
	table.clear(Where)
	table.clear(SpeedOf)
	for _, runner in Runners:List() do
		Where[runner.Id] = runner.Position
		SpeedOf[runner.Id] = runner.Speed
	end
	local myId = Player:GetAttribute("SpeedId")
	myId = if type(myId) == "number" then myId else nil
	if myId then
		Where[myId] = mv:GetPosition()
		SpeedOf[myId] = mv:GetSpeed()
	end
	local me = mv:GetPosition()
	local parts, cframes = {}, {}
	StepCards(clock, camera.CFrame.Position, parts, cframes)
	if #parts > 0 then workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) end
	StepPickups(clock, me + Vector3.new(0, BODY, 0))
	StepHands(clock, myId)
	StepUse(clock, mv, camera, myId)
	StepRopes(clock, myId, me)
	StepGators(dt)
	StepAuras(myId, me)
end

local function Hooked(mv)
	mv.GrappleEvent.Event:Connect(function(what: string)
		local myId = Player:GetAttribute("SpeedId")
		if type(myId) ~= "number" then return end
		if what == "Slingshot" then
			DropRope(myId, mv:GetPosition() + Vector3.new(0, BODY, 0))
			Sounds:Play("Extra/Ui/PowerUp", 0.35)
		elseif what == "Release" and Using and Using.Kind == "runner" then
			DropRope(myId)
		end
	end)
end

-- // PUBLIC //--

function Items:Command(value: string)
	local words = string.split(value, " ")
	local what = words[1]
	local myId = Player:GetAttribute("SpeedId")
	local mv = Backend:GetMovement()
	if what == "card" then
		local id, back = tonumber(words[2]), tonumber(words[3])
		if id and back then Taken[id] = back end
	elseif what == "got" then
		ShowItem(words[2])
		Sounds:Play("Extra/Ui/Chime", 0.3)
	elseif what == "spent" then
		if Held then ShowItem(nil) end
	elseif what == "hand" then
		local id = tonumber(words[2])
		if id then HandOf[id] = if words[3] and words[3] ~= "none" then words[3] else nil end
	elseif what == "reset" then
		Taken, Asked = {}, {}
		ShowItem(nil)
		table.clear(HandOf)
		for id, rope in Ropes do DropRopeNow(rope) end
		table.clear(Ropes)
		for gid in Gators do EndGator(gid) end
	elseif what == "rope" then
		local from = tonumber(words[2])
		if not from or from == myId then return end   -- (yours is drawn as you fire it)
		if words[3] == "off" then
			DropRope(from)
		elseif words[3] == "runner" then
			NewRope(from, "runner", tonumber(words[4]), tonumber(words[5]))
		elseif words[3] == "point" then
			NewRope(from, "point", Vector3.new(tonumber(words[4]) or 0, tonumber(words[5]) or 0, tonumber(words[6]) or 0), tonumber(words[7]))
		end
	elseif what == "yank" then
		local from, seconds = tonumber(words[2]), tonumber(words[3])
		if mv and from then
			mv:Yank(function() return Where[from] end, seconds)
			PlayAt("Impact", mv:GetPosition() + Vector3.new(0, BODY, 0), 0.6)
		end
	elseif what == "slow" then
		local keep = tonumber(words[2])
		if mv and keep then mv:Slow(keep) end
	elseif what == "fx" then
		if words[2] == "drink" then
			local id, untilTime = tonumber(words[3]), tonumber(words[4])
			if id and untilTime then NewAura(id, untilTime) end
		elseif words[2] == "shot" then
			local from, to, keep = tonumber(words[3]), tonumber(words[4]), tonumber(words[5])
			if from and to and from ~= myId then Shot(from, to, keep or 1, myId, mv and mv:GetPosition()) end
		end
	elseif what == "ink" then
		local from = tonumber(words[2])
		if from ~= myId then Inked() end
	elseif what == "gator" then
		local gid, from, to = tonumber(words[2]), tonumber(words[3]), tonumber(words[4])
		if gid and from then NewGator(gid, from, if to and to ~= 0 then to else nil, if type(myId) == "number" then myId else nil, mv and mv:GetPosition()) end
	elseif what == "gatorhit" then
		local gid, to = tonumber(words[2]), tonumber(words[3])
		local at = to and (if to == myId and mv then mv:GetPosition() else Where[to])
		if gid then EndGator(gid, at and at + Vector3.new(0, BODY, 0)) end
	elseif what == "gatorend" then
		local gid = tonumber(words[2])
		if gid then EndGator(gid) end
	end
end

function Items:Stats()
	local stats = table.clone(Stats)
	stats.Item = Held
	local n = 0
	for _ in Hands do n += 1 end
	stats.Hands = n
	n = 0
	for _ in Gators do n += 1 end
	stats.Gators = n
	return stats
end

function Items:Step(clock: number?)
	Step(clock)
end

function Items:Init()
	if Started or not (CARDS and G) then return end
	Started = true
	task.spawn(function()
		local mv = Backend:GetMovement()
		while not mv do
			task.wait(0.2)
			mv = Backend:GetMovement()
		end
		Hooked(mv)
		RunService:BindToRenderStep("SpeedItems", Enum.RenderPriority.Camera.Value + 5, function() Step() end)
	end)
end

return Items
