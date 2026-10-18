local Services = script.Services

for i,v in pairs(Services:GetDescendants()) do
	if v:IsA("ModuleScript") then

		local module = require(v)

		if module.Init then
			module:Init()
		end

	end
end
