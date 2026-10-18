return function(registry)
	registry:RegisterType("speedAction", registry.Cmdr.Util.MakeEnumType("SpeedAction",
		{ "course", "body", "auto", "wp", "dive", "start", "still", "ghost", "lag", "warp", "item", "steer", "minimap", "sound", "tags", "vfx" }))
end
