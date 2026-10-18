return {
	Name = "countdown",
	Description = "The 3-2-1-GO on screens (a test: nothing waits for GO yet). Everyone it's sent to hits GO together. Defaults to you.",
	Group = "Admin",
	Args = {
		{ Type = "players", Name = "Players", Description = "Whose screens (default: you)", Optional = true },
	},
}
