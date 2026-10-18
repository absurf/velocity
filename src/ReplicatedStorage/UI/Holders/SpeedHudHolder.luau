local TweenService = game:GetService("TweenService")

local Hud = {}
Hud.__index = Hud

local POPUPS = false

local LANDING_STYLE = {
	Perfect = { text = "PERFECT", color = Color3.fromRGB(90, 235, 255) },
	Good = { text = "GOOD", color = Color3.fromRGB(120, 255, 140) },
	Ok = { text = "OK", color = Color3.fromRGB(255, 255, 255) },
	Bad = { text = "BAD", color = Color3.fromRGB(255, 80, 80) },
}

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	for k, v in pairs(props) do
		l[k] = v
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.2
	stroke.Parent = l
	l.Parent = parent
	return l
end

function Hud.new(playerGui)
	local self = setmetatable({}, Hud)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpeedHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	self.gui = gui

	self.speed = label(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.94), Size = UDim2.fromScale(0.2, 0.09), Text = "0" })
	self.speedSub = label(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.94), Size = UDim2.fromScale(0.2, 0.025), Font = Enum.Font.GothamBold, Text = "studs/s" })

	local barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0.5, 1)
	barBack.Position = UDim2.fromScale(0.5, 0.845)
	barBack.Size = UDim2.fromScale(0.18, 0.012)
	barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	barBack.BackgroundTransparency = 0.3
	barBack.BorderSizePixel = 0
	barBack.Parent = gui
	self.energyBack = barBack
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 235, 255)
	fill.BorderSizePixel = 0
	fill.Parent = barBack
	self.energyFill = fill

	self.popup = label(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromScale(0.34, 0.1), Text = "", TextTransparency = 1 })
	self.popup.UIStroke.Thickness = 3
	self.popupScale = Instance.new("UIScale")
	self.popupScale.Parent = self.popup
	self.popupSub = label(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.41), Size = UDim2.fromScale(0.3, 0.03), Font = Enum.Font.GothamBold, Text = "", TextTransparency = 1 })

	self.charge = label(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromScale(0.3, 0.035), Font = Enum.Font.GothamBold, Text = "" })

	self.debug = label(gui, { AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromScale(0.01, 0.08), Size = UDim2.fromScale(0.3, 0.2), Font = Enum.Font.Code, TextScaled = false, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
	self.help = label(gui, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.99, 0.08), Size = UDim2.fromScale(0.4, 0.16), Font = Enum.Font.GothamBold, TextScaled = false, TextWrapped = false, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Top,
		Text = "auto-run · A/D or mouse steer · S brakes\nSpace = dive (fast-fall)\nhold Shift = charge into a run · tap Shift = walk\nR = restart · V = valley · C = curves · T = part course · P = auto-steer bot · B = ball / human · M = free mouse · H = hide HUD" })
	self.side = label(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromScale(0.2, 0.035), Font = Enum.Font.GothamBlack, Text = "", TextTransparency = 1, TextColor3 = Color3.fromRGB(255, 225, 90) })
	self.popupToken = 0
	self.sideToken = 0
	return self
end

local SPEED_COLORS = {
	{ 0, Color3.fromRGB(255, 255, 255) },
	{ 0.494, Color3.fromRGB(255, 156, 88) },
	{ 0.756, Color3.fromRGB(255, 88, 88) },
	{ 1, Color3.fromRGB(195, 16, 16) },
}
local function speedColor(units)
	local t = math.clamp((units - 50) / 50, 0, 1)
	for i = 2, #SPEED_COLORS do
		local a, b = SPEED_COLORS[i - 1], SPEED_COLORS[i]
		if t <= b[1] then
			return a[2]:Lerp(b[2], (t - a[1]) / (b[1] - a[1]))
		end
	end
	return SPEED_COLORS[#SPEED_COLORS][2]
end

function Hud:SideNote(text)
	if not POPUPS then return end
	self.sideToken += 1
	local token = self.sideToken
	local s = self.side
	s.Text, s.TextTransparency = text, 0
	s.UIStroke.Transparency = 0.2
	task.delay(0.5, function()
		if token ~= self.sideToken then return end
		TweenService:Create(s, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		TweenService:Create(s.UIStroke, TweenInfo.new(0.2), { Transparency = 1 }):Play()
	end)
end

function Hud:SetVisible(on)
	self.gui.Enabled = on
end

function Hud:SetReadoutsVisible(on)
	self.readouts = on
	self.speed.Visible, self.speedSub.Visible, self.energyBack.Visible = on, on, on
	self.debug.Visible, self.help.Visible = on, on
end

function Hud:SetSpeedOnly(on)
	self.speedOnly = on
	for _, child in self.gui:GetChildren() do
		if child:IsA("GuiObject") then
			child.Visible = not on or child == self.speed or child == self.speedSub
		end
	end
end

function Hud:Popup(text, color, sub)
	if not POPUPS then return end
	self.popupToken += 1
	local token = self.popupToken
	local p, s = self.popup, self.popupSub
	p.Text, p.TextColor3, p.TextTransparency = text, color, 0
	p.UIStroke.Transparency = 0.2
	s.Text, s.TextTransparency = sub or "", 0
	s.UIStroke.Transparency = 0.2
	-- lands big on frame 1, then settles
	self.popupScale.Scale = 1.35
	TweenService:Create(self.popupScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.75, function()
		if token ~= self.popupToken then return end
		local info = TweenInfo.new(0.25)
		TweenService:Create(p, info, { TextTransparency = 1 }):Play()
		TweenService:Create(p.UIStroke, info, { Transparency = 1 }):Play()
		TweenService:Create(s, info, { TextTransparency = 1 }):Play()
		TweenService:Create(s.UIStroke, info, { Transparency = 1 }):Play()
	end)
end

function Hud:Bind(movement)
	if self.conns then
		for _, c in ipairs(self.conns) do c:Disconnect() end
	end
	self.movement = movement
	self.conns = {
		movement.Landed.Event:Connect(function(info)
			local style = LANDING_STYLE[info.kind]
			if style then
				self:Popup(style.text, style.color, string.format("score %.2f · hit at %d° · %.1fs air", info.score, math.floor(info.impactAngle + 0.5), info.airTime))
			end
		end),
		movement.CloseCall.Event:Connect(function(side)
			self:SideNote(side == "Left" and "◀ CLOSE CALL" or "CLOSE CALL ▶")
		end),
		movement.Hit.Event:Connect(function(kind, damage)
			local text = kind == "HeadOn" and "HEAD-ON" or (kind == "Bonk" and "BONK" or (kind == "Trap" and "ZAP" or "SMASH"))
			self:Popup(text, Color3.fromRGB(255, 150, 60), string.format("-%d", damage))
		end),
	}
end

function Hud:Update()
	local mv = self.movement
	if not mv then return end
	local d = mv:GetDebug()
	local charge = if d.mode == "Slow" then (d.charge > 0 and string.format("CHARGING %d%%", math.floor(math.min(d.charge, 1) * 100)) or "WASD to move · hold Shift to launch") else ""
	if self.charge.Text ~= charge then self.charge.Text = charge end
	if self.readouts == false then return end
	self.speed.Text = string.format("%d", math.floor(d.speed + 0.5))
	self.speed.TextColor3 = speedColor(d.speedUnits)
	self.speedSub.Text = string.format("studs/s  ·  %d speed", math.floor(d.speedUnits + 0.5))
	self.energyFill.Size = UDim2.fromScale(d.energy, 1)
	local last = mv.lastLanding
	self.debug.Text = string.format(
		"mode %s   %s%s%s\nair %.2fs   height %d\nenergy %.2f   autosteer %s (wp %d)\nlast: %s",
		d.mode,
		d.grounded and "grounded" or "airborne",
		d.fastFalling and "  DIVE" or "",
		d.braking and "  BRAKE" or "",
		d.sinceGrounded, math.floor(d.height),
		d.energy, d.autoSteer and "on" or "off", d.waypoint,
		last and string.format("%s %.2f @%d°", last.kind, last.score, math.floor(last.impactAngle + 0.5)) or "-"
	)
end

return Hud
