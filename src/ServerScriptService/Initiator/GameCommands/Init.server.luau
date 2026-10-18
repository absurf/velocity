local Commands = script.Parent.Commands
local Types    = script.Parent.Types
local Hooks    = script.Parent.Hooks

local Cmdr = require(script.Parent.MainModule.Cmdr)

Cmdr:RegisterDefaultCommands({ "Help" })
Cmdr:RegisterCommandsIn(Commands)
Cmdr:RegisterTypesIn(Types)
Cmdr:RegisterHooksIn(Hooks)
