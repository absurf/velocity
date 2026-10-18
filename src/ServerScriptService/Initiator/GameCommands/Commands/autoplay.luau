return {
	Name = "autoplay",
	Description = "Bots drive these players' runners and races loop by themselves (10 s apart): autoplay <on|off> [players] (default: you).",
	Group = "Admin",
	Args = {
		{ Type = "string", Name = "State", Description = "on / off" },
		{ Type = "players", Name = "Players", Description = "Who (default: you)", Optional = true },
	},
}
