local module = {}

module.Actions = {
	Dive = {
		Action = "Dive",
		Keys = { MouseKeyboard = "Space", Gamepad = "ButtonR2" },
		Labels = { MouseKeyboard = "Space", Gamepad = "R2" },
		Bar = true, Order = 1, Hold = true, Group = "Speed",
	},

	FastRun = {
		Action = "Run / walk",
		Keys = { MouseKeyboard = "LeftShift", Gamepad = "ButtonL3" },
		Labels = { MouseKeyboard = "Shift", Gamepad = "L3" },
		Bar = true, Order = 2, Hold = true, Group = "Speed",
	},
	Respawn = {
		Action = "Restart",
		Keys = { MouseKeyboard = "R", Gamepad = "DPadUp" },
		Labels = { MouseKeyboard = "R", Gamepad = "Up" },
		Bar = true, Order = 3, Group = "Speed",
	},

	UseItem = {
		Action = "Use item",
		Keys = { MouseKeyboard = "MouseButton1", Gamepad = "ButtonR1" },
		Labels = { MouseKeyboard = "LMB", Gamepad = "R1" },
		Bar = true, Order = 5, Hold = true, Group = "Speed",
	},
	Body = {
		Action = "Ball / human",
		Keys = { MouseKeyboard = "B", Gamepad = "DPadDown" },
		Labels = { MouseKeyboard = "B", Gamepad = "Down" },
		Bar = true, Order = 4, Group = "Speed",
	},

	-- TEST KEYS (SpeedDev)
	CourseValley = { Action = "Valley course", Keys = { MouseKeyboard = "V" }, Labels = { MouseKeyboard = "V" }, Bar = false, Group = "SpeedDev" },
	CourseCurves = { Action = "Curves course", Keys = { MouseKeyboard = "C" }, Labels = { MouseKeyboard = "C" }, Bar = false, Group = "SpeedDev" },
	CoursePart = { Action = "Part course", Keys = { MouseKeyboard = "T" }, Labels = { MouseKeyboard = "T" }, Bar = false, Group = "SpeedDev" },
	AutoSteer = { Action = "Auto-steer bot", Keys = { MouseKeyboard = "P" }, Labels = { MouseKeyboard = "P" }, Bar = false, Group = "SpeedDev" },
	Hud = { Action = "Hide HUD", Keys = { MouseKeyboard = "H" }, Labels = { MouseKeyboard = "H" }, Bar = false, Group = "SpeedDev" },
	FreeMouse = { Action = "Free mouse", Keys = { MouseKeyboard = "M" }, Labels = { MouseKeyboard = "M" }, Bar = false, Group = "SpeedDev" },
	Ghost = { Action = "Ghost (you, as others see you)", Keys = { MouseKeyboard = "G" }, Labels = { MouseKeyboard = "G" }, Bar = false, Group = "SpeedDev" },
}

return module
