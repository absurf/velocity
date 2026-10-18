local Graph = {}
Graph.__index = Graph

local P = "New_Courier_"
local function C(name, ts) return { clip = P .. name, ts = ts or 1 } end
local function D1(param, children) return { kind = "1D", param = param, children = children } end -- { {thr, node} }
local function D2(kind, children) return { kind = kind, children = children } end -- { {x, y, node} }

local idle = D1("Speed", { { 0, C("Idle") }, { 1, C("Idle_Combat") } })

local function grounded(p) return p.IsGrounded end
local function air(p) return not p.IsGrounded end

local STATES = {
	SlowMovement = {
		motion = D2("Freeform", {
			{ 0, 0.25, C("Walk") }, { 0, 1, C("Jog") }, { -0.3, 0, C("Jog_L") }, { 0.3, 0, C("Jog_R") },
			{ 0, 0, idle }, { 0.1, 0, idle }, { -0.1, 0, idle }, { 0, 0.01, idle },
		}),
		go = {
			{ to = "DashStart", when = function(p) return p.ChargeRun end, dur = 0.165 },
			{ to = "Running", when = function(p) return p.Running end, dur = 0.173 },
		},
	},
	DashStart = { motion = C("Dash_Start_New_Start"), go = {
		{ to = "DashTransition", when = function(p) return p.Running end, dur = 0 },
		{ to = "IdleReturn", when = function(p) return not p.ChargeRun and not p.Running end, dur = 0 },
	} },
	DashTransition = { motion = C("Dash_Start_New_Transition"), go = { { to = "Running", exit = 0.6156, dur = 0.128 } } },
	Running = {
		motion = D2("Freeform", {
			{ 1, 0, D1("Speed", { { 0, C("Jog_R 1", 1.5) }, { 2, C("Dash_Loop_R", 2) } }) },
			{ -1, 0, D1("Speed", { { 0, C("Jog_L 1", 1.5) }, { 2, C("Dash_Loop_L", 2) } }) },
			{ -1, 1, C("Jog_L 1", 1.5) },
			{ 1, 1, C("Jog_R 1", 1.5) },
			{ -0.5, 0, C("Jog_L 1", 1.5) },
			{ 0.5, 0, C("Jog_R 1", 1.5) },
			{ 0, 1, D1("Confidence", {
				{ 0, D1("Speed", { { 0, C("Dash_Loop_Unsure", 1.5) }, { 1, C("Dash_MediumConfidence", 2) } }) },
				{ 1, D1("Speed", { { 0, C("Dash_Loop", 1.5) }, { 2, C("Dash_Loop_Velocity", 2) } }) },
			}) },
			{ 0, -1, D1("Speed", { { 0, C("Dash_Skis", 2) }, { 2, C("Dash_Loop", 3) } }) },
			{ 0, 0, D1("Confidence", { { 0, C("Dash_Loop_Unsure", 1.5) }, { 0.5, C("Dash_MediumConfidence", 1.5) }, { 1, C("Dash_Loop", 1) } }) },
		}),
		go = {
			{ to = "DashStop", when = function(p) return not p.Running end, dur = 0.040 },
			{ to = "Flying", when = air, dur = 0.160 },
		},
	},
	DashStop = { motion = C("Dash_Stop"), go = { { to = "DashStopLoop", exit = 0.332, dur = 0.334 } } },
	DashStopLoop = { motion = D1("Speed", { { 0, C("Dash_Stop_Loop_0") }, { 1, C("Dash_Stop_Loop_1") } }), go = {
		{ to = "IdleReturn", when = function(p) return p.Speed < 0.25 end, dur = 0.073 },
		{ to = "DashStart", when = function(p) return p.ChargeRun end, dur = 0.057 },
		{ to = "IdleReturn", when = function(p) return not p.ChargeRun end, dur = 0 },
	} },
	IdleReturn = { motion = C("IdleReturn"), go = { { to = "SlowMovement", exit = 0.2617, dur = 0.492 } } },
	Flying = {
		motion = D2("Simple", {
			{ 0, 0, D1("Speed", { { 0, C("Fly_New_0", 1) }, { 1, C("Fly_New_0", 2) } }) },
			{ 0, 1, D1("Speed", { { 0, C("Fly_New_Fwd") }, { 1, C("Fly_New_Fwd_Velocity") } }) },
			{ 0, -1, D1("RelX", { { 0, C("Fly_New_Bck", 1) }, { 1, C("Fly_New_Bck", 2) } }) },
			{ 1, 0, D1("Speed", { { 0, C("Fly_Slight_R") }, { 0.5, C("Fly_New_Turn_R") }, { 1, C("Fly_New_Turn_RExtra") } }) },

			{ -1, 0, D1("RelX", { { 0, C("Fly_Slight_L") }, { 0.5, C("Fly_New_Turn_L") }, { 1, C("Fly_New_Turn_LExtra") } }) },
		}),
		go = {
			{ to = "Running", when = grounded, dur = 0.164 },
			{ to = "FastFallStart", when = function(p) return p.FastFall end, dur = 0.081 },
		},
	},
	FastFallStart = { motion = C("FastFall_Start"), go = {
		{ to = "FastFallLoop", exit = 0.229, dur = 1.145 },
		{ to = "FastFallLand", when = grounded, dur = 0 },
		{ to = "FastFallEnd", when = function(p) return not p.FastFall end, dur = 0 },
	} },
	FastFallLoop = {
		motion = D2("Simple", {
			{ 0, 1, C("FastFall_Loop") }, { 0, 0, C("FastFall_Loop_Down") }, { -1, 0, C("FastFall_Loop_Turn_L") },
			{ 1, 0, C("FastFall_Loop_Turn_R") }, { 0, -2, C("Fly_0") },
		}),
		go = {
			{ to = "FastFallLand", when = grounded, dur = 0.076 },
			{ to = "FastFallEnd", when = function(p) return not p.FastFall end, dur = 0 },
		},
	},
	FastFallEnd = { motion = C("FastFall_End"), go = {
		{ to = "FastFallLand", when = grounded, dur = 0.074 },
		{ to = "Flying", exit = 0.353, dur = 0.636 },
	} },
	FastFallLand = { motion = C("FastFall_Land"), go = { { to = "Running", exit = 0.735, dur = 0.154 } } },
	Jump1 = { motion = C("JumpType_1"), go = { { to = "Flying", exit = 0.365, dur = 1.281 }, { to = "Running", when = grounded, dur = 0.25 } } },
	Jump2L = { motion = C("JumpType_2_L"), go = { { to = "Flying", exit = 0.391, dur = 1.516 }, { to = "Running", when = grounded, dur = 0.25 } } },
	Jump2R = { motion = C("JumpType_2_R"), go = { { to = "Flying", exit = 0.370, dur = 1.223 }, { to = "Running", when = grounded, dur = 0.25 } } },
	Jump3 = { motion = C("JumpType_3"), go = { { to = "Flying", exit = 0.494, dur = 0.674 }, { to = "Running", when = grounded, dur = 0.25 } } },
	Jump4 = { motion = C("JumpType_4"), go = { { to = "Flying", exit = 0.495, dur = 1.010 }, { to = "Running", when = grounded, dur = 0.25 } } },
	FlyStart = { motion = C("Fly_New_Start"), go = { { to = "Flying", exit = 0.4, dur = 0.463 }, { to = "Running", when = grounded, dur = 0.176 } } },
	Land1 = { motion = C("Dash_LandType1"), go = { { to = "Running", exit = 0.5, dur = 0.25 } } },
	Land3 = { motion = D1("Speed", { { 0, C("Dash_LandType3", 1) }, { 1, C("Dash_LandType3", 2) } }), go = { { to = "Running", exit = 0.7406, dur = 0.130 } } },
	Land4 = { motion = D1("Speed", { { 0, C("Dash_LandType4", 1) }, { 1, C("Dash_LandType4", 1.5) } }), go = { { to = "Land3", exit = 1, dur = 0 } } },
	DamageAirR = { motion = C("Fly_New_Damage_R"), go = { { to = "Flying", exit = 0.384, dur = 0.821 }, { to = "FastFallLand", when = grounded, dur = 0 } } },
	DamageAirM = { motion = C("Fly_New_Damage_M"), go = { { to = "Flying", exit = 0.551, dur = 0.715 }, { to = "FastFallLand", when = grounded, dur = 0 } } },
	DamageAirL = { motion = C("Fly_New_Damage_L"), go = { { to = "Flying", exit = 0.501, dur = 0.666 }, { to = "FastFallLand", when = grounded, dur = 0 } } },

	DamageGround = { motion = C("DamageGrounded_R"), go = { { to = "Running", exit = 0.885, dur = 0.206 } } },
}

local ANY = {
	{ to = "Jump1", when = function(p) return p.JumpType == 2 end, dur = 0.108 },
	{ to = "Jump3", when = function(p) return p.JumpType == 3 end, dur = 0.113 },
	{ to = "Jump2L", when = function(p) return p.JumpType == 1 and p.AltJump end, dur = 0.159 },
	{ to = "Jump4", when = function(p) return p.JumpType == 4 end, dur = 0.110 },
	{ to = "FlyStart", when = function(p) return p.JumpType == 0 end, dur = 0.107 },
	{ to = "Jump2R", when = function(p) return p.JumpType == 1 and not p.AltJump end, dur = 0.151 },
	{ to = "DamageAirR", when = function(p) return p.Damaged and not p.IsGrounded and p.DamageDirX > 0.5 end, dur = 0 },
	{ to = "DamageAirM", when = function(p) return p.Damaged and not p.IsGrounded and math.abs(p.DamageDirX) < 0.5 end, dur = 0 },
	{ to = "DamageAirL", when = function(p) return p.Damaged and not p.IsGrounded and p.DamageDirX < -0.5 end, dur = 0 },
	{ to = "DamageGround", when = function(p) return p.Damaged and p.IsGrounded end, dur = 0 },
}

function Graph.ClipNames()
	local seen, list = {}, {}
	local function walk(node)
		if node.clip then
			if not seen[node.clip] then seen[node.clip] = true; table.insert(list, node.clip) end
			return
		end
		for _, c in ipairs(node.children) do walk(c[#c]) end
	end
	for _, s in pairs(STATES) do walk(s.motion) end
	table.sort(list)
	return list
end

local function smoothDamp(cur, target, vel, smoothTime, dt)
	smoothTime = math.max(1e-4, smoothTime)
	local omega = 2 / smoothTime
	local x = omega * dt
	local e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	local change = cur - target
	local temp = (vel + omega * change) * dt
	vel = (vel - omega * temp) * e
	return target + (change + temp) * e, vel
end

local function freeform(children, px, py, w)
	local n = #children
	local sum = 0
	for i = 1, n do
		local ci = children[i]
		local h = 1
		for j = 1, n do
			if j ~= i then
				local cj = children[j]
				local vx, vy = cj[1] - ci[1], cj[2] - ci[2]
				local len2 = vx * vx + vy * vy
				if len2 > 1e-9 then
					local t = 1 - ((px - ci[1]) * vx + (py - ci[2]) * vy) / len2
					if t < h then h = t end
				end
			end
		end
		h = math.max(h, 0)
		w[i] = h
		sum += h
	end
	if sum > 0 then for i = 1, n do w[i] /= sum end end
end

local function simple(children, px, py, w)
	local center
	local dirs = {}
	for i, c in ipairs(children) do
		w[i] = 0
		if c[1] == 0 and c[2] == 0 then center = i else table.insert(dirs, { i = i, a = math.atan2(c[2], c[1]), x = c[1], y = c[2] }) end
	end
	local mag = math.sqrt(px * px + py * py)
	if mag < 1e-5 or #dirs == 0 then
		if center then w[center] = 1 else for _, d in ipairs(dirs) do w[d.i] = 1 / #dirs end end
		return
	end
	table.sort(dirs, function(a, b) return a.a < b.a end)
	local pa = math.atan2(py, px)
	local A, B = dirs[#dirs], dirs[1] -- wrap-around pair by default
	for k = 1, #dirs - 1 do
		if pa >= dirs[k].a and pa <= dirs[k + 1].a then A, B = dirs[k], dirs[k + 1] break end
	end
	local det = A.x * B.y - A.y * B.x
	local wa, wb
	if math.abs(det) < 1e-6 then
		wa, wb = mag / math.sqrt(A.x * A.x + A.y * A.y), 0
	else
		wa = (px * B.y - py * B.x) / det
		wb = (A.x * py - A.y * px) / det
	end
	wa, wb = math.max(wa, 0), math.max(wb, 0)
	local s = wa + wb
	if center and s < 1 then
		w[center] = 1 - s
	elseif s > 0 then
		wa, wb = wa / s, wb / s
	end
	w[A.i], w[B.i] = wa, wb
end

-- motion -> weighted leaves
local function eval(node, p, weight, out)
	if weight <= 1e-4 then return end
	if node.clip then
		table.insert(out, { leaf = node, w = weight })
		return
	end
	local ch = node.children
	if node.kind == "1D" then
		local v = p[node.param] or 0
		if v <= ch[1][1] then return eval(ch[1][2], p, weight, out) end
		if v >= ch[#ch][1] then return eval(ch[#ch][2], p, weight, out) end
		for i = 1, #ch - 1 do
			local a, b = ch[i], ch[i + 1]
			if v >= a[1] and v <= b[1] then
				local t = (b[1] - a[1]) > 1e-9 and (v - a[1]) / (b[1] - a[1]) or 0
				eval(a[2], p, weight * (1 - t), out)
				eval(b[2], p, weight * t, out)
				return
			end
		end
	else
		local w = {}
		if node.kind == "Simple" then simple(ch, p.RelX, p.RelY, w) else freeform(ch, p.RelX, p.RelY, w) end
		for i, c in ipairs(ch) do eval(c[3], p, weight * w[i], out) end
	end
end

function Graph.new()
	local self = setmetatable({}, Graph)
	self.active = { { state = "SlowMovement", time = 0, weight = 1 } }
	self.fade = 0 -- seconds left in the current cross-fade
	self.fadeDur = 0
	self.p = {
		Speed = 0, IsGrounded = true, JumpType = -1, AltJump = false, FastFall = false, RelX = 0, RelY = 0,
		Running = false, ChargeRun = false, Confidence = 1, Damaged = false, DamageDirX = 0,
	}
	self.relXVel, self.relYVel = 0, 0
	self.jumpType, self.airFrames = 0, 0
	self.state = "SlowMovement"
	return self
end

function Graph:current()
	return self.active[#self.active]
end

-- start a transition (dur 0 = cut)
function Graph:go(to, dur)
	if dur <= 0 then
		self.active = { { state = to, time = 0, weight = 1 } }
		self.fade, self.fadeDur = 0, 0
	else
		table.insert(self.active, { state = to, time = 0, weight = 0 })
		self.fade, self.fadeDur = dur, dur
	end
	self.state = to
end

function Graph:Land(kind, diving)
	if diving then return end
	if kind == "Bad" or kind == "Ok" then self:go("Land1", 0)
	elseif kind == "Good" then self:go("Land3", 0)
	elseif kind == "Perfect" then self:go("Land4", 0) end
end

function Graph:Damage(sideX)
	self.p.Damaged = true
	self.p.DamageDirX = sideX
end

local function duration(leaves, clips)
	local d, wsum = 0, 0
	for _, l in ipairs(leaves) do
		local len = clips:Length(l.leaf.clip)
		d += l.w * len / l.leaf.ts
		wsum += l.w
	end
	return wsum > 0 and d / wsum or 1
end

function Graph:Step(s, dt, clips)
	local p = self.p
	-- PlayerAnimationHandler.Update
	if s.isGrounded then
		local y = s.velUnitY
		self.jumpType = (y > 0.75 and 4) or (y > 0.6 and 3) or (y > 0.45 and 2) or (y > 0.25 and 1) or 0
		if self.jumpType == 4 or self.jumpType == 2 or self.jumpType == 1 then p.AltJump = not p.AltJump end
	end
	local slow = s.mode ~= "Fast"
	p.Speed = s.speed / 100 * (slow and 2 or 1)
	if self.airFrames > 2 or s.mostlyGrounded or slow then p.JumpType = -1 end
	if not s.mostlyGrounded then self.airFrames += 1 else self.airFrames = 0 end
	if p.IsGrounded and not s.mostlyGrounded then p.JumpType = self.jumpType end
	if self.airFrames > 2 or s.mostlyGrounded or slow then p.JumpType = -1 end
	p.IsGrounded = s.mostlyGrounded
	p.FastFall = s.fastFall
	p.RelX, self.relXVel = smoothDamp(p.RelX, s.relX, self.relXVel, 0.2, dt)
	p.RelY, self.relYVel = smoothDamp(p.RelY, s.relY, self.relYVel, 0.2, dt)
	p.Running = not slow
	p.ChargeRun = slow and s.charging or false

	local cur = self:current()
	local moved = false
	for _, t in ipairs(ANY) do
		if t.to ~= cur.state and t.when(p) then self:go(t.to, t.dur); moved = true break end
	end
	if not moved then
		local def = STATES[cur.state]
		for _, t in ipairs(def.go) do
			local ok
			if t.exit then ok = cur.time >= t.exit and (not t.when or t.when(p)) else ok = t.when(p) end
			if ok then self:go(t.to, t.dur) break end
		end
	end
	p.Damaged = false

	if self.fade > 0 then
		self.fade = math.max(self.fade - dt, 0)
		local newest = self.active[#self.active]
		local target = 1 - self.fade / self.fadeDur
		local others = 0
		for i = 1, #self.active - 1 do others += self.active[i].weight end
		local rest = 1 - target
		for i = 1, #self.active - 1 do
			self.active[i].weight = others > 0 and self.active[i].weight / others * rest or 0
		end
		newest.weight = target
		if self.fade <= 0 then self.active = { newest }; newest.weight = 1 end
		for i = #self.active - 1, 1, -1 do
			if self.active[i].weight < 1e-3 then table.remove(self.active, i) end
		end
	end

	local draw = {}
	for _, a in ipairs(self.active) do
		local leaves = {}
		eval(STATES[a.state].motion, p, 1, leaves)
		a.time += dt / duration(leaves, clips)
		for _, l in ipairs(leaves) do
			local len = clips:Length(l.leaf.clip)
			local t = a.time
			if clips:Loops(l.leaf.clip) then t = t % 1 else t = math.min(t, 1) end
			table.insert(draw, { name = l.leaf.clip, weight = l.w * a.weight, time = t * len })
		end
	end
	return draw
end

return Graph
