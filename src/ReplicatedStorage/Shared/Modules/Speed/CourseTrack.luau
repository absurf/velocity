local CourseTrack = {}
CourseTrack.__index = CourseTrack

local WINDOW = 6
local REACH = 150

local function Numbered(folder: Instance?): { Vector3 }
	local list = {}
	for _, part in if folder then folder:GetChildren() else {} do
		local n = tonumber(part.Name)
		if n and part:IsA("BasePart") then table.insert(list, { n, part.Position }) end
	end
	table.sort(list, function(a, b) return a[1] < b[1] end)
	local points = {}
	for _, entry in list do table.insert(points, entry[2]) end
	return points
end

local function OnSegment(a: Vector3, b: Vector3, p: Vector3): (number, number)
	local ab = b - a
	local length2 = ab:Dot(ab)
	local k = if length2 > 1e-6 then math.clamp((p - a):Dot(ab) / length2, 0, 1) else 0
	return (p - (a + ab * k)).Magnitude, k
end

function CourseTrack.new(course: Instance?)
	if not course then return nil end
	local points = {}
	local start = course:FindFirstChild("Start")
	if start and start:IsA("BasePart") then table.insert(points, start.Position) end
	for _, point in Numbered(course:FindFirstChild("Waypoints")) do table.insert(points, point) end
	if #points < 2 then return nil end
	local self = setmetatable({ Course = course, Name = course.Name, Points = points, Along = { 0 } }, CourseTrack)
	for i = 2, #points do self.Along[i] = self.Along[i - 1] + (points[i] - points[i - 1]).Magnitude end
	self.Length = self.Along[#points]
	self.LapEnds = {}
	for _, gate in Numbered(course:FindFirstChild("Laps")) do table.insert(self.LapEnds, (self:Progress(gate))) end
	table.sort(self.LapEnds)
	self.Laps = math.max(math.floor(tonumber(course:GetAttribute("Laps")) or 0), #self.LapEnds + 1)
	return self
end

function CourseTrack:Progress(position: Vector3, hint: number?): (number, number, number)
	local points, along = self.Points, self.Along
	local last = #points - 1
	local function search(from: number, to: number)
		local best, bestI, bestK = math.huge, 1, 0
		for i = math.max(from, 1), math.min(to, last) do
			local d, k = OnSegment(points[i], points[i + 1], position)
			if d < best then best, bestI, bestK = d, i, k end
		end
		return best, bestI, bestK
	end
	local d, i, k
	if hint then
		d, i, k = search(hint - WINDOW, hint + WINDOW)
		if d > REACH then d, i, k = search(1, last) end
	else
		d, i, k = search(1, last)
	end
	return along[i] + (along[i + 1] - along[i]) * k, i, d
end

function CourseTrack:PointAt(along: number): (Vector3, Vector3)
	local points, at = self.Points, self.Along
	along = math.clamp(along, 0, self.Length)
	for i = 1, #points - 1 do
		if at[i + 1] >= along then
			local span = math.max(at[i + 1] - at[i], 1e-6)
			local way = points[i + 1] - points[i]
			return points[i] + way * ((along - at[i]) / span), if way.Magnitude > 1e-6 then way.Unit else Vector3.zAxis
		end
	end
	local n = #points
	return points[n], (points[n] - points[n - 1]).Unit
end

function CourseTrack:Lap(along: number): number
	local lap = 1
	for _, ends in self.LapEnds do
		if along >= ends then lap += 1 end
	end
	return math.min(lap, self.Laps)
end

function CourseTrack:Finished(along: number, reach: number): boolean
	return along >= self.Length - reach
end

return CourseTrack
