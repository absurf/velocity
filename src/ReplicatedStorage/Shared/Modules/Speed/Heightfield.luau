local Heightfield = {}
Heightfield.__index = Heightfield

function Heightfield.new(def)
	local self = setmetatable({}, Heightfield)
	self.ox, self.oz = def.origin.X, def.origin.Y
	self.sp = def.spacing
	self.nx = math.floor(def.size.X / def.spacing) + 1
	self.nz = math.floor(def.size.Y / def.spacing) + 1
	self.heightFn = def.height
	self.buf = buffer.create(self.nx * self.nz * 4)
	self.ready = false
	return self
end

function Heightfield:Build(yieldEvery)
	local nx, sp, ox, oz, fn, buf = self.nx, self.sp, self.ox, self.oz, self.heightFn, self.buf
	for j = 0, self.nz - 1 do
		local z = oz + j * sp
		local base = j * nx
		for i = 0, nx - 1 do
			buffer.writef32(buf, (base + i) * 4, fn(ox + i * sp, z))
		end
		if yieldEvery and j % yieldEvery == 0 then
			self.progress = (j + 1) / self.nz
			task.wait()
		end
	end
	self.progress = 1
	self.ready = true
end

function Heightfield:vertex(i, j)
	return buffer.readf32(self.buf, (j * self.nx + i) * 4)
end

function Heightfield:Sample(x, z)
	local fx = (x - self.ox) / self.sp
	local fz = (z - self.oz) / self.sp
	local i, j = math.floor(fx), math.floor(fz)
	if i < 0 or j < 0 or i >= self.nx - 1 or j >= self.nz - 1 then
		return nil
	end
	local u, v = fx - i, fz - j
	local h00 = self:vertex(i, j)
	local h10 = self:vertex(i + 1, j)
	local h01 = self:vertex(i, j + 1)
	local h11 = self:vertex(i + 1, j + 1)
	local sp = self.sp
	local y, a, b -- a = dy/dx, b = dy/dz (per unit)
	if u >= v then
		y = h00 + u * (h10 - h00) + v * (h11 - h10)
		a, b = (h10 - h00) / sp, (h11 - h10) / sp
	else
		y = h00 + v * (h01 - h00) + u * (h11 - h01)
		a, b = (h11 - h01) / sp, (h01 - h00) / sp
	end
	return y, Vector3.new(-a, 1, -b).Unit
end

function Heightfield:Raycast(from, to)
	if not self.ready then return nil end
	local d = to - from
	local len = d.Magnitude
	if len < 1e-6 then return nil end
	local flatLen = math.sqrt(d.X * d.X + d.Z * d.Z)
	if flatLen < 1e-4 then
		-- vertical ray: exact
		local h, n = self:Sample(from.X, from.Z)
		if not h then return nil end
		local y0, y1 = from.Y, to.Y
		if (y0 >= h and y1 <= h) then
			local p = Vector3.new(from.X, h, from.Z)
			return { position = p, normal = n, distance = math.abs(y0 - h) }
		end
		return nil
	end
	local steps = math.max(1, math.ceil(flatLen / (self.sp * 0.5)))
	local prev = from
	local hPrev = self:Sample(prev.X, prev.Z)
	local prevAbove = hPrev ~= nil and prev.Y >= hPrev
	for k = 1, steps do
		local p = from + d * (k / steps)
		local h = self:Sample(p.X, p.Z)
		local above = h ~= nil and p.Y >= h
		if h and prevAbove and not above then

			local lo, hi = prev, p
			for _ = 1, 10 do
				local mid = (lo + hi) / 2
				local hm = self:Sample(mid.X, mid.Z)
				if hm and mid.Y >= hm then lo = mid else hi = mid end
			end
			local hy, n = self:Sample(lo.X, lo.Z)
			local hitPos = Vector3.new(lo.X, hy or lo.Y, lo.Z)
			return { position = hitPos, normal = n, distance = (hitPos - from).Magnitude }
		end
		prev, prevAbove = p, above
	end
	return nil
end

return Heightfield
