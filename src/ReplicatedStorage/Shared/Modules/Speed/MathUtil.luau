local MathUtil = {}

local ZERO = Vector3.zero

function MathUtil.clamp01(x)
	return math.clamp(x, 0, 1)
end

function MathUtil.lerp(a, b, t)
	return a + (b - a) * t
end

function MathUtil.invLerp(a, b, x)
	if a == b then
		return 0
	end
	return math.clamp((x - a) / (b - a), 0, 1)
end

function MathUtil.moveTowards(current, target, maxDelta)
	if math.abs(target - current) <= maxDelta then
		return target
	end
	return current + math.sign(target - current) * maxDelta
end

function MathUtil.lerpV(a, b, t)
	t = math.clamp(t, 0, 1)
	return a + (b - a) * t
end

function MathUtil.expAlpha(rate, dt)
	return 1 - math.exp(-rate * dt)
end

function MathUtil.unit(v)
	local mag = v.Magnitude
	if mag < 1e-5 then
		return ZERO
	end
	return v / mag
end

function MathUtil.flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

function MathUtil.projectOnPlane(v, normal)
	local n = MathUtil.unit(normal)
	return v - n * v:Dot(n)
end

function MathUtil.angle(a, b)
	local ma, mb = a.Magnitude, b.Magnitude
	if ma < 1e-5 or mb < 1e-5 then
		return 0
	end
	return math.deg(math.acos(math.clamp(a:Dot(b) / (ma * mb), -1, 1)))
end

function MathUtil.reflect(v, normal)
	return v - normal * (2 * v:Dot(normal))
end

function MathUtil.rotateTowards(current, target, maxRadians)
	local mag = current.Magnitude
	if mag < 1e-5 or target.Magnitude < 1e-5 then
		return current
	end
	local cu, tu = current / mag, target.Unit
	local ang = math.acos(math.clamp(cu:Dot(tu), -1, 1))
	if ang <= maxRadians then
		return tu * mag
	end
	local axis = cu:Cross(tu)
	if axis.Magnitude < 1e-6 then
		axis = math.abs(cu.Y) < 0.99 and cu:Cross(Vector3.yAxis) or cu:Cross(Vector3.xAxis)
	end
	return CFrame.fromAxisAngle(axis.Unit, maxRadians):VectorToWorldSpace(current)
end

function MathUtil.easeInOut(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function MathUtil.signedAngle(a, b, axis)
	local ang = MathUtil.angle(a, b)
	if a:Cross(b):Dot(axis) < 0 then
		return -ang
	end
	return ang
end

return MathUtil
