return function(registry)
	registry:RegisterType("uiMode", registry.Cmdr.Util.MakeEnumType("UiMode", { "speed", "all" }))
end
