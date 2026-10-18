return {
	Name = "race",
	Description = "Start a race: race [seed] [easy|normal|hard|off] -- a new map, bots, the grid, the cutscene, 3-2-1, GO.",
	Group = "Admin",
	Args = {
		{ Type = "integer", Name = "Seed", Description = "Which map (default: a random one)", Optional = true },
		{ Type = "string", Name = "Bots", Description = "easy / normal / hard / off (default: normal)", Optional = true },
	},
}
