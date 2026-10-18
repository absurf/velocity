local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local GUIController = {}
if RunService:IsServer() then return GUIController end

local Player = Players.LocalPlayer

-- [ FEEL ]-- STARTING VALUES, NOT TUNED.
local POPUPS = { StartingHolder = true, ResultsHolder = true, FinishedHolder = true }   -- not HUD: they stay put
local OUT = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local IN = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local STAGGER = 0.05     -- s between one panel and the next
local MARGIN = 0.06

-- [ STATE ]--
local Hidden = false
local Rest: { [GuiObject]: UDim2 } = {}      -- each panel's place on screen
local Moving: { [GuiObject]: Tween } = {}
local Sent: { GuiObject } = {}               -- the panels sent away (to bring back)

local function Holder(): Instance?
	local gui = Player:FindFirstChild("PlayerGui")
	gui = gui and gui:FindFirstChild("GameGUI")
	return gui and gui:FindFirstChild("Holder")
end

local function Away(panel: GuiObject, rest: UDim2): UDim2
	local holder = panel.Parent :: GuiObject
	local hsize = holder.AbsoluteSize
	if hsize.X < 1 or hsize.Y < 1 then return rest end

	local size = panel.AbsoluteSize
	local restX = rest.X.Scale * hsize.X + rest.X.Offset - panel.AnchorPoint.X * size.X
	local restY = rest.Y.Scale * hsize.Y + rest.Y.Offset - panel.AnchorPoint.Y * size.Y
	local at = panel.AbsolutePosition
	local x0, y0, x1, y1 = 0, 0, size.X, size.Y
	for _, d in panel:GetDescendants() do
		if d:IsA("GuiObject") and d.Visible then
			local p, s = d.AbsolutePosition - at, d.AbsoluteSize
			x0, y0 = math.min(x0, p.X), math.min(y0, p.Y)
			x1, y1 = math.max(x1, p.X + s.X), math.max(y1, p.Y + s.Y)
		end
	end
	local hp = holder.AbsolutePosition
	local left, top = hp.X + restX + x0, hp.Y + restY + y0
	local right, bottom = hp.X + restX + x1, hp.Y + restY + y1

	local gui = holder:FindFirstAncestorWhichIsA("ScreenGui")
	local inset = if gui and gui.IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset()
	local view = workspace.CurrentCamera.ViewportSize
	local sl, st, sr, sb = -inset.X, -inset.Y, view.X - inset.X, view.Y - inset.Y
	local mx, my = MARGIN * view.X, MARGIN * view.Y

	local cx, cy = ((left + right) / 2 - hp.X) / hsize.X, ((top + bottom) / 2 - hp.Y) / hsize.Y
	local edges = {
		{ cx, Vector2.new(sl - mx - right, 0) },        -- left
		{ 1 - cx, Vector2.new(sr + mx - left, 0) },     -- right
		{ cy, Vector2.new(0, st - my - bottom) },       -- top
		{ 1 - cy, Vector2.new(0, sb + my - top) },      -- bottom
	}
	table.sort(edges, function(a, b) return a[1] < b[1] end)
	local shift = edges[1][2]
	return rest + UDim2.fromScale(shift.X / hsize.X, shift.Y / hsize.Y)
end

local function Move(panel: GuiObject, info: TweenInfo, goal: UDim2, delay: number, instant: boolean?)
	if Moving[panel] then Moving[panel]:Cancel() end
	if instant then
		panel.Position = goal
		return
	end
	local tween = TweenService:Create(panel, TweenInfo.new(info.Time, info.EasingStyle, info.EasingDirection, 0, false, delay), { Position = goal })
	Moving[panel] = tween
	tween:Play()
end

function GUIController.HideHud(instant: boolean?)
	if Hidden then return end
	local holder = Holder()
	if not holder then return end
	Hidden = true
	table.clear(Sent)
	local i = 0
	for _, panel in holder:GetChildren() do
		if not panel:IsA("GuiObject") or POPUPS[panel.Name] or not panel.Visible then continue end
		if not Moving[panel] or Moving[panel].PlaybackState ~= Enum.PlaybackState.Playing then Rest[panel] = Rest[panel] or panel.Position end
		local rest = Rest[panel] or panel.Position
		Rest[panel] = rest
		table.insert(Sent, panel)
		Move(panel, OUT, Away(panel, rest), i * STAGGER, instant)
		i += 1
	end
end

function GUIController.ShowHud(instant: boolean?)
	if not Hidden then return end
	Hidden = false
	for i, panel in Sent do
		local rest = Rest[panel]
		if rest and panel.Parent then Move(panel, IN, rest, (i - 1) * STAGGER, instant) end
	end
	table.clear(Sent)
end

function GUIController.HudHidden(): boolean
	return Hidden
end

return GUIController
