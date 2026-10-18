return {
	Name = "bots",
	Description = "Bots on the map: bots [easy|normal|hard] [count] (default normal, fills to 8 racers) | bots off.",
	Group = "Admin",
	Args = {
		{ Type = "string", Name = "Difficulty", Description = "easy / normal / hard, or off (default: normal)", Optional = true },
		{ Type = "integer", Name = "Count", Description = "How many bots (default: fill the race to 8 racers)", Optional = true },
	},
}
