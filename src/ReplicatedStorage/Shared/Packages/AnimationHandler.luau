-- [ SERVICES ]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- [ UTILITY MODULES ]--
local NetworkHandler = require(script.Parent.AbsurfNetworkHandler)

-- [ VARIABLES ]--
local Assets_Folder = ReplicatedStorage.Assets
local Animations_Folder = Assets_Folder.Animations

local Player = Players.LocalPlayer

local module = {

	["Animations"] = {},
	["Cache"] = {},
	["Remaps"] = {}, -- ADD THIS
}

local function ResolveAnimationName(Character, Animation_Name)
	if module.Remaps[Character] and module.Remaps[Character][Animation_Name] then
		return module.Remaps[Character][Animation_Name]
	end
	return Animation_Name
end

local function GetAnimator(Character : Instance?) : Animator?
	if Character == nil then return nil end
	local rig = Character:FindFirstChildOfClass("Humanoid") or Character:FindFirstChildOfClass("AnimationController")
	return (rig and rig:FindFirstChildOfClass("Animator")) or nil
end

module.Load = function(Character : Model, Animation_Name : string)
	if Character == nil then return end

	local Animator : Animator = GetAnimator(Character)
	if Animator == nil then return warn("Could not find an Animator (Humanoid/AnimationController) in "..Character.Name.."!") end

	if module.Animations[Animation_Name] ~= nil then

		local AnimTrack : Animation = module.Animations[Animation_Name]

		return Animator:LoadAnimation(AnimTrack)
	else

		warn(Animation_Name.." does not exist!")
		return nil

	end

end

module.Setup = function(Character : Model)

	module.Remove(Character)

	local Animator : Animator = GetAnimator(Character)
	if Animator == nil then return warn("Could not find an Animator in "..Character.Name.."!") end

	module.Cache[Character] = {}

	for Animation_Name,Anim_Asset : Animation in pairs(module.Animations) do
		module.Cache[Character][Animation_Name] = Animator:LoadAnimation(Anim_Asset)
	end

end

module.SetupOnly = function(Character : Model, Names : {string})
	module.Remove(Character)
	local Animator : Animator = GetAnimator(Character)
	if Animator == nil then return warn("Could not find an Animator in "..Character.Name.."!") end
	module.Cache[Character] = {}
	for _, name in ipairs(Names) do
		local asset = module.Animations[name]
		if asset then
			module.Cache[Character][name] = Animator:LoadAnimation(asset)
		else
			warn(name.." animation not found in Animations folder!")
		end
	end
end

module.LoadOne = function(Character : Model, Name : string) : AnimationTrack?
	if Character == nil then return nil end
	local Animator : Animator = GetAnimator(Character)
	if Animator == nil then warn("Could not find an Animator in "..Character.Name.."!"); return nil end
	local cache = module.Cache[Character]
	if cache == nil then cache = {}; module.Cache[Character] = cache end
	if cache[Name] then return cache[Name] end
	local asset = module.Animations[Name]
	if asset == nil then warn(Name.." animation not found in Animations folder!"); return nil end
	local track = Animator:LoadAnimation(asset)
	cache[Name] = track
	return track
end

module.Play = function(Player : Player, Character : Model, Animation_Name : string, Properties)
	Animation_Name = ResolveAnimationName(Character, Animation_Name)

	if RunService:IsServer() then

		if Properties == nil then Properties = {} end

		if Character == nil then
			NetworkHandler.Send(Player, "PlayAnimation", false, Animation_Name, Properties)

		else

			local Animator : Animator = GetAnimator(Character)
			if Animator == nil then return warn("Could not find an Animator in "..Character.Name.."!") end

			if Character == nil then
				-- print("its nil")
				if Player.Character ~= nil then
					-- print("NOT HNIL")
					Character = Player.Character
				end
			end

			-- warn(Character)

			if module.Cache[Character] ~= nil then

				if module.Cache[Character][Animation_Name] ~= nil then

					-- print(module.Cache)

					local Track : AnimationTrack = module.Cache[Character][Animation_Name]

					local Priority = Properties.Priority or Track.Priority
					local Speed = Properties.Speed or Track.Speed
					local Fade = Properties.Fade or 0.100000001
					local Weight = Properties.Weight or 1

					Track.Priority = Priority
					Track:Play(Fade,Weight,Speed)

					return Track

				else

					warn(`{Animation_Name} does not exist in {Character.Name}!`)
					return nil

				end

			else
				warn(`{Character.Name} does not exist!`)
				return nil
			end

		end

	else

		if Character == nil then
			Character = Player.Character
			print(Character)

			if Character == nil then return end
		end
		-- warn("Passed")

		local Animator : Animator = GetAnimator(Character)
		if Animator == nil then return warn("Could not find an Animator in "..Character.Name.."!") end

		if module.Cache[Character] ~= nil then

			if module.Cache[Character][Animation_Name] ~= nil then

				-- print(module.Cache)

				local Track : AnimationTrack = module.Cache[Character][Animation_Name]

				local Priority = Properties.Priority or Track.Priority
				local Speed = Properties.Speed or Track.Speed

				local Fade = Properties.Fade or 0.15
				local Weight = Properties.Weight or 1

				-- warn(Priority,Speed,Fade,Weight)

				Track.Priority = Priority
				Track:Play(Fade,Weight,Speed)

				return Track

			else

				warn(`{Animation_Name} does not exist in {Character.Name}!`)
				return nil

			end

		else
			warn(`{Character.Name} does not exist!`)
			return nil
		end

	end

end

module.Stop = function(Player : Player, Character : Model, Animation_Names, Properties)

	if RunService:IsServer() then

		if Properties == nil then Properties = {} end

		if Character == nil then
			NetworkHandler.Send(Player, "StopAnimation", false, Animation_Names, Properties)
		else
			if Character == nil then
				Character = Player.Character
				if Character == nil then return end
			end
			if Properties == nil then Properties = {} end
			if module.Cache[Character] ~= nil then
				local ResolvedNames = {}
				for _, name in ipairs(Animation_Names) do
					table.insert(ResolvedNames, ResolveAnimationName(Character, name))
				end
				for Name_Of_Animation, Track in pairs(module.Cache[Character]) do
					if table.find(ResolvedNames, Name_Of_Animation) then
						local Fade = Properties.Fade or 0.100000001
						Track:Stop(Fade)
					end
				end
			end
		end

	else

		if Character == nil then
			Character = Player.Character
			if Character == nil then return end
		end
		if Properties == nil then Properties = {} end
		if module.Cache[Character] ~= nil then
			local ResolvedNames = {}
			for _, name in ipairs(Animation_Names) do
				table.insert(ResolvedNames, ResolveAnimationName(Character, name))
			end
			for Name_Of_Animation, Track in pairs(module.Cache[Character]) do
				if table.find(ResolvedNames, Name_Of_Animation) then
					local Fade = Properties.Fade or 0.100000001
					Track:Stop(Fade)
				end
			end
		end
	end
end

module.Remove = function(Character : Model)

	if module.Cache[Character] then
		module.Cache[Character] = nil
	end

end

module.GetTrack = function(Character : Model, Animation_Name : string)
	Animation_Name = ResolveAnimationName(Character, Animation_Name)

	if Character == nil then
		return
	end

	if module.Cache[Character] ~= nil then
		if module.Cache[Character][Animation_Name] ~= nil then

			local Track : AnimationTrack = module.Cache[Character][Animation_Name]
			return Track
		end
	end

end

module.SetRemap = function(Character : Model, RemapTable : {[string]: string})
	module.Remaps[Character] = RemapTable
end

module.ClearRemap = function(Character : Model)
	if module.Remaps[Character] then
		-- Stop all currently remapped animations
		for originalName, remappedName in pairs(module.Remaps[Character]) do
			if module.Cache[Character] and module.Cache[Character][remappedName] then
				local Track = module.Cache[Character][remappedName]
				if Track.IsPlaying then
					Track:Stop(0.15)
				end
			end
		end
	end
	module.Remaps[Character] = nil
end

-- [ SETUP ]--

NetworkHandler.AddListener("PlayAnimation", function(Animation_Name : string, Properties)

	module.Play(Player, nil, Animation_Name, Properties)

	warn("PALYAPLYAPYLPYLAPYA")
	-- warn(Animation_Name)

end)

NetworkHandler.AddListener("StopAnimation", function(Animation_Name : string, Properties)

	module.Stop(Player, nil, Animation_Name, Properties)

end)

for i,v in pairs(Animations_Folder:GetDescendants()) do
	if v:IsA("Animation") then
		module.Animations[v.Name] = v
	end
end

return module
