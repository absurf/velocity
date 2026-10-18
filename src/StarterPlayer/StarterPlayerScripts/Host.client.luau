local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local NetworkHandler = require(ReplicatedStorage.Shared.Packages.AbsurfNetworkHandler)

local function HasIgnoreTag(instance: Instance): boolean
	local current = instance
	while current and current ~= game do
		if CollectionService:HasTag(current, "IgnoreInit") then
			return true
		end
		current = current.Parent
	end
	return false
end

for i,v in pairs(ReplicatedStorage.Shared.Services:GetDescendants()) do
	if v:IsA("ModuleScript") then
		if HasIgnoreTag(v) then continue end
		local module = require(v)
		if type(module) ~= "table" then continue end
		-- print(v.Name, v)
		if module.Init then
			module:Init()
		end
	end
end

for i,v in pairs(ReplicatedStorage.UI:GetDescendants()) do
	if v:IsA("ModuleScript") then
		if HasIgnoreTag(v) then continue end
		local module = require(v)
		if type(module) ~= "table" then continue end
		if module.Init then
			module:Init()
		end
	end
end

NetworkHandler.Send(nil, "PlayerStartupServiceServer_ClientReady", false)
