local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CmdrConfig = require(ReplicatedStorage.Shared.Modules.Configs.CmdrConfig)

return function(registry)
	registry:RegisterHook("BeforeRun", function(context)
		local Player = context.Executor
		local UserID = Player.UserId

		local isAdmin     = table.find(CmdrConfig.ADMINS, UserID)
		local isDeveloper = table.find(CmdrConfig.DEVELOPERS, UserID)

		if context.Group == "Admin" then
			if not isAdmin then
				return "You do not have permission to use this command! (Admin required)"
			end
		end

		if context.Group == "Developer" then
			if not isAdmin and not isDeveloper then
				return "You do not have permission to use this command! (Developer required)"
			end
		end
	end)
end
