local RunService = game:GetService("RunService")

local Perf = {}

Perf.Enabled = false
Perf.ThresholdMs = 4

local SIDE = RunService:IsServer() and "S" or "C"

function Perf.Time(label: string, fn, ...)
	if not Perf.Enabled then return fn(...) end
	local t0 = os.clock()
	local results = table.pack(fn(...))
	local ms = (os.clock() - t0) * 1000
	if ms >= Perf.ThresholdMs then
		warn(string.format("[Perf %s] %s took %.1f ms", SIDE, label, ms))
	end
	return table.unpack(results, 1, results.n)
end

function Perf.Wrap(label: string, fn)
	return function(...)
		return Perf.Time(label, fn, ...)
	end
end

return Perf
