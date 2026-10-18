return {
	Name = "judge",
	Description = "Judge mode (half the traps, 30% fewer lucky blocks) from the next race / map: judge [on|off]. No word: says which.",
	Group = "Admin",
	Args = {
		{ Type = "string", Name = "State", Description = "on / off (default: just say which)", Optional = true },
	},
}
