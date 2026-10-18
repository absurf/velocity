return {
	Name = "map",
	Description = "New generated grass map for everyone, standing at its start (hold Shift to launch). Same seed = same map. No seed: random.",
	Group = "Admin",
	Args = {
		{ Type = "integer", Name = "Seed", Description = "Which map (default: a random one)", Optional = true },
		{ Type = "string", Name = "Pieces", Description = "Test: gaps / islands (every crest), traps / spinners / cages / lava / missiles (all along), all (default: the map's own)", Optional = true },
	},
}
