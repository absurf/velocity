return {
	Name = "ui",
	Description = "UI on screens: speed = only the speed readout, all = everything back. Defaults to you.",
	Group = "Admin",
	Args = {
		{ Type = "uiMode", Name = "Mode", Description = "speed (only the speed readout) or all (everything back)" },
		{ Type = "players", Name = "Players", Description = "Whose screens (default: you)", Optional = true },
	},
}
