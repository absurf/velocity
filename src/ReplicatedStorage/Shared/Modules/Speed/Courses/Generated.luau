local Config = require(script.Parent.Parent.Parent.Configs.SpeedConfig)

local Generated = {}

local S = Config.Studs
local LINE_STEP = 20
local FINE_STEP = 4
local TRIES, CHAINS = 100, 200
local NOISE_Z = 0.37

local START = { Name = "Start", EndYaw = 0.9, Knots = { Vector3.new(0, 0, 0), Vector3.new(4, 0, 248) } }   -- Speed StartSplineKey
local PIECES = {
	{ Name = "Turn", EndYaw = 85.6, Knots = {   -- Speed SP_2: a sweeping right turn
		Vector3.new(0, 0, 0), Vector3.new(-1, 0, 182), Vector3.new(102, 0, 398), Vector3.new(314, 0, 514), Vector3.new(536, 0, 531) } },
	{ Name = "Wiggle", EndYaw = -12.7, Knots = {   -- Speed SP_8: an S, mostly straight
		Vector3.new(0, 0, 0), Vector3.new(8.7, 0, 138.1), Vector3.new(-16.4, 0, 292.8), Vector3.new(37.4, 0, 492.2), Vector3.new(3.2, 0, 643.4) } },
	{ Name = "Long", EndYaw = 0.4, Knots = { Vector3.new(0, 0, 0), Vector3.new(4, 0, 546) } },    -- Speed SP_5
	{ Name = "Short", EndYaw = 0.9, Knots = { Vector3.new(0, 0, 0), Vector3.new(4, 0, 248) } },   -- Speed SP_4
}

local Cache: { [any]: any } = {}
local CacheOrder: { any } = {}
local Building: { [any]: boolean } = {}
local PlaceProps, Mounds, SetPieces, PlaceTraps, PlaceCards

-- // THE LINE //--

local function Place(piece, mirror: number, at: Vector3, yaw: number): { Vector3 }
	local c, s = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
	local out = {}
	for i, k in piece.Knots do
		local x = k.X * mirror
		out[i] = at + Vector3.new(x * c + k.Z * s, k.Y, -x * s + k.Z * c)
	end
	return out
end

local function Along(knots: { Vector3 }, step: number): { Vector3 }
	local total = 0
	for i = 2, #knots do total += (knots[i] - knots[i - 1]).Magnitude end
	local n = math.max(math.round(total / step), 2)
	local out, i, walked = {}, 2, 0
	for j = 0, n - 1 do
		local want = total * j / (n - 1)
		while i < #knots and walked + (knots[i] - knots[i - 1]).Magnitude < want do
			walked += (knots[i] - knots[i - 1]).Magnitude
			i += 1
		end
		local a, b = knots[i - 1], knots[i]
		local len = (b - a).Magnitude
		out[j + 1] = if len > 1e-6 then a:Lerp(b, math.clamp((want - walked) / len, 0, 1)) else a
	end
	return out
end

local function Sampled(knots: { Vector3 }, from: number): { { P: Vector3, A: number } }
	local points = Along(knots, 50)
	local out, a = {}, from
	for i, p in points do
		if i > 1 then a += (p - points[i - 1]).Magnitude end
		out[i] = { P = p, A = a }
	end
	return out
end

local function Clear(candidate, placed, gap: number, around: number): boolean
	local gap2 = gap * gap
	for _, piece in placed do
		for _, a in piece.Samples do
			for _, b in candidate do
				if b.A - a.A > around then
					local dx, dz = a.P.X - b.P.X, a.P.Z - b.P.Z
					if dx * dx + dz * dz < gap2 then return false end
				end
			end
		end
	end
	return true
end

local function Chain(rng: Random, count: number, gap: number, around: number)
	local best = nil
	for _ = 1, CHAINS do
		local first = Place(START, 1, Vector3.zero, 0)
		local placed = { { Knots = first, Samples = Sampled(first, 0) } }
		local at, yaw = first[#first], START.EndYaw
		local whole = true
		for _ = 1, count do
			local fit = nil
			local last = placed[#placed].Samples
			local from = last[#last].A
			for _ = 1, TRIES do
				local piece = PIECES[rng:NextInteger(1, #PIECES)]
				local mirror = if rng:NextNumber() > 0.5 then -1 else 1
				local knots = Place(piece, mirror, at, yaw)
				local samples = Sampled(knots, from)
				if Clear(samples, placed, gap, around) then
					fit = { Knots = knots, Samples = samples, Yaw = yaw + mirror * piece.EndYaw }
					break
				end
			end
			if not fit then
				whole = false
				break
			end
			table.insert(placed, fit)
			at, yaw = fit.Knots[#fit.Knots], fit.Yaw
		end
		if whole then return placed end
		if not best or #placed > #best then best = placed end
	end
	return best
end

local function Turn(placed): (number, Vector3)
	local bestYaw, bestArea, bestCentre = 0, math.huge, Vector3.zero
	for yaw = 0, 75, 15 do
		local c, s = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, piece in placed do
			for _, sample in piece.Samples do
				local p = sample.P
				local x, z = p.X * c + p.Z * s, -p.X * s + p.Z * c
				x0, x1, z0, z1 = math.min(x0, x - 100), math.max(x1, x + 100), math.min(z0, z - 100), math.max(z1, z + 100)
			end
		end
		local area = (x1 - x0) * (z1 - z0)
		if area < bestArea then bestYaw, bestArea, bestCentre = yaw, area, Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2) end
	end
	return bestYaw, bestCentre
end

local function Spline(knots: { Vector3 }, step: number): { Vector3 }
	local out = { knots[1] }
	local n = #knots
	local function nextT(t: number, a: Vector3, b: Vector3): number
		return t + math.max((b - a).Magnitude, 1e-3) ^ 0.5
	end
	for i = 1, n - 1 do
		local p0, p1, p2, p3 = knots[math.max(i - 1, 1)], knots[i], knots[i + 1], knots[math.min(i + 2, n)]
		local t0 = 0
		local t1 = nextT(t0, p0, p1)
		local t2 = nextT(t1, p1, p2)
		local t3 = nextT(t2, p2, p3)
		local steps = math.max(math.ceil((p2 - p1).Magnitude / step), 1)
		for j = 1, steps do
			local t = t1 + (t2 - t1) * j / steps
			local a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
			local a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
			local a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
			local b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
			local b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
			out[#out + 1] = b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
		end
	end
	return out
end

local function Resample(points: { Vector3 }, step: number): { Vector3 }
	local out = { points[1] }
	local want, walked = step, 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local len = (b - a).Magnitude
		while len > 0 and walked + len >= want do
			out[#out + 1] = a:Lerp(b, (want - walked) / len)
			want += step
		end
		walked += len
	end
	if (out[#out] - points[#points]).Magnitude > step * 0.25 then out[#out + 1] = points[#points] else out[#out] = points[#points] end
	return out
end

-- // THE COURSE //--

local function Perlin01(x: number, z: number): number
	local n = 0.5 + math.noise(x, z, NOISE_Z) * 0.5
	return if n < 0 then 0 elseif n > 1 then 1 else n
end

function Generated.Build(seed: number, force: string?, judge: boolean?)
	seed = math.floor(tonumber(seed) or 0)
	force = if type(force) == "string" and force ~= "" then string.lower(force) else nil
	if judge == nil then judge = Config.Judge ~= nil and Config.Judge.On == true end
	local id = (if force then seed .. ":" .. force else tostring(seed)) .. (if judge then ":judge" else "")
	if Cache[id] then return Cache[id] end
	local yielding = coroutine.isyieldable()
	if yielding then
		local waited = 0
		while Building[id] and waited < 15 do waited += task.wait() end
		if Cache[id] then return Cache[id] end
		Building[id] = true
	end
	local MAP = Config.Map
	local k = MAP.Scale
	local rng = Random.new(seed)

	local roadRng = Random.new(seed + 7919)
	local ROAD = MAP.Road
	local function factor(amount: number): number return 1 + (roadRng:NextNumber() * 2 - 1) * amount end
	local halfWidth = ROAD.HalfWidth * factor(ROAD.WidthRandom) * k
	local noiseWidth = ROAD.Noise * factor(ROAD.NoiseRandom) * k
	local roadFreq = ROAD.NoiseScale * factor(ROAD.NoiseScaleRandom) * 0.005 / k
	local rim = ROAD.Rim * k
	local reach = halfWidth + noiseWidth + rim
	local reach2 = reach * reach

	local gap = 2 * reach / k + MAP.Apart
	local placed = Chain(rng, MAP.Segments, gap, gap * 1.6)
	local yaw, centre = Turn(placed)
	local c, s = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
	local knots = {}
	local yLow, yHigh = math.huge, -math.huge
	for index, piece in placed do
		for i, p in piece.Knots do
			if index == 1 or i > 1 then
				local x, z = p.X * c + p.Z * s, -p.X * s + p.Z * c
				knots[#knots + 1] = Vector3.new(x - centre.X, p.Y, z - centre.Z)
				yLow, yHigh = math.min(yLow, p.Y), math.max(yHigh, p.Y)
			end
		end
	end
	local mid = (yLow + yHigh) / 2
	local metres = Resample(Spline(knots, FINE_STEP), LINE_STEP)

	-- in the world (units)
	local base = MAP.Centre
	local points, along = {}, { 0 }
	local px, py, pz = {}, {}, {}
	for i, p in metres do
		local w = Vector3.new(base.X + p.X * k, base.Y + (p.Y - mid) * k, base.Z + p.Z * k)
		points[i] = w
		px[i], py[i], pz[i] = w.X, w.Y, w.Z
		if i > 1 then along[i] = along[i - 1] + (w - points[i - 1]).Magnitude end
	end
	local length = along[#along]

	local function offset(): number return rng:NextNumber(-10000, 10000) end
	local roadOx, roadOz = offset(), offset()
	local hills = {}
	for i, h in MAP.Hills do
		hills[i] = { F = h.Scale * 0.005 / k, Str = h.Str * k, Exp = h.Exp, Ox = offset(), Oz = offset() }
	end

	local grade = MAP.Slope * 0.1
	for i = 1, #points do
		py[i] += grade * (length / 2 - along[i])
		points[i] = Vector3.new(px[i], py[i], pz[i])
	end
	local DIPS = MAP.Dips

	local dipRng = Random.new(seed + 104729)
	local dips = {}
	local flat = DIPS.Flat * k
	local at = flat
	while true do
		local big = dipRng:NextNumber() < DIPS.Big.Chance
		local spacing = dipRng:NextNumber(DIPS.Spacing[1], DIPS.Spacing[2]) * k * (if big then DIPS.Big.Spacing else 1)
		local depth = dipRng:NextNumber(DIPS.Depth[1], DIPS.Depth[2]) * k * (if big then DIPS.Big.Depth else 1)
		if at + spacing > length - flat then break end
		dips[#dips + 1] = { at, at + spacing * DIPS.Drop, at + spacing, depth, Big = big }
		at += spacing
	end
	local bowl = DIPS.Shape
	local rollF, rollStr, rollO = 1 / (MAP.Roll.Wave * k), MAP.Roll.Str * k, offset()

	local rampTotal = 0
	local function Rebase()
		local total = 0
		for _, dip in dips do
			dip.Before = total
			if dip.Ramp then total += dip.Ramp.Drop end
		end
		rampTotal = total
	end
	local function Profile(d: number): number
		local h = math.noise(d * rollF + rollO, NOISE_Z, 0.71) * 2 * rollStr
		for _, dip in dips do
			if d <= dip[1] then return h - (dip.Before or 0) end   -- (in order: the rest are further on)
			if d < dip[3] then
				local ramp = dip.Ramp
				if ramp then
					local u = math.clamp((d - ramp.From) / (dip[3] - ramp.From), 0, 1)
					return h - (dip.Before or 0) - ramp.Drop * (1 - (1 - u) ^ ramp.Shape)
				end
				local u = if d < dip[2] then (d - dip[1]) / (dip[2] - dip[1]) else (dip[3] - d) / (dip[3] - dip[2])
				return h - (dip.Before or 0) - dip[4] * (1 - (1 - u) ^ bowl)
			end
		end
		return h - rampTotal
	end

	local roadLow = math.huge
	for i = 1, #points do roadLow = math.min(roadLow, py[i] + Profile(along[i])) end
	local voidY = roadLow - MAP.Void * k
	local hillTop = 0
	for _, h in hills do hillTop += h.Str end

	local cell = reach
	local buckets: { [number]: { number } } = {}
	local function key(cx: number, cz: number): number return cx * 1048576 + cz end
	for i = 1, #points - 1 do
		local x0 = math.floor((math.min(px[i], px[i + 1]) - reach) / cell)
		local x1 = math.floor((math.max(px[i], px[i + 1]) + reach) / cell)
		local z0 = math.floor((math.min(pz[i], pz[i + 1]) - reach) / cell)
		local z1 = math.floor((math.max(pz[i], pz[i + 1]) + reach) / cell)
		for cx = x0, x1 do
			for cz = z0, z1 do
				local list = buckets[key(cx, cz)]
				if not list then
					list = {}
					buckets[key(cx, cz)] = list
				end
				list[#list + 1] = i
			end
		end
	end

	local function Road(x: number, z: number): (number, number, number, number)
		local list = buckets[key(math.floor(x / cell), math.floor(z / cell))]
		if not list then return 0, math.huge, 0, 0 end
		local bestD2, bestY, bestS = math.huge, 0, 0
		for _, i in list do
			local ax, az = px[i], pz[i]
			local dx, dz = px[i + 1] - ax, pz[i + 1] - az
			local len2 = dx * dx + dz * dz
			local t = if len2 > 1e-9 then ((x - ax) * dx + (z - az) * dz) / len2 else 0
			t = if t < 0 then 0 elseif t > 1 then 1 else t
			local qx, qz = ax + dx * t - x, az + dz * t - z
			local d2 = qx * qx + qz * qz
			if d2 < bestD2 then
				bestD2, bestY, bestS = d2, py[i] + (py[i + 1] - py[i]) * t, along[i] + (along[i + 1] - along[i]) * t
			end
		end
		if bestD2 >= reach2 then return 0, math.huge, bestS, bestY end
		local dist = math.sqrt(bestD2)
		local widen = Perlin01(x * roadFreq + roadOx, z * roadFreq + roadOz) * noiseWidth
		local u = (dist - halfWidth - widen) / rim
		return (if u <= 0 then 1 elseif u >= 1 then 0 else 1 - u * u * (3 - 2 * u)), dist, bestS, bestY
	end

	local function PointAt(d: number): (Vector3, Vector3)
		d = math.clamp(d, 0, length)
		for i = 2, #points do
			if along[i] >= d then
				local seg = along[i] - along[i - 1]
				local dir = (points[i] - points[i - 1]).Unit
				return points[i - 1]:Lerp(points[i], if seg > 0 then (d - along[i - 1]) / seg else 0), dir
			end
		end
		return points[#points], (points[#points] - points[#points - 1]).Unit
	end

	local pieces = {}
	local PIECES_ = MAP.Pieces
	local wall = (PIECES_ and PIECES_.Wall or 3) * k
	local function fade(u: number): number   -- 1 at u <= 0, easing to 0 at u >= 1
		if u <= 0 then return 1 elseif u >= 1 then return 0 end
		return 1 - u * u * (3 - 2 * u)
	end

	local function Shape(isle, x: number, z: number): (number, number)
		local dx, dz = x - isle.X, z - isle.Z
		local u, v = dx * isle.Ux + dz * isle.Uz, dz * isle.Ux - dx * isle.Uz
		local a, b = math.abs(u / isle.A), math.abs(v / isle.B)
		return (a * a * a * a + b * b * b * b) ^ 0.25, u
	end

	local function Cut(x: number, z: number, s: number): (number, number)
		local best, lift = 0, 0
		for _, piece in pieces do
			if s > piece.From - wall and s < piece.To + wall then
				local m = if s < piece.From then fade((piece.From - s) / wall) elseif s > piece.To then fade((s - piece.To) / wall) else 1
				for _, isle in piece.Islands do
					local q, u = Shape(isle, x, z)
					m *= 1 - fade((q - 1) * isle.B / wall)
					local run = isle.A * isle.KickRun
					local t = (u - (isle.A - run)) / run
					if t > 0 and q < 1 + wall / isle.B then lift = math.max(lift, isle.Kick * math.min(t, 1.2) ^ 2) end
				end
				if m > best then best = m end
			end
		end
		return best, lift
	end

	local function InCut(s: number, r: number): boolean
		for _, piece in pieces do
			if s > piece.From - wall - r and s < piece.To + wall + r then return true end
		end
		return false
	end

	local function Ground(x: number, z: number, uncut: boolean?): number
		local w, dist, s, y = Road(x, z)
		if dist == math.huge then return voidY end
		local h = voidY + (y + Profile(s) - voidY) * w
		for _, hill in hills do
			local n = Perlin01(x * hill.F + hill.Ox, z * hill.F + hill.Oz)
			if hill.Exp ~= 1 then n = math.max(n, 0.0001) ^ hill.Exp end
			h += n * hill.Str
		end
		if not uncut and pieces[1] then
			local m, lift = Cut(x, z, s)
			h += lift
			if m > 0 then h += (voidY - h) * m end
		end
		return h
	end
	pieces = SetPieces({ Seed = seed, Force = force, Dips = dips, PointAt = PointAt, HalfWidth = halfWidth, Rebase = Rebase,
		Uncut = function(d: number): number
			local p = PointAt(d)
			return Ground(p.X, p.Z, true)
		end })
	if rampTotal > 0 then
		roadLow = math.huge
		for i = 1, #points do roadLow = math.min(roadLow, py[i] + Profile(along[i])) end
		voidY = roadLow - MAP.Void * k
	end

	local PAD = MAP.StartPad
	local padAt, padDir = PointAt(PAD.Ahead * k)
	local padRight = Vector3.new(-padDir.Z, 0, padDir.X).Unit
	local padY = Ground(padAt.X, padAt.Z)
	local padHalf = PAD.Size * (k / 2)
	local padRim = PAD.Rim * k
	local finish = points[#points]
	local finishY = Ground(finish.X, finish.Z)
	local finIn, finOut = MAP.EndPad.Inner * k, MAP.EndPad.Outer * k

	local HILL = PAD.Hill
	local hillRise = if HILL then HILL.Rise * k else 0
	local hillEdge = if HILL then (HILL.Edge - PAD.Ahead) * k else 0
	local hillDrop = if HILL then HILL.Drop * k else 1
	local function smooth(u: number): number
		if u <= 0 then return 1 elseif u >= 1 then return 0 end
		return 1 - u * u * (3 - 2 * u)
	end
	local function BaseHeight(x: number, z: number, uncut: boolean?): number
		local h = Ground(x, z, uncut)
		local rx, rz = x - padAt.X, z - padAt.Z
		local across = math.abs(rx * padRight.X + rz * padRight.Z) - padHalf.X
		local ahead = math.abs(rx * padDir.X + rz * padDir.Z) - padHalf.Y
		local t = smooth(math.max(across / padRim.X, ahead / padRim.Y))
		if t > 0 then
			local top = padY
			if hillRise > 0 then
				local u = ((rx * padDir.X + rz * padDir.Z) - hillEdge) / hillDrop
				top += hillRise * (if u <= 0 then 1 elseif u >= 1 then 0 else (1 - u) * (1 - u))
			end
			h += (top - h) * t
		end
		local fx, fz = x - finish.X, z - finish.Z
		local f = smooth((math.sqrt(fx * fx + fz * fz) - finIn) / (finOut - finIn))
		if f > 0 then h += (finishY - h) * f end
		return h
	end

	local traps = PlaceTraps({ Seed = seed, Force = force, Judge = judge, Length = length, PointAt = PointAt, Height = BaseHeight,
		HalfWidth = halfWidth, Pieces = pieces, Dips = dips })

	local cards = PlaceCards({ Seed = seed, Judge = judge, Length = length, PointAt = PointAt, Height = BaseHeight, HalfWidth = halfWidth,
		Pieces = pieces, Start = (if HILL then HILL.Edge else 0) * k })
	local function Blocked(x: number, z: number, r: number): boolean
		if not (pieces[1] or traps[1] or cards[1]) then return false end
		for _, card in cards do
			local dx, dz = x - card.Position.X / S, z - card.Position.Z / S
			if dx * dx + dz * dz < (r + 4) ^ 2 then return true end
		end
		local _, dist, s = Road(x, z)
		if dist ~= math.huge and InCut(s, r) then return true end
		for _, trap in traps do
			if trap.Kind == "Spinner" then
				if math.abs(s - trap.Along) < r + 6 then return true end
			elseif trap.Kind == "Cage" and trap.Low then
				local dx, dz = x - trap.Centre.X, z - trap.Centre.Z
				if dx * dx + dz * dz < (trap.R + r + 4) ^ 2 then return true end
			elseif trap.Kind == "Missile" then
				local dx, dz = x - trap.Foot.X, z - trap.Foot.Z
				if dx * dx + dz * dz < (trap.Half + r + 4) ^ 2 then return true end
			end
		end
		return false
	end
	local props, propCounts, bumps = PlaceProps({ Seed = seed, Road = Road, Height = BaseHeight, PointAt = PointAt,
		Line = { Length = length }, HalfWidth = halfWidth, NoiseWidth = noiseWidth, StartAt = padAt, Finish = finish,
		Blocked = Blocked }, yielding)
	local MoundAt = Mounds(bumps)
	local function Height(x: number, z: number, uncut: boolean?): number
		return BaseHeight(x, z, uncut) + MoundAt(x, z)
	end

	local function Floating(x: number, z: number): number?
		for _, piece in pieces do
			for _, isle in piece.Islands do
				local reachQ = 1 + wall / isle.B
				local q = Shape(isle, x, z)
				if q < reachQ then
					local u = q / reachQ
					local jag = 1 + math.noise(x * 0.15, z * 0.15, isle.Noise) * 0.35
					return 1.5 + isle.Thick * (1 - u * u) ^ 0.6 * jag
				end
			end
		end
		return nil
	end
	local function GapRim(x: number, z: number): number?
		if not pieces[1] then return nil end
		local _, dist, s = Road(x, z)
		if dist == math.huge or not InCut(s, wall) then return nil end
		return Height(x, z, true)
	end
	local FALL = PIECES_ and PIECES_.Fall

	local function FallBack(x: number, z: number): (number, Vector3?)
		local _, _, s = Road(x, z)
		local every = MAP.WaypointEvery * k
		local target, aim = s - (FALL and FALL.Back or 220) * k, nil
		for _, piece in pieces do
			if s > piece.Crest - wall * 4 and s < piece.To + wall * 4 then
				target = piece.Crest - (FALL and FALL.RunUp or 40) * k
				local c = PointAt(piece.Crest)
				aim = Vector3.new(c.X, Height(c.X, c.Z, true), c.Z)
				break
			end
		end
		local n = math.floor(target / every)
		while n >= 1 and InCut(n * every, wall * 2) do n -= 1 end
		return math.max(n, 0), aim
	end

	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, #points do
		x0, x1, z0, z1 = math.min(x0, px[i]), math.max(x1, px[i]), math.min(z0, pz[i]), math.max(z1, pz[i])
	end
	local margin = reach + 10
	local origin = Vector2.new(x0 - margin, z0 - margin)
	local size = Vector2.new(x1 - x0 + 2 * margin, z1 - z0 + 2 * margin)

	local function OnGround(p: Vector3, up: number): Vector3   -- (over a cut: where the road would be)
		return Vector3.new(p.X, Height(p.X, p.Z, true), p.Z) * S + Vector3.new(0, up, 0)
	end
	local startAt, startDir = PointAt(10 * k)
	local startPos = OnGround(startAt, 1)

	local edgeAlong = (if HILL then HILL.Edge else 0) * k
	local function RaceSlot(slot: number): CFrame
		local R = Config.Race
		local back = (R.JogDistance + slot * R.RowGap) / S
		local p, dir = PointAt(math.max(edgeAlong - back, 0))
		local flat = Vector3.new(dir.X, 0, dir.Z).Unit
		local side = if slot % 2 == 0 then -1 else 1
		local q = p + Vector3.new(-flat.Z, 0, flat.X) * (side * R.Across / 2 / S)
		local at = Vector3.new(q.X, Height(q.X, q.Z), q.Z) * S + Vector3.new(0, 0.5, 0)
		return CFrame.lookAt(at, at + flat)
	end
	local waypoints = {}
	local every = MAP.WaypointEvery * k
	for d = every, length - every * 0.5, every do
		waypoints[#waypoints + 1] = OnGround((PointAt(d)), 4)
	end
	waypoints[#waypoints + 1] = OnGround(points[#points], 4)
	local gates = {}
	for lap = 1, math.max(MAP.Laps, 1) - 1 do
		gates[lap] = OnGround((PointAt(length * lap / MAP.Laps)), 4)
	end

	local data = {
		Seed = seed, Force = force, Judge = judge,
		Height = Height, height = Height,
		Origin = origin, Size = size, Spacing = MAP.Spacing,
		Line = { Points = points, Along = along, Length = length },
		Start = CFrame.lookAt(startPos, startPos + Vector3.new(startDir.X, 0, startDir.Z)),
		Waypoints = waypoints, Gates = gates,
		KillY = (roadLow - MAP.Kill * k) * S,
		VoidTop = (voidY + hillTop + 2) * S,
		Dips = #dips,
		Length = length * S,
		Pieces = #placed,
		Reach = reach,
		-- for Generated.Props (units)
		Road = Road, PointAt = PointAt,
		HalfWidth = halfWidth, NoiseWidth = noiseWidth,
		StartAt = padAt, Finish = finish,
		Props = props, PropCounts = propCounts, Mounds = #bumps,
		SetPieces = pieces, Floating = Floating, GapRim = GapRim, FallBack = FallBack, Traps = traps, Cards = cards,
		RaceSlot = RaceSlot, Edge = edgeAlong,
	}
	Building[id] = nil
	Cache[id] = data
	table.insert(CacheOrder, id)
	if #CacheOrder > 4 then Cache[table.remove(CacheOrder, 1)] = nil end
	return data
end

-- // THE PROPS //--

local function Layered(x: number, z: number, f: number, ox: number, oz: number): number
	local v = 0
	for i = 0, 2 do
		local p = Perlin01(x * f + ox, z * f + oz)
		v = if i == 0 then p else v + (p - v) * 0.2 ^ i
		f *= 2
	end
	return v
end

function PlaceProps(data, yielding: boolean?)
	local MAP = Config.Map
	local RULES = MAP.Props
	local RAMP = RULES and RULES.Ramp
	local list, counts, bumps = {}, {}, {}
	local library = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	library = library and library:FindFirstChild("Speed")
	library = library and library:FindFirstChild("Props")
	if not (RULES and RULES.Enabled and library and data.Road) then return list, counts, bumps end
	local k = MAP.Scale
	local rng = Random.new(data.Seed + 1299709)
	local looks = Random.new(data.Seed + 15485863)
	local Road, Height, PointAt = data.Road, data.Height, data.PointAt
	local length = data.Line.Length
	local across = data.HalfWidth + data.NoiseWidth
	local clock = os.clock()
	local function breathe()
		if yielding and os.clock() - clock > 0.004 then
			task.wait()
			clock = os.clock()
		end
	end

	local flatArea = 0
	local STEP_ALONG, STEP_ACROSS = 44, 4
	for d = STEP_ALONG / 2, length, STEP_ALONG do
		local p, dir = PointAt(d)
		local right = Vector3.new(-dir.Z, 0, dir.X).Unit
		for o = -across - 4, across + 4, STEP_ACROSS do
			local q = p + right * o
			if Road(q.X, q.Z) >= 0.9999 then flatArea += STEP_ACROSS * STEP_ALONG end
		end
		breathe()
	end
	local speedArea = flatArea / (k * k)

	local CELL = 30
	local grid: { [number]: { { number } } } = {}
	local function cellKey(x: number, z: number): number return math.floor(x / CELL) * 1048576 + math.floor(z / CELL) end
	local function Free(x: number, z: number, r: number, rank: number): boolean
		local reach = math.ceil((r + 60) / CELL)
		local cx, cz = math.floor(x / CELL), math.floor(z / CELL)
		for i = cx - reach, cx + reach do
			for j = cz - reach, cz + reach do
				local bucket = grid[i * 1048576 + j]
				if bucket then
					for _, o in bucket do
						if o[4] >= rank then
							local dx, dz, rr = o[1] - x, o[2] - z, o[3] + r
							if dx * dx + dz * dz < rr * rr then return false end
						end
					end
				end
			end
		end
		return true
	end
	local function Add(x: number, z: number, r: number, rank: number)
		local key = cellKey(x, z)
		local bucket = grid[key]
		if not bucket then
			bucket = {}
			grid[key] = bucket
		end
		table.insert(bucket, { x, z, r, rank })
	end

	local start, finish = data.StartAt, data.Finish
	local clearStart, clearEnd = RULES.ClearStart * k, RULES.ClearEnd * k
	local S_ = S
	for _, rule in RULES.Kinds do
		local folder = library:FindFirstChild(rule.Name)
		local assets = folder and folder:GetChildren() or {}
		table.sort(assets, function(a, b) return a.Name < b.Name end)
		local weights, totalWeight = {}, 0
		for i, a in assets do
			weights[i] = math.max(tonumber(a:GetAttribute("Weight")) or 1, 0)
			totalWeight += weights[i]
		end
		local function Pick()
			local roll = rng:NextNumber() * totalWeight
			for i, w in weights do
				roll -= w
				if roll < 0 then return assets[i] end
			end
			return assets[#assets]
		end
		local target = math.min(math.round(rule.Count * speedArea / 200000), rule.Max)
		counts[rule.Name] = 0
		if #assets == 0 or target <= 0 then continue end
		local f = if rule.Perlin then 1 / (rule.Perlin.Wave * k) else 0
		local ox, oz = rng:NextNumber(-10000, 10000), rng:NextNumber(-10000, 10000)
		local maxSlope = math.cos(math.rad(math.min(rule.Slope, 89)))
		local placed = 0
		for _ = 1, 10 do
			for _ = 1, math.min(target * 2, 6000) do
				if placed >= target then break end
				local d = rng:NextNumber() * length
				local side = if rng:NextNumber() < 0.5 then -1 else 1
				local off = rng:NextNumber(rule.Dist[1], rule.Dist[2]) * across * side
				local asset = Pick()
				local size = rule.Size[1] + (rule.Size[2] - rule.Size[1]) * rng:NextNumber() ^ rule.SizePow
				local yaw = rng:NextNumber() * math.pi * 2
				local p, dir = PointAt(d)
				local x, z = p.X - dir.Z * off, p.Z + dir.X * off
				if Road(x, z) < 0.9999 then continue end
				if rule.Perlin then
					local v = Layered(x, z, f, ox, oz)
					if v < rule.Perlin.Min or v > rule.Perlin.Max then continue end
				end
				local sx, sz = x - start.X, z - start.Z
				if sx * sx + sz * sz < clearStart * clearStart then continue end
				local ex, ez = x - finish.X, z - finish.Z
				if ex * ex + ez * ez < clearEnd * clearEnd then continue end

				local native = asset:GetAttribute("Height") or 1
				local scale = (if rule.Height then rule.Height / native else 1) * size * k * S_
				local tall = native * scale / S_   -- units, as drawn
				local r = (asset:GetAttribute("Radius") or 1) * scale / S_
				if rule.Spread then
					r = math.max(r, (asset:GetAttribute("Width") or 0) / 2 * rule.Spread * scale / S_)
				end

				local ramp = RAMP ~= nil and (rule.Ramp or (rule.RampBelow ~= nil and tall * S_ < rule.RampBelow))
				local ra, rb, run = 0, 0, 0
				if ramp then
					ra = (asset:GetAttribute("SizeX") or 1) * scale / S_ / 2 * RAMP.Top
					rb = (asset:GetAttribute("SizeZ") or 1) * scale / S_ / 2 * RAMP.Top
					run = math.max(tall * RAMP.Height * RAMP.Steep, RAMP.MinRun)
					r = math.max(ra, rb) + run
				end
				if not Free(x, z, r, rule.Rank) then continue end
				if data.Blocked and data.Blocked(x, z, r) then continue end
				if ramp then

					local whole = true
					for a = 0, 7 do
						local ang = a * math.pi / 4
						if Road(x + math.cos(ang) * r, z + math.sin(ang) * r) < 0.9999 then
							whole = false
							break
						end
					end
					if not whole then continue end
				end
				local y = Height(x, z)
				local hx = Height(x + 1, z) - Height(x - 1, z)
				local hz = Height(x, z + 1) - Height(x, z - 1)
				local normal = Vector3.new(-hx, 2, -hz).Unit
				if normal.Y < maxSlope then continue end

				local tan = math.sqrt(math.max(1 - normal.Y * normal.Y, 0)) / normal.Y
				local sink = if ramp then 0 else r * tan * (1 - rule.Tilt) + tall * 0.02
				local up = Vector3.yAxis:Lerp(normal, rule.Tilt).Unit
				local look = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
				local side3 = (look - up * look:Dot(up)).Unit
				local at = Vector3.new(x, y - sink, z) * S_
				Add(x, z, r, rule.Rank)
				placed += 1
				if ramp then
					local across2 = Vector2.new(side3.X, side3.Z).Unit   -- the rock's own x, flat
					table.insert(bumps, { X = x, Z = z, Top = tall * RAMP.Height, A = math.max(ra, 0.5), B = math.max(rb, 0.5),
						R = math.sqrt(math.max(ra * rb, 0.25)), Run = run, Ux = across2.X, Uz = across2.Y, Reach = math.max(ra, rb) + run })
				end
				local shadow = rule.Shadows == nil or looks:NextNumber() < rule.Shadows
				table.insert(list, { Kind = rule.Name, Asset = asset.Name, CFrame = CFrame.fromMatrix(at, side3, up), Scale = scale,
					Along = d * S_, Ramp = ramp or nil, NoShadow = (not shadow) or nil })
				if placed % 20 == 0 then breathe() end
			end
			if placed >= target then break end
			breathe()
		end
		counts[rule.Name] = placed
	end
	counts.FlatArea = math.round(speedArea)
	counts.Ramps = #bumps
	return list, counts, bumps
end

function Generated.Props(data)
	return data.Props or {}, data.PropCounts or {}
end

function Mounds(bumps)
	if #bumps == 0 then return function() return 0 end end
	local CELL = 24
	local grid: { [number]: { any } } = {}
	for _, b in bumps do
		for i = math.floor((b.X - b.Reach) / CELL), math.floor((b.X + b.Reach) / CELL) do
			for j = math.floor((b.Z - b.Reach) / CELL), math.floor((b.Z + b.Reach) / CELL) do
				local key = i * 1048576 + j
				local list = grid[key]
				if not list then
					list = {}
					grid[key] = list
				end
				table.insert(list, b)
			end
		end
	end
	return function(x: number, z: number): number
		local list = grid[math.floor(x / CELL) * 1048576 + math.floor(z / CELL)]
		if not list then return 0 end
		local best = 0
		for _, b in list do
			local dx, dz = x - b.X, z - b.Z
			local u = (dx * b.Ux + dz * b.Uz) / b.A
			local v = (dz * b.Ux - dx * b.Uz) / b.B
			local q = math.sqrt(u * u + v * v)
			local h = b.Top
			if q > 1 then
				local w = (q - 1) * b.R / b.Run
				h = if w >= 1 then 0 else b.Top * (1 + math.cos(math.pi * w)) / 2
			end
			if h > best then best = h end
		end
		return best
	end
end

function Generated.ForCourse(course: Instance)
	return Generated.Build(course:GetAttribute("Seed") or 0, course:GetAttribute("Pieces"), course:GetAttribute("Judge"))
end

-- // THE SET PIECES //--

function SetPieces(data)
	local MAP = Config.Map
	local P = MAP.Pieces
	local list = {}
	if not (P and P.Enabled) then return list end
	local k = MAP.Scale
	local rng = Random.new(data.Seed + 32452843)
	local crests = {}
	for i, dip in data.Dips do
		if i > 1 then table.insert(crests, { At = dip[1], Down = dip[2] - dip[1], Big = dip.Big, Dip = dip }) end
	end
	for i = #crests, 2, -1 do   -- shuffled
		local j = rng:NextInteger(1, i)
		crests[i], crests[j] = crests[j], crests[i]
	end
	local lip, wall, apart = P.Lip * k, P.Wall * k, P.Apart * k
	local function Room(at: number): boolean
		for _, piece in list do
			if math.abs(piece.Crest - at) < apart then return false end
		end
		return true
	end

	local function Landing(crestAt: number, speed: number): number
		local y0 = data.Uncut(crestAt)
		local rise = y0 - data.Uncut(crestAt - 2)
		local n = math.sqrt(4 + rise * rise)
		local vx, vy = speed * 2 / n, speed * rise / n
		local x, y = crestAt, y0
		local push, drag, dt = Config.AirSpeed / Config.TickRate, Config.Drag * Config.TickRate, 1 / 30
		for _ = 1, 240 do
			vx += (push - drag * vx) * dt
			vy += (-Config.Gravity - drag * vy) * dt
			x, y = x + vx * dt, y + vy * dt
			if y < data.Uncut(x) then break end
		end
		return x
	end

	local R = P.Gaps.Ramp
	local rampRng = Random.new(data.Seed + 15485863)
	local function Gap(crest)
		local G = P.Gaps
		local dip = crest.Dip
		local roll, slope = rampRng:NextNumber(), rampRng:NextNumber()
		if R and dip and data.Rebase and roll < R.Chance then
			local nextTaken = false
			for _, piece in list do
				if math.abs(piece.Crest - dip[3]) < 1 then nextTaken = true end
			end
			if not nextTaken then
				local from = crest.At + lip
				dip.Ramp = { From = from, Shape = R.Shape,
					Drop = (dip[3] - from) * math.tan(math.rad(R.Slope[1] + (R.Slope[2] - R.Slope[1]) * slope)) }
				data.Rebase()
			end
		end
		local down = if dip and dip.Ramp then dip[3] - crest.At else crest.Down
		local reach = Landing(crest.At, P.Hops.Speeds[1] / Config.Studs) - crest.At - lip - P.Hops.Pad * k
		local len = math.min(rng:NextNumber(G.Length[1], G.Length[2]) * k, down * G.MaxShare, reach)
		table.insert(list, { Kind = "Gap", Crest = crest.At, From = crest.At + lip, To = crest.At + lip + math.max(len, 8), Islands = {},
			Ramp = dip and dip.Ramp ~= nil })
	end
	local function Hop(crest)
		local H = P.Hops
		local from = crest.At + lip
		local near = Landing(crest.At, H.Speeds[1] / Config.Studs)
		local far = Landing(crest.At, H.Speeds[2] / Config.Studs)
		local pad = H.Pad * k
		local start = math.max(near - pad, from + H.MinBefore * k)
		local a = math.max((far + pad - start) / 2, 10)
		local b = rng:NextNumber(H.Width[1], H.Width[2]) * k / 2
		local after = rng:NextNumber(H.After[1], H.After[2]) * k
		local kick = H.Kick * k
		local ends = start + 2 * a
		if (data.Uncut(ends + after * 2) - data.Uncut(ends)) / (after * 2) > H.MaxClimb then
			after, kick = 0, 0
		end
		local mid = start + a
		local p, dir = data.PointAt(mid)
		local flat = Vector2.new(dir.X, dir.Z).Unit
		local off = rng:NextNumber(-1, 1) * H.Sway * data.HalfWidth
		table.insert(list, { Kind = "Hop", Crest = crest.At, From = from, To = mid + a + after, Islands = { {
			X = p.X - flat.Y * off, Z = p.Z + flat.X * off, A = a, B = b, R = math.max(a, b), Ux = flat.X, Uz = flat.Y,
			Along = mid, Kick = kick, KickRun = H.KickRun,
			Thick = rng:NextNumber(H.Thickness[1], H.Thickness[2]) * k, Noise = rng:NextNumber(0, 100) + 0.37 } } })
	end
	local force = data.Force
	if force == "gaps" or force == "islands" or force == "hops" or force == "all" then
		table.sort(crests, function(a, b) return a.At < b.At end)
		for i, crest in crests do
			local last = list[#list]
			if last and crest.At < last.To + wall * 4 then continue end
			if force == "gaps" or (force == "all" and i % 2 == 0) then Gap(crest) else Hop(crest) end
		end
	else
		local hops = rng:NextInteger(P.Hops.Count[1], P.Hops.Count[2])
		local gaps = rng:NextInteger(P.Gaps.Count[1], P.Gaps.Count[2])
		for pass = 1, 2 do   -- big dips first
			for _, crest in crests do
				if hops <= 0 then break end
				if (crest.Big or pass == 2) and Room(crest.At) then
					Hop(crest)
					hops -= 1
				end
			end
		end
		for _, crest in crests do
			if gaps <= 0 then break end
			if Room(crest.At) then
				Gap(crest)
				gaps -= 1
			end
		end
	end
	table.sort(list, function(a, b) return a.From < b.From end)
	return list
end

-- // THE CARDS //--

function PlaceCards(data)
	local C = Config.Items and Config.Items.Cards
	local list = {}
	if not C then return list end
	local k = Config.Map.Scale
	local wall = (Config.Map.Pieces and Config.Map.Pieces.Wall or 3) * k
	local function InCut(s: number): boolean
		for _, piece in data.Pieces do
			if s > piece.From - wall * 3 and s < piece.To + wall * 3 then return true end
		end
		return false
	end
	local alongs = {}
	local from, to = data.Start + C.Clear * k, data.Length - C.Clear * k
	for s = from, to, C.Every * k do table.insert(alongs, s) end
	local afterGap = {}   -- (the rows past a gap's landing)
	for _, piece in data.Pieces do
		local s = piece.To + C.AfterGap * k
		if s < to then
			table.insert(alongs, s)
			afterGap[s] = true
		end
	end
	table.sort(alongs)
	local rows, last = {}, -math.huge
	for _, s in alongs do
		if not InCut(s) and s - last > C.AfterGap * k * 0.6 then
			last = s
			table.insert(rows, s)
		end
	end

	local judge = Config.Judge
	if data.Judge and judge and judge.Cards < 1 then
		local plain = {}
		for _, s in rows do
			if not afterGap[s] then table.insert(plain, s) end
		end
		local drop = math.min(#rows - math.round(#rows * judge.Cards), #plain)
		local gone = {}
		for i, s in plain do
			if math.floor(i * drop / #plain + 0.5) > math.floor((i - 1) * drop / #plain + 0.5) then gone[s] = true end
		end
		local kept = {}
		for _, s in rows do
			if not gone[s] then table.insert(kept, s) end
		end
		rows = kept
	end
	for _, s in rows do
		do
			local p, dir = data.PointAt(s)
			local flat = Vector3.new(dir.X, 0, dir.Z).Unit
			local right = Vector3.new(-flat.Z, 0, flat.X)
			for j = 1, C.Lanes do
				local q = p + right * ((-1 + 2 * (j - 1) / math.max(C.Lanes - 1, 1)) * C.Spread * data.HalfWidth)
				local y = data.Height(q.X, q.Z) * S + C.Lift
				table.insert(list, { Id = #list + 1, Position = Vector3.new(q.X * S, y, q.Z * S), Along = s, Facing = -flat })
			end
		end
	end
	return list
end

-- // THE TRAPS //--

function PlaceTraps(data)
	local MAP = Config.Map
	local T = MAP.Traps
	local list = {}
	local library = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	library = library and library:FindFirstChild("Speed")
	library = library and library:FindFirstChild("Traps")
	if not (T and T.Enabled and library) then return list end
	local k, S_ = MAP.Scale, Config.Studs
	local rng = Random.new(data.Seed + 49979687)

	local judge = Config.Judge
	local function Fewer(n: number): number
		if not (data.Judge and judge) or n <= 0 then return n end
		local x = n * judge.Traps
		local whole = math.floor(x)
		if x - whole > 0.5 or (x - whole == 0.5 and whole % 2 == 1) then whole += 1 end
		return math.max(whole, 1)
	end
	local length = data.Length
	local apart, clear, crestClear, pieceClear = T.Apart * k, T.Clear * k, T.CrestClear * k, T.PieceClear * k

	local function Free(kind: string, s: number, gap: number, reach: number): boolean
		if s < clear or s > length - clear then return false end
		if kind == "Spinner" then
			for _, dip in data.Dips do
				if math.abs(s - dip[1]) < crestClear then return false end
			end
		end
		for _, piece in data.Pieces do
			local from, to = if kind == "Spinner" then piece.Crest - pieceClear else piece.From, piece.To + (if kind == "Spinner" then pieceClear else 0)
			if s + reach > from and s - reach < to then return false end
		end
		for _, trap in list do
			if math.abs(s - trap.Along) < gap then return false end
		end
		return true
	end
	local function Reach(kind: string): number
		if kind == "Cage" then return (T.Cage.Scale[2] * 133 / S_) end
		if kind == "Lava" then return (T.Lava.Surge[2] + T.Lava.GroupGap) * k + 10 end
		return 4
	end
	local function Make(kind: string, s: number)
		local p, dir = data.PointAt(s)
		local axis = Vector3.new(dir.X, 0, dir.Z).Unit
		local right = Vector3.new(-axis.Z, 0, axis.X)
		local ground = data.Height(p.X, p.Z)
		local trap: any = { Kind = kind, Along = s, Id = (data.Seed % 100000) * 64 + #list + 1 }
		if kind == "Spinner" then
			local C = T.Spinner
			local asset = library:FindFirstChild(C.Assets[rng:NextInteger(1, #C.Assets)])
			if not asset then return end
			local arm = (asset:GetAttribute("Arm") or 150) / S_
			local hub = Vector3.new(p.X, ground + arm * C.Reach, p.Z)
			local cf = CFrame.lookAt(hub, hub + axis)
			local spokes = {}
			for deg in string.gmatch(asset:GetAttribute("Spokes") or "90,-90", "[^,]+") do
				table.insert(spokes, math.rad(tonumber(deg) or 0))
			end
			trap.Asset, trap.Hub, trap.Axis, trap.Right, trap.Up = asset.Name, hub, axis, cf.RightVector, cf.UpVector
			trap.Arm, trap.Spokes = arm, spokes
			trap.Omega = math.rad(rng:NextNumber(C.Speed[1], C.Speed[2])) * (if rng:NextNumber() < 0.5 then -1 else 1)
			trap.Phase, trap.Radius, trap.Cooldown = rng:NextNumber(0, math.pi * 2), C.Radius / S_, C.Cooldown
		elseif kind == "Cage" then
			local C = T.Cage
			local asset = library:FindFirstChild("Cage")
			if not asset then return end
			local scale = rng:NextNumber(C.Scale[1], C.Scale[2])
			local r = (asset:GetAttribute("Radius") or 130) * scale / S_
			local at = p + right * (rng:NextNumber(-1, 1) * C.Side * data.HalfWidth)
			local lift = rng:NextNumber(C.Lift[1], C.Lift[2])
			trap.Asset, trap.Scale, trap.R, trap.Low = "Cage", scale, r, lift < 0.6
			trap.Centre = Vector3.new(at.X, data.Height(at.X, at.Z) + r * lift, at.Z)
			trap.Tumble = Vector3.new(math.rad(C.Tumble[1]), math.rad(C.Tumble[2]), math.rad(C.Tumble[3])) * (0.7 + 0.6 * rng:NextNumber())
			trap.Phase, trap.Cooldown = rng:NextNumber(0, math.pi * 2), C.Cooldown
		else

			local C = T.Lava
			if not library:FindFirstChild("Lava") then return end
			local roll = rng:NextNumber()
			local combo = if roll < C.Combos.Cross then "Cross" elseif roll < C.Combos.Cross + C.Combos.Wave then "Wave" else "Single"
			local count = if combo == "Cross" then 2 elseif combo == "Wave" then 3 else 1
			local sway = rng:NextNumber(C.Sway[1], C.Sway[2]) * data.HalfWidth
			local swayRate = rng:NextNumber(C.Speed[1], C.Speed[2]) / S_ / sway
			local surge = if combo == "Single" then rng:NextNumber(C.Surge[1], C.Surge[2]) * k else 0
			local swayPhase, fire = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, C.Fire + C.Rest)
			for i = 1, count do
				local at = s + (if combo == "Wave" then (i - 2) * C.GroupGap * k elseif combo == "Cross" then (i - 1.5) * C.GroupGap * k else 0)
				local q, qdir = data.PointAt(at)
				local qaxis = Vector3.new(qdir.X, 0, qdir.Z).Unit
				local nozzle: any = { Kind = "Lava", Asset = "Lava", Along = at, Id = trap.Id * 4 + i, Combo = combo }
				nozzle.Drop = (C.Height + (if combo == "Cross" then (i - 1.5) * 30 else 0)) / S_
				nozzle.Base = Vector3.new(q.X, data.Height(q.X, q.Z) + nozzle.Drop, q.Z)
				nozzle.Right, nozzle.Axis = Vector3.new(-qaxis.Z, 0, qaxis.X), qaxis
				nozzle.Sway, nozzle.SwayRate, nozzle.Surge = sway, swayRate, surge
				nozzle.SurgeRate = swayRate * rng:NextNumber(0.3, 0.6)
				nozzle.SwayPhase = swayPhase + (if combo == "Cross" then (i - 1) * math.pi elseif combo == "Wave" then (i - 1) * math.pi * 2 / 3 else 0)
				nozzle.AzRate = math.rad(rng:NextNumber(C.Turn[1], C.Turn[2])) * (if rng:NextNumber() < 0.5 then -1 else 1)
				nozzle.Tilt = { math.rad(C.Tilt[1]), math.rad(C.Tilt[2]) }
				nozzle.Fire, nozzle.Rest, nozzle.Phase = C.Fire, C.Rest, fire
				nozzle.Radius, nozzle.Cooldown = C.Radius / S_, C.Cooldown
				table.insert(list, nozzle)
			end
			return
		end
		table.insert(list, trap)
	end
	local force = data.Force
	local only = if force == "spinners" or force == "lasers" then "Spinner" elseif force == "cages" then "Cage"
		elseif force == "lava" then "Lava" else nil
	if force == "missiles" then
		-- (the towers only: below)
	elseif only or force == "traps" or force == "all" then
		local kinds = { "Spinner", "Cage", "Lava" }
		for s = clear, length - clear, apart * 0.75 do   -- the whole line, closer than usual
			for _ = 1, 3 do
				local kind = only or kinds[1]
				local at, placed = s, false
				for _ = 1, 6 do   -- (nudged off a crest / a set piece)
					if Free(kind, at, apart * 0.6, Reach(kind)) then
						Make(kind, at)
						placed = true
						break
					end
					at += apart * 0.12
				end
				kinds = { kinds[2], kinds[3], kinds[1] }
				if placed or only then break end
			end
		end
	else

		local want = {}
		for _, kind in { "Spinner", "Cage", "Lava" } do
			local C = T[kind]
			want[kind] = Fewer(rng:NextInteger(C.Count[1], C.Count[2]))
		end
		local tries = 0
		while (want.Spinner + want.Cage + want.Lava) > 0 and tries < 600 do
			for _, kind in { "Spinner", "Cage", "Lava" } do
				if want[kind] > 0 then
					tries += 1
					local s = rng:NextNumber(clear, length - clear)
					if Free(kind, s, apart, Reach(kind)) then
						Make(kind, s)
						want[kind] -= 1
					end
				end
			end
		end
	end

	local MT = T.Missile
	local towerAsset = MT and library:FindFirstChild(MT.Asset)
	if towerAsset and not only then
		local mrng = Random.new(data.Seed + 86028121)
		local scale = MT.Scale or 1
		local tubes = {}
		local head = towerAsset:FindFirstChild("Head")
		for i = 1, 8 do
			local tube = head and head:FindFirstChild("Tube" .. i)
			if not tube then break end
			tubes[i] = towerAsset.WorldPivot:PointToObjectSpace(tube.WorldPosition) * scale / S_
		end
		local base = towerAsset:FindFirstChild("Base")
		local half = (if base then base.Size.X / 2 else 43) * scale / S_
		local w0, w1, step = MT.Window[1] * k, MT.Window[2] * k, MT.RowStep * k
		local wall_ = (MAP.Pieces and MAP.Pieces.Wall or 3) * k
		local function InCut(s: number): boolean
			for _, piece in data.Pieces do
				if s > piece.From - wall_ * 2 and s < piece.To + wall_ * 2 then return true end
			end
			return false
		end
		local towers = {}
		local function Tower(s: number): boolean
			if #tubes == 0 or s + w0 < clear or s > length - clear or InCut(s) then return false end
			for _, other in towers do
				if math.abs(other.Along - s) < MT.Apart * k then return false end
			end
			local rows = {}
			for a = s + w0, s + w1, step do
				if a > clear and a < length - clear and not InCut(a) then
					local p, dir = data.PointAt(a)
					local flat = Vector3.new(dir.X, 0, dir.Z).Unit
					local right = Vector3.new(-flat.Z, 0, flat.X)
					local points = {}
					for j = 1, MT.Lanes do
						local q = p + right * ((-1 + 2 * (j - 1) / (MT.Lanes - 1)) * MT.Spread * data.HalfWidth)
						points[j] = Vector3.new(q.X, data.Height(q.X, q.Z), q.Z)
					end
					table.insert(rows, { Along = a, Points = points })
				end
			end
			if #rows < 3 then return false end
			local p, dir = data.PointAt(s)
			local flat = Vector3.new(dir.X, 0, dir.Z).Unit
			local side = if mrng:NextNumber() < 0.5 then -1 else 1
			local at = p + Vector3.new(-flat.Z, 0, flat.X) * (side * (data.HalfWidth * MT.Side + half))

			local low = data.Height(at.X, at.Z)
			for _, o in { Vector3.new(half, 0, 0), Vector3.new(-half, 0, 0), Vector3.new(0, 0, half), Vector3.new(0, 0, -half) } do
				low = math.min(low, data.Height(at.X + o.X, at.Z + o.Z))
			end
			local foot = Vector3.new(at.X, math.max(low, data.Height(p.X, p.Z) - (MT.Drop or 40) / S_) - (MT.Sink or 0) / S_, at.Z)
			local reach = 0
			for _, row in rows do
				for _, q in row.Points do reach = math.max(reach, (q - foot).Magnitude) end
			end
			local interval = mrng:NextNumber(MT.Interval[1], MT.Interval[2])
			local trap = { Kind = "Missile", Asset = MT.Asset, Along = s, Id = (data.Seed % 100000) * 64 + 40 + #towers,
				Foot = foot, Scale = scale, Half = half, Tubes = tubes,
				Omega = math.rad(mrng:NextNumber(MT.Spin[1], MT.Spin[2])) * (if mrng:NextNumber() < 0.5 then -1 else 1),
				Phase = mrng:NextNumber(0, math.pi * 2), Interval = interval, Offset = mrng:NextNumber(0, interval),
				Stagger = MT.Stagger, Flight = MT.Flight, Arc = MT.Arc / S_, Rows = rows, Lanes = MT.Lanes,
				Radius = MT.Radius / S_, Blast = MT.Blast, Cooldown = MT.Cooldown, WindowTo = s + w1,
				Reach = reach + (MT.Radius + 10) / S_ }
			table.insert(towers, trap)
			table.insert(list, trap)
			return true
		end
		if force == "missiles" then
			for s = clear - w0, length - clear, MT.Apart * k * 0.5 do
				for _ = 1, 4 do   -- (nudged off a set piece)
					if Tower(s) then break end
					s += step
				end
			end
		else

			local want = if force == "traps" or force == "all" then MT.Count[2] else Fewer(mrng:NextInteger(MT.Count[1], MT.Count[2]))
			local from, to = clear - w0, length - clear
			local stretch = (to - from) / want
			for n = 0, want - 1 do
				for _ = 1, 8 do
					if Tower(from + stretch * (n + mrng:NextNumber(0.15, 0.85))) then break end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.Along < b.Along end)
	return list
end

local function Marker(name: string, at: Vector3 | CFrame, parent: Instance)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Transparency = 1
	part.Size = Vector3.one * 2
	part.CFrame = if typeof(at) == "CFrame" then at else CFrame.new(at)
	part.Parent = parent
	return part
end

local function FinishGate(data, parent: Instance)
	local gate = Config.Race and Config.Race.Gate
	if not (gate and data.Finish and data.PointAt and data.Height) then return end
	local CollectionService = game:GetService("CollectionService")
	local fin = data.Finish
	local _, way = data.PointAt(data.Line.Length)
	local flat = Vector3.new(way.X, 0, way.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local ground = Vector3.new(fin.X, data.Height(fin.X, fin.Z), fin.Z) * S
	local half = data.HalfWidth * S * gate.HalfWidth
	local height = 2 * half * gate.Height
	local frame = CFrame.lookAt(ground, ground + flat)
	local model = Instance.new("Model")
	model.Name = "Finish"
	CollectionService:AddTag(model, "SpeedCameraIgnore")
	local function Block(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size, p.CFrame, p.Color = size, cf, color
		p.Material = material or Enum.Material.Neon
		p.Transparency = transparency or 0
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local sink = 30
	local tall = height + gate.Beam + sink
	local pillars = {}
	for _, side in { -1, 1 } do
		local at = frame * CFrame.new(side * half, tall / 2 - sink, 0)
		pillars[side] = Block(if side < 0 then "PillarLeft" else "PillarRight", Vector3.new(gate.Pillar, tall, gate.Pillar), at, gate.Color)

		Block("Trim", Vector3.new(gate.Pillar * 0.18, tall, gate.Pillar * 1.04), at * CFrame.new(-side * gate.Pillar * 0.5, 0, 0), gate.Trim)
		Block("Cap", Vector3.new(gate.Pillar * 1.5, gate.Pillar * 0.5, gate.Pillar * 1.5), frame * CFrame.new(side * half, height + gate.Beam + gate.Pillar * 0.25, 0), gate.Trim)
	end

	local beam = Block("Beam", Vector3.new(2 * half + gate.Pillar, gate.Beam, gate.Pillar * 0.8), frame * CFrame.new(0, height + gate.Beam / 2, 0), gate.Panel or gate.Color, Enum.Material.SmoothPlastic)
	local band = gate.Beam * 0.12
	Block("BandLow", Vector3.new(2 * half + gate.Pillar, band, gate.Pillar * 0.86), frame * CFrame.new(0, height + band / 2, 0), gate.Color)
	Block("BandHigh", Vector3.new(2 * half + gate.Pillar, band, gate.Pillar * 0.86), frame * CFrame.new(0, height + gate.Beam - band / 2, 0), gate.Color)

	local across, drop = 2 * half - gate.Pillar, height + sink
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("Speed")
	vfx = vfx and vfx:FindFirstChild("VFX")
	local checker = vfx and vfx:FindFirstChild("FinishChecker")
	if checker and checker:IsA("Beam") then
		local ends = {}
		for i, side in { -1, 1 } do
			local a = Instance.new("Attachment")
			a.Name = "Checker"
			a.Parent = pillars[side]

			a.WorldCFrame = frame * CFrame.new(side * (half - gate.Pillar / 2), (height - sink) / 2, 0) * CFrame.Angles(0, math.pi / 2, 0)
			ends[i] = a
		end
		local beam = checker:Clone()
		beam.Name = "Checker"
		beam.Attachment0, beam.Attachment1 = ends[1], ends[2]
		beam.Width0, beam.Width1 = drop, drop
		local width0 = checker.Width0
		if beam.TextureMode == Enum.TextureMode.Stretch then

			local length = checker:GetAttribute("SourceLength") or across
			beam.TextureLength = math.max(1, math.round(checker.TextureLength * width0 / length * across / drop))
		else
			beam.TextureLength = checker.TextureLength * drop / width0   -- (Wrap / Static: studs a repeat)
		end
		beam.Parent = ends[1]
	else
		Block("Curtain", Vector3.new(across, drop, 0.4), frame * CFrame.new(0, (height - sink) / 2, 0), gate.Curtain, Enum.Material.ForceField)
		Block("CurtainGlow", Vector3.new(across, drop, 0.6), frame * CFrame.new(0, (height - sink) / 2, 0), gate.Curtain, Enum.Material.Neon, gate.Glow or 0.88)
	end
	-- FINISH on both faces of the beam
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Label" .. face.Name
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 1.5
		gui.LightInfluence = 0
		gui.Brightness = 1.5
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.7, 0.66)
		label.Text = gate.Text
		label.TextScaled = true
		label.TextColor3 = gate.Trim
		label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
		local stroke = Instance.new("UIStroke")
		stroke.Color = gate.Color
		stroke.Thickness = 3
		stroke.Parent = label
		label.Parent = gui
		gui.Parent = beam
	end
	model.Parent = parent
	return model
end

function Generated.MakeModel(data)
	local model = Instance.new("Model")

	model.Name = "Map_" .. data.Seed .. (if data.Force then "_" .. data.Force else "") .. (if data.Judge then "_judge" else "")
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("Heightfield", "Generated")
	model:SetAttribute("Seed", data.Seed)
	if data.Force then model:SetAttribute("Pieces", data.Force) end
	model:SetAttribute("Judge", data.Judge == true)
	model:SetAttribute("KillY", data.KillY)
	model:SetAttribute("VoidTop", data.VoidTop)
	model:SetAttribute("OpenEdges", true)
	model:SetAttribute("Length", data.Length)
	Marker("Start", data.Start, model)
	local waypoints = Instance.new("Folder")
	waypoints.Name = "Waypoints"
	for i, p in data.Waypoints do Marker(tostring(i), p, waypoints) end
	waypoints.Parent = model
	local laps = Instance.new("Folder")
	laps.Name = "Laps"
	for i, p in data.Gates do Marker(tostring(i), p, laps) end
	laps.Parent = model

	if data.RaceSlot then
		local grid = Instance.new("Folder")
		grid.Name = "Grid"
		for slot = 1, 12 do Marker(tostring(slot), data.RaceSlot(slot - 1), grid) end
		grid.Parent = model
	end
	FinishGate(data, model)
	return model
end

return Generated
