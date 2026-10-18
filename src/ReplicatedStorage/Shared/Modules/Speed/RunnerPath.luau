local RunnerPath = {}

function RunnerPath.At(list, t: number, extrapolate: number)
	local n = #list
	if n == 0 then return nil, nil, nil, 0 end
	local newest = list[n]
	if t >= newest.T then
		local ahead = math.min(t - newest.T, extrapolate)
		return newest.Position + newest.Velocity * (newest.TimeScale * ahead), newest, newest, 0
	end
	local oldest = list[1]
	if t <= oldest.T then return oldest.Position, oldest, oldest, 0 end
	for i = n - 1, 1, -1 do
		local a = list[i]
		if a.T <= t then
			local b = list[i + 1]
			if a.Spawn ~= b.Spawn then return a.Position, a, a, 0 end
			local h = math.max(b.T - a.T, 1e-4)
			local k = (t - a.T) / h
			local va, vb = a.Velocity * a.TimeScale, b.Velocity * b.TimeScale
			local k2, k3 = k * k, k * k * k
			local h00, h10, h01, h11 = 2 * k3 - 3 * k2 + 1, k3 - 2 * k2 + k, -2 * k3 + 3 * k2, k3 - k2
			return a.Position * h00 + va * (h10 * h) + b.Position * h01 + vb * (h11 * h), a, b, k
		end
	end
	return oldest.Position, oldest, oldest, 0
end

function RunnerPath.Rotation(from, to, k: number): CFrame
	if from == to or k <= 0 then return from.Rotation end
	return from.Rotation:Lerp(to.Rotation, k)
end

function RunnerPath.Yaw(from, to, k: number): number
	local turn = (to.Yaw - from.Yaw + 180) % 360 - 180
	return from.Yaw + turn * k
end

return RunnerPath
