local RunnerPack = {}

RunnerPack.Size = 42

local FLAGS = { "Grounded", "MostlyGrounded", "Dive", "Slow", "FastRun", "Ball", "Bad" }
local BAD_FOR = 0.25
local Q = 32767
local WORLD = 1e6

local function I16(x: number): number
	return math.clamp(math.round(x), -32768, 32767)
end

local function I8(x: number): number
	return math.clamp(math.round(x * 127), -127, 127)
end

local function Quaternion(cf: CFrame): (number, number, number, number)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local x, y, z, w
	local trace = r00 + r11 + r22
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		w, x, y, z = 0.25 * s, (r21 - r12) / s, (r02 - r20) / s, (r10 - r01) / s
	elseif r00 > r11 and r00 > r22 then
		local s = math.sqrt(1 + r00 - r11 - r22) * 2
		w, x, y, z = (r21 - r12) / s, 0.25 * s, (r01 + r10) / s, (r02 + r20) / s
	elseif r11 > r22 then
		local s = math.sqrt(1 + r11 - r00 - r22) * 2
		w, x, y, z = (r02 - r20) / s, (r01 + r10) / s, 0.25 * s, (r12 + r21) / s
	else
		local s = math.sqrt(1 + r22 - r00 - r11) * 2
		w, x, y, z = (r10 - r01) / s, (r02 + r20) / s, (r12 + r21) / s, 0.25 * s
	end
	if w < 0 then x, y, z, w = -x, -y, -z, -w end
	return x, y, z, w
end

function RunnerPack.Write(b: buffer, at: number, s)
	local p, v = s.Position, s.Velocity
	buffer.writef64(b, at, s.T)
	buffer.writef32(b, at + 8, p.X)
	buffer.writef32(b, at + 12, p.Y)
	buffer.writef32(b, at + 16, p.Z)
	buffer.writei16(b, at + 20, I16(v.X * 10))
	buffer.writei16(b, at + 22, I16(v.Y * 10))
	buffer.writei16(b, at + 24, I16(v.Z * 10))
	local qx, qy, qz, qw = Quaternion(s.Rotation)
	buffer.writei16(b, at + 26, I16(qx * Q))
	buffer.writei16(b, at + 28, I16(qy * Q))
	buffer.writei16(b, at + 30, I16(qz * Q))
	buffer.writei16(b, at + 32, I16(qw * Q))
	buffer.writeu16(b, at + 34, math.round(((s.Yaw or 0) / 360) % 1 * 65536) % 65536)
	buffer.writeu16(b, at + 36, math.clamp(math.round((s.TimeScale or 1) * 1000), 0, 65535))
	buffer.writeu8(b, at + 38, (s.Spawn or 0) % 256)
	local flags = 0
	for i, name in FLAGS do
		if s[name] then flags += 2 ^ (i - 1) end
	end
	buffer.writeu8(b, at + 39, flags)
	buffer.writei8(b, at + 40, I8(s.InputX or 0))
	buffer.writei8(b, at + 41, I8(s.InputY or 0))
end

function RunnerPack.Read(b: buffer, at: number)
	local qx, qy, qz, qw = buffer.readi16(b, at + 26) / Q, buffer.readi16(b, at + 28) / Q, buffer.readi16(b, at + 30) / Q, buffer.readi16(b, at + 32) / Q
	local length = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	local rotation = if length > 1e-4 then CFrame.new(0, 0, 0, qx / length, qy / length, qz / length, qw / length) else CFrame.identity
	local yaw = buffer.readu16(b, at + 34) / 65536 * 360
	if yaw > 180 then yaw -= 360 end
	local flags = buffer.readu8(b, at + 39)
	local s = {
		T = buffer.readf64(b, at),
		Position = Vector3.new(buffer.readf32(b, at + 8), buffer.readf32(b, at + 12), buffer.readf32(b, at + 16)),
		Velocity = Vector3.new(buffer.readi16(b, at + 20), buffer.readi16(b, at + 22), buffer.readi16(b, at + 24)) / 10,
		Rotation = rotation,
		Yaw = yaw,
		TimeScale = buffer.readu16(b, at + 36) / 1000,
		Spawn = buffer.readu8(b, at + 38),
		InputX = buffer.readi8(b, at + 40) / 127,
		InputY = buffer.readi8(b, at + 41) / 127,
	}
	for i, name in FLAGS do
		s[name] = bit32.btest(flags, 2 ^ (i - 1))
	end
	return s
end

function RunnerPack.Encode(s): buffer
	local b = buffer.create(RunnerPack.Size)
	RunnerPack.Write(b, 0, s)
	return b
end

function RunnerPack.Finite(s): boolean
	local t, p = s.T, s.Position
	if t ~= t or math.abs(t) > 1e12 then return false end
	for _, x in { p.X, p.Y, p.Z } do
		if x ~= x or math.abs(x) > WORLD then return false end
	end
	return true
end

function RunnerPack.SetTimeScale(b: buffer, at: number, scale: number)
	buffer.writeu16(b, at + 36, math.clamp(math.round(scale * 1000), 0, 65535))
end

function RunnerPack.JustBad(sim: any): boolean
	local landing = sim.lastLanding
	return landing ~= nil and landing.kind == "Bad" and os.clock() - (landing.time or 0) < BAD_FOR
end

return RunnerPack
