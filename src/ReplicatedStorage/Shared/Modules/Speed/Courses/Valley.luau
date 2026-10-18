local Valley = {}

Valley.Origin = Vector2.new(2600, -3400)
Valley.Size = Vector2.new(360, 3440)
Valley.Spacing = 500 / 255
Valley.Length = 3300
Valley.CenterX = 2780
Valley.Top = 1400 -- units (3500 studs)

Valley.WallWidth = 60
Valley.WallHeight = 80

local function smooth01(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function band(s, a, b, fade)
	return smooth01((s - a) / fade) * (1 - smooth01((s - b) / fade))
end

-- road centre line (x) as a function of s
function Valley.centerX(s)
	return Valley.CenterX + 55 * math.sin(s / 260) + 22 * math.sin(s / 105 + 1.3)
end

local function profile(s)
	local y = Valley.Top

	y -= 0.22 * s + 22 * math.sin(s / 170) + 12 * math.sin(s / 61)
	-- start flat
	y += 0.22 * (60 - math.min(s, 60)) * 0
	return y
end

local function kicker(s, s0, rampLen, h)
	local lip = math.max(6, h * 0.55)
	if s < s0 - rampLen or s > s0 + lip then return 0 end
	if s <= s0 then
		return h * smooth01((s - (s0 - rampLen)) / rampLen)
	end
	return h * (1 - smooth01((s - s0) / lip))
end

local function drop(s, s0, width, depth)
	return -depth * smooth01((s - s0) / width)
end

local FEATURES = {
	kickers = { { 420, 40, 9 }, { 900, 55, 14 }, { 1750, 40, 10 }, { 2700, 70, 22 } },
	drops = { { 940, 45, 60 }, { 2740, 70, 120 } },
}

function Valley.height(x, z)
	local s = -z
	local xc = Valley.centerX(s)
	local d = x - xc
	local ad = math.abs(d)
	local y = profile(s)
	for _, k in ipairs(FEATURES.kickers) do y += kicker(s, k[1], k[2], k[3]) end
	for _, dr in ipairs(FEATURES.drops) do y += drop(s, dr[1], dr[2], dr[3]) end

	y += 9 * math.sin((s - 1150) / 42) * band(s, 1150, 1600, 40)

	local road = 0.0045 * d * d * (1 - smooth01((ad - 28) / 10)) + 0.0045 * 28 * 28 * smooth01((ad - 28) / 10)
	local rim = 20 * smooth01((ad - 30) / 45)
	local hills = (math.noise(x / 70, z / 70, 0.37) * 28 + math.noise(x / 23, z / 23, 4.1) * 6) * smooth01((ad - 45) / 60)
	local normalLat = road + rim + hills

	local hp = band(s, 1950, 2450, 60)
	local u = math.min(ad / 60, 1)
	local halfpipe = 48 * (1 - math.cos(u * math.pi / 2)) + math.min(math.max(ad - 60, 0), 50) * 0.9 + hills * 0.4
	y += normalLat + (halfpipe - normalLat) * hp
	-- moguls on the road (s 2500..2650)
	y += 3.2 * math.sin(s / 7.5) * math.sin(d / 8) * band(s, 2500, 2650, 25) * (1 - smooth01((ad - 25) / 10))
	-- finish: flatten the last stretch
	local fin = smooth01((s - (Valley.Length - 150)) / 80)
	if fin > 0 then
		local yFlat = profile(Valley.Length - 150) - 180 -- after both drops (60 + 120)
		y = y + (yFlat + road + rim - y) * fin
	end
	local edge = math.min(x - Valley.Origin.X, Valley.Origin.X + Valley.Size.X - x, z - Valley.Origin.Y)
	if edge < Valley.WallWidth then
		local k = 1 - math.max(edge, 0) / Valley.WallWidth
		y += Valley.WallHeight * k * k
	end
	return y
end

return Valley
