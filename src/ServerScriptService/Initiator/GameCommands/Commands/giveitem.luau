return {
	Name = "giveitem",
	Description = "Give an item now: giveitem <item> [players] (item: grapple / gator / drink / ink / shotgun; default: you).",
	Group = "Admin",
	Args = {
		{ Type = "string", Name = "Item", Description = "grapple / gator / drink / ink / shotgun" },
		{ Type = "players", Name = "Players", Description = "Who gets it (default: you)", Optional = true },
	},
}
