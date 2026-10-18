return {
	Name = "speed",
	Description = "Speed dev controls: course <name> | body ball|human | auto on|off | wp <n> | dive <s> | start | still | ghost on|off | lag <ping> [jitter] [loss%] | warp <studs> | item <name> [uses]/use/off | minimap follow|whole | sound on|off|<set> | tags on|off | vfx land|bad|spawn|run / vfx 'lines on|off'. Defaults to you.",
	Group = "Admin",
	Args = {
		{ Type = "speedAction", Name = "Action", Description = "What to do" },
		{ Type = "string", Name = "Value", Description = "Course / ball|human / on|off / waypoint / seconds / ping ms", Optional = true },
		{ Type = "players", Name = "Players", Description = "Whose screens (default: you)", Optional = true },
	},
}
