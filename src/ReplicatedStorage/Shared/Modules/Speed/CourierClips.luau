local Clips = {}
Clips.__index = Clips

local cache = {}

function Clips.new(folder)
	local data = cache[folder]
	if not data then
		data = {}
		cache[folder] = data
	end
	return setmetatable({ folder = folder, data = data }, Clips)
end

function Clips:Get(name)
	local d = self.data[name]
	if d ~= nil then return d or nil end
	local kfs = self.folder:FindFirstChild(name)
	if not kfs then self.data[name] = false return nil end
	local keys = kfs:GetKeyframes()
	table.sort(keys, function(a, b) return a.Time < b.Time end)
	local joints, times = {}, {}
	for i, k in ipairs(keys) do
		times[i] = k.Time
		local function walk(p)
			for _, c in ipairs(p:GetChildren()) do
				if c:IsA("Pose") then
					if c.Name ~= "HumanoidRootPart" then
						local arr = joints[c.Name]
						if not arr then arr = {}; joints[c.Name] = arr end
						arr[i] = c.CFrame
					end
					walk(c)
				end
			end
		end
		walk(k)
	end

	for _, arr in pairs(joints) do
		local last = CFrame.identity
		for i = 1, #keys do
			if arr[i] then last = arr[i] else arr[i] = last end
		end
	end
	local n = #keys
	local length = n > 0 and keys[n].Time or 0
	d = { n = n, times = times, length = math.max(length, 1 / 60), loop = kfs.Loop, joints = joints,
		step = n > 1 and (length / (n - 1)) or (1 / 60) }
	self.data[name] = d
	return d
end

function Clips:Length(name)
	local d = self:Get(name)
	return d and d.length or 1
end

function Clips:Loops(name)
	local d = self:Get(name)
	return d and d.loop or false
end

function Clips:Accumulate(name, t, w, acc, wsum)
	local d = self:Get(name)
	if not d or d.n == 0 or w <= 1e-4 then return end
	local f = t / d.step
	local i0 = math.clamp(math.floor(f), 0, d.n - 1)
	local i1 = math.min(i0 + 1, d.n - 1)
	local a = math.clamp(f - i0, 0, 1)
	for joint, frames in pairs(d.joints) do
		local cf = frames[i0 + 1]
		if a > 0 then cf = cf:Lerp(frames[i1 + 1], a) end
		local ws = (wsum[joint] or 0) + w
		if ws == w then acc[joint] = cf else acc[joint] = acc[joint]:Lerp(cf, w / ws) end
		wsum[joint] = ws
	end
end

return Clips
