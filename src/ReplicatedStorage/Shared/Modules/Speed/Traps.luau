local SpeedConfig = require(script.Parent.Parent.Configs.SpeedConfig)

local Traps = {}

local TAU = math.pi * 2
local BURN = 0.95
local CAGE = SpeedConfig.Map.Traps.Cage
local CAGE_SIZE = 133.43

local CageNodes: { Vector3 } = {}
local CageBars: { { number } } = {}
do
	local phase = math.rad(CAGE.Phase or -18)
	local y, r = 1 / math.sqrt(5), 2 / math.sqrt(5)
	local verts = { Vector3.new(0, 1, 0) }
	for k = 0, 4 do
		local a = phase + math.rad(72 * k)
		table.insert(verts, Vector3.new(math.sin(a) * r, y, math.cos(a) * r))
	end
	for k = 0, 4 do
		local a = phase + math.rad(36 + 72 * k)
		table.insert(verts, Vector3.new(math.sin(a) * r, -y, math.cos(a) * r))
	end
	table.insert(verts, Vector3.new(0, -1, 0))
	local shortest = math.huge
	for i = 1, 12 do for j = i + 1, 12 do shortest = math.min(shortest, (verts[i] - verts[j]).Magnitude) end end
	local joined = {}
	for i = 1, 12 do for j = i + 1, 12 do
		if (verts[i] - verts[j]).Magnitude < shortest * 1.01 then joined[i * 100 + j], joined[j * 100 + i] = true, true end
	end end
	CageNodes = table.clone(verts)
	local middles = {}
	local function Middle(i: number, j: number): number
		local key = math.min(i, j) * 100 + math.max(i, j)
		if not middles[key] then
			table.insert(CageNodes, (verts[i] + verts[j]).Unit)
			middles[key] = #CageNodes
		end
		return middles[key]
	end
	local seen = {}
	local function Bar(i: number, j: number)
		local key = math.min(i, j) * 100 + math.max(i, j)
		if not seen[key] then
			seen[key] = true
			table.insert(CageBars, { i, j })
		end
	end
	for i = 1, 12 do for j = i + 1, 12 do for k = j + 1, 12 do
		if joined[i * 100 + j] and joined[j * 100 + k] and joined[i * 100 + k] then
			local ij, jk, ki = Middle(i, j), Middle(j, k), Middle(k, i)
			Bar(i, ij) Bar(ij, j) Bar(j, jk) Bar(jk, k) Bar(k, ki) Bar(ki, i) Bar(ij, jk) Bar(jk, ki) Bar(ki, ij)
		end
	end end end
end

function Traps.Clock(): number
	return workspace:GetServerTimeNow()
end

function Traps.Turn(trap, t: number): number
	return (trap.Phase + trap.Omega * t) % TAU
end

function Traps.Nozzle(trap, t: number): Vector3
	local phase = trap.SwayPhase or trap.Phase
	local a = (phase + trap.SwayRate * t) % TAU
	local b = (phase * 1.7 + trap.SurgeRate * t) % TAU
	return trap.Base + trap.Right * (math.sin(a) * trap.Sway) + trap.Axis * (math.sin(b) * trap.Surge)
end

function Traps.Beam(trap, t: number): (Vector3?, number)
	local cycle = trap.Fire + trap.Rest
	local at = t + trap.Phase
	local into = at - math.floor(at / cycle) * cycle
	if into >= trap.Fire then return nil, 0 end
	local size = math.clamp(math.min(into, trap.Fire - into), 0, 1)
	local az = (trap.Phase * 2.3 + trap.AzRate * t) % TAU
	local tilt = trap.Tilt[1] + (trap.Tilt[2] - trap.Tilt[1]) * (0.5 + 0.5 * math.sin((trap.Phase + 0.9 * t) % TAU))
	local s = math.sin(tilt)
	return Vector3.new(math.cos(az) * s, -math.cos(tilt), math.sin(az) * s), size
end

function Traps.Tumble(trap, t: number): CFrame
	local w = trap.Tumble
	return CFrame.fromEulerAnglesXYZ((trap.Phase + w.X * t) % TAU, (trap.Phase * 0.7 + w.Y * t) % TAU, (trap.Phase * 1.3 + w.Z * t) % TAU)
end

local TWO32 = 4294967296
local function Hash(a: number, b: number, c: number): number
	local h = ((a % 65536) * 31337 + (b % 1048576) * 7919 + c * 104729) % TWO32
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = (h * 1597333) % TWO32
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1103231) % TWO32
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / TWO32
end

function Traps.Shot(trap, n: number, i: number): (number, Vector3, Vector3)
	local launch = n * trap.Interval + trap.Offset + (i - 1) * trap.Stagger
	local rows = trap.Rows
	local row = rows[math.floor(Hash(trap.Id, n, 1) * #rows) + 1]
	local clear = math.floor(Hash(trap.Id, n, 2) * trap.Lanes) + 1
	local lane = if i < clear then i else i + 1
	local to = row.Points[lane] or row.Points[#row.Points]
	local turn = (trap.Phase + trap.Omega * launch) % TAU
	return launch, trap.Foot + CFrame.Angles(0, turn, 0):VectorToWorldSpace(trap.Tubes[i]), to
end

function Traps.Flight(trap, from: Vector3, to: Vector3, u: number): (Vector3, Vector3)

	local mid = Vector3.new(from.X + (to.X - from.X) * 0.15, math.max(from.Y, to.Y) + trap.Arc, from.Z + (to.Z - from.Z) * 0.15)
	local e = math.clamp(u, 0, 1) ^ 1.25
	local a = 1 - e
	return from * (a * a) + mid * (2 * a * e) + to * (e * e), (mid - from) * a + (to - mid) * e
end

function Traps.EachShot(trap, t: number, fn: (number, number, number, Vector3, Vector3) -> ())
	local tubes = #trap.Tubes
	local life = trap.Flight + trap.Blast + 0.5
	local last = math.floor((t - trap.Offset) / trap.Interval)
	local first = math.floor((t - trap.Offset - life - trap.Stagger * tubes) / trap.Interval)
	for n = math.max(first, last - 6), last do
		for i = 1, tubes do
			local launch = n * trap.Interval + trap.Offset + (i - 1) * trap.Stagger
			if t >= launch and t <= launch + life then
				local _, from, to = Traps.Shot(trap, n, i)
				fn(n, i, launch, from, to)
			end
		end
	end
end

local function SegSeg(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3): number
	local d1, d2, r = p1 - p0, q1 - q0, p0 - q0
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	local s, t
	if a <= 1e-9 and e <= 1e-9 then return r.Magnitude end
	if a <= 1e-9 then
		s, t = 0, math.clamp(f / e, 0, 1)
	else
		local c = d1:Dot(r)
		if e <= 1e-9 then
			t, s = 0, math.clamp(-c / a, 0, 1)
		else
			local b = d1:Dot(d2)
			local denom = a * e - b * b
			s = if denom > 1e-9 then math.clamp((b * f - c * e) / denom, 0, 1) else 0
			t = (b * s + f) / e
			if t < 0 then
				t, s = 0, math.clamp(-c / a, 0, 1)
			elseif t > 1 then
				t, s = 1, math.clamp((b - c) / a, 0, 1)
			end
		end
	end
	return ((p0 + d1 * s) - (q0 + d2 * t)).Magnitude
end

function Traps.Touches(trap, a: Vector3, b: Vector3, t: number): boolean
	local kind = trap.Kind
	if kind == "Spinner" then
		local hub = trap.Hub

		local da, db = (a - hub):Dot(trap.Axis), (b - hub):Dot(trap.Axis)
		local r = trap.Radius
		if (da > r and db > r) or (da < -r and db < -r) then return false end
		if (a - hub).Magnitude > trap.Arm + r + (b - a).Magnitude then return false end
		local turn = Traps.Turn(trap, t)
		local right, up = trap.Right, trap.Up
		for _, spoke in trap.Spokes do
			local ang = spoke + turn
			local tip = hub + (right * math.cos(ang) + up * math.sin(ang)) * trap.Arm
			if SegSeg(a, b, hub, tip) < r then return true end
		end
		return false
	elseif kind == "Cage" then

		local centre, size = trap.Centre, trap.R / CAGE_SIZE   -- units per stud of the full-size model
		local nodes = CAGE.Nodes * size
		local reach = CAGE.Laser * size + CAGE.Body / SpeedConfig.Studs

		local pa, pb = a - centre, b - centre
		local d = pb - pa
		local s = if d:Dot(d) > 1e-9 then math.clamp(-pa:Dot(d) / d:Dot(d), 0, 1) else 0
		if (pa + d * s).Magnitude > nodes + reach then return false end
		if math.max(pa.Magnitude, pb.Magnitude) < nodes * 0.95 - reach then return false end
		local turn = Traps.Tumble(trap, t)
		local la, lb = turn:VectorToObjectSpace(pa), turn:VectorToObjectSpace(pb)
		for _, bar in CageBars do
			if SegSeg(la, lb, CageNodes[bar[1]] * nodes, CageNodes[bar[2]] * nodes) < reach then return true end
		end
		return false
	elseif kind == "Missile" then

		if (a - trap.Foot).Magnitude > trap.Reach + (b - a).Magnitude then return false end
		local last = math.floor((t - trap.Offset - trap.Flight) / trap.Interval)
		for n = last - 1, last do
			for i = 1, #trap.Tubes do
				local into = t - (n * trap.Interval + trap.Offset + (i - 1) * trap.Stagger) - trap.Flight
				if into >= 0 and into <= trap.Blast then
					local _, _, to = Traps.Shot(trap, n, i)
					if SegSeg(a, b, to, to) < trap.Radius then return true end
				end
			end
		end
		return false
	elseif kind == "Lava" then
		local dir, size = Traps.Beam(trap, t)
		if not dir or size < BURN then return false end
		local from = Traps.Nozzle(trap, t)
		local reach = trap.Drop / math.max(-dir.Y, 0.2) * 1.3   -- past the ground: nothing's under it
		return SegSeg(a, b, from, from + dir * reach) < trap.Radius
	end
	return false
end

Traps.CageNodes, Traps.CageBars = CageNodes, CageBars

return Traps
