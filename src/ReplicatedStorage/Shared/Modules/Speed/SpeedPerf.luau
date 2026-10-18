local SpeedPerf = {}

local names: { string } = {}
local starts: { number } = {}
local depth = 0
local frame: { [string]: number } = {}       -- this frame's time (s) or count per name
local window = { frames = 0, sum = {} :: { [string]: number }, max = {} :: { [string]: number }, started = os.clock() }
local report: { [string]: { ms: number, max: number } } = {}
local SPIKE_MS, SPIKE_KEEP = 30, 12
local spikes = {}
local previous: { [string]: number } = {}

function SpeedPerf.Begin(name: string)
	debug.profilebegin(name)
	depth += 1
	names[depth], starts[depth] = name, os.clock()
end

function SpeedPerf.End()
	debug.profileend()
	if depth == 0 then return end
	local name = names[depth]
	frame[name] = (frame[name] or 0) + (os.clock() - starts[depth])
	depth -= 1
end

function SpeedPerf.Count(name: string, n: number?)
	frame[name] = (frame[name] or 0) + (n or 1)
end

function SpeedPerf.Frame()

	local long = frame.Frame
	if long and long * 1000 >= SPIKE_MS then
		local sections = {}
		for name, value in previous do
			if name:sub(1, 1) ~= "#" then sections[name] = math.floor(value * 100000) / 100 end
		end
		table.insert(spikes, { At = os.clock(), Ms = math.floor(long * 1000), Sections = sections })
		if #spikes > SPIKE_KEEP then table.remove(spikes, 1) end
	end
	table.clear(previous)
	for name, value in frame do
		if name ~= "Frame" then previous[name] = value end
	end
	window.frames += 1
	for name, value in frame do
		window.sum[name] = (window.sum[name] or 0) + value
		if value > (window.max[name] or 0) then window.max[name] = value end
	end
	table.clear(frame)
	local now = os.clock()
	if now - window.started >= 1 then
		table.clear(report)
		for name, sum in window.sum do

			local scale = if name:sub(1, 1) == "#" then 1 else 1000
			report[name] = { ms = math.floor(sum / window.frames * scale * 100) / 100, max = math.floor((window.max[name] or 0) * scale * 100) / 100 }
		end
		report["#frames"] = { ms = window.frames, max = window.frames }
		window.frames, window.started = 0, now
		table.clear(window.sum)
		table.clear(window.max)
	end
end

function SpeedPerf.Report()
	return report
end

function SpeedPerf.Spikes()
	return spikes
end

return SpeedPerf
