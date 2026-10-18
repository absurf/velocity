-- [ SERVICES ]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
-- [ VARIABLES ]--

local Assets_Folder = ReplicatedStorage.Assets
local Sounds_Folder = Assets_Folder.Sounds

-- [ UTILITY MODULES ]--
local AbsurfUtility = require(script.Parent.AbsurfUtility)

local module = {

	["Audios"] = {},
	["Cache"] = {},
	["SoundGroups"] = {}, -- Maps audio name to sound group name

}

local VALID_CATEGORIES = {
	"Master",
	"Music",
	"Misc"
}

local function GetSoundCategory(soundInstance)
	local current = soundInstance.Parent

	while current and current ~= Sounds_Folder do

		for _, category in ipairs(VALID_CATEGORIES) do
			if current.Name == category then
				return category
			end
		end
		current = current.Parent
	end

	-- Default to Misc if no category found
	return "Misc"
end

-- [ MODULE FUNCTIONS ]--

module.Play = function(Audio_Name : string, Object : Part, Properties)

	if module.Audios[Audio_Name] ~= nil then

		local AudioTrack : Sound = module.Audios[Audio_Name]:Clone()

		local ScreenTrack = Properties.ScreenTrack or false
		local Weld = Properties.Weld or false

		local NewInstance = Properties.NewInstance or true

		local CFrameOption

		local CFrameTarget = (Object ~= nil and Object.CFrame) or Properties.CFrame or error(`object or cframe was not given for {Audio_Name}!`)
		local WeldOffset = Properties.WeldOffset or CFrame.new(0,0,0)
		local IgnoreTimeScale = Properties.IgnoreTimeScale or false -- ✅ NEW

		local Debug = Properties.Debug or false

		local Looped = Properties.Looped or AudioTrack.Looped
		local Volume = Properties.Volume or AudioTrack.Volume
		local TimePosition = Properties.TimePosition or 0
		local RollOffMode = Properties.RollOffMode or AudioTrack.RollOffMode
		local RollOffMinDistance = Properties.RollOffMinDistance or (if AudioTrack.RollOffMinDistance < 1000 then AudioTrack.RollOffMinDistance else 300)
		local RollOffMaxDistance = Properties.RollOffMaxDistance or (if AudioTrack.RollOffMaxDistance < 1000 then AudioTrack.RollOffMaxDistance else 300)

		-- warn(TimePosition, Audio_Name)

		AudioTrack.Looped = Looped
		AudioTrack.Volume = Volume
		AudioTrack.RollOffMode = RollOffMode
		AudioTrack.RollOffMinDistance = RollOffMinDistance
		AudioTrack.RollOffMaxDistance = RollOffMaxDistance

		-- Assign to the correct SoundGroup
		local soundGroupName = module.SoundGroups[Audio_Name] or "Misc"
		local soundGroup = SoundService:FindFirstChild("Master")
		if soundGroup then
			soundGroup = soundGroup:FindFirstChild(soundGroupName)
		end

		if soundGroup and soundGroup:IsA("SoundGroup") then
			AudioTrack.SoundGroup = soundGroup
		else
			warn(`SoundGroup not found for category: {soundGroupName}. Audio will play without volume control.`)
		end

		local ID = AbsurfUtility.GenerateID()
		module.Cache[ID] = {

			["Misc"] = {},
			["Audio"] = AudioTrack,
			["AudioName"] = Audio_Name,
			["IgnoreTimeScale"] = IgnoreTimeScale, -- ✅ NEW
			["Cleanup"] = nil
		}

		if ScreenTrack == true then
			AudioTrack.Parent = game.Workspace

		else
			if NewInstance == true then

				local Part = Instance.new("Part", game.Workspace)
				Part.CanQuery = false
				Part.CanCollide = false
				Part.Size = Vector3.new(1,1,1)
				Part.Color = Color3.fromRGB(255, 0, 4)
				Part.Transparency = if Debug == true then 0.75 else 1

				AudioTrack.Parent = Part

				table.insert(module.Cache[ID].Misc, Part)

				if Weld == true then
					Part.Anchored = false

					local weld = Instance.new("Weld", Part)
					weld.Part0 = Part
					weld.Part1 = Object
					weld.C0 = WeldOffset

					table.insert(module.Cache[ID].Misc, weld)

				else
					Part.Anchored = true
					Part.CFrame = CFrameTarget
				end

			else

				if Object == nil then
					warn(`Object must be given for this audio track: {Audio_Name}! Deleting.`)
					module.Cache[ID] = nil

				else
					AudioTrack.Parent = Object
				end

			end

		end

		module.Cache[ID].Cleanup = function()

			if module.Cache[ID].FadeConnection then
				module.Cache[ID].FadeConnection:Disconnect()
				module.Cache[ID].FadeConnection = nil
			end

			AudioTrack:Destroy()

			for i,v in pairs(module.Cache[ID].Misc) do
				v:Destroy()
			end

			module.Cache[ID] = nil

		end

		AudioTrack.TimePosition = TimePosition
		AudioTrack:Play()

		AudioTrack.Ended:Connect(function()
			module.Cache[ID].Cleanup()

		end)

		AudioTrack.Stopped:Connect(function()
			module.Cache[ID].Cleanup()
		end)

		return AudioTrack, ID

	else
		warn(`{Audio_Name} does not exist.`)

	end

end

module.Stop = function(Tag_ID : string, AudioName : string, FadeOutInfo)

	if Tag_ID == nil and AudioName == nil then return end

	local function HandleStop(Info)

		if Info.FadeConnection then
			Info.FadeConnection:Disconnect()
			Info.FadeConnection = nil
		end

		if FadeOutInfo and FadeOutInfo.Duration and FadeOutInfo.EasingStyle then
			-- Fade out the audio
			local Audio = Info.Audio
			local StartVolume = Audio.Volume
			local Duration = FadeOutInfo.Duration
			local EasingStyle = FadeOutInfo.EasingStyle

			local Elapsed = 0
			local FadeConnection

			FadeConnection = RunService.Heartbeat:Connect(function(dt)
				Elapsed += dt
				local Alpha = math.clamp(Elapsed / Duration, 0, 1)
				local EasedAlpha = AbsurfUtility.ReturnEasing(EasingStyle, Alpha)

				-- Fade from StartVolume to 0
				Audio.Volume = StartVolume * (1 - EasedAlpha)

				if Alpha >= 1 then
					FadeConnection:Disconnect()
					Info.FadeConnection = nil
					Audio:Stop()
				end
			end)

			Info.FadeConnection = FadeConnection

		else
			-- Instant stop (legacy behavior)
			Info.Audio:Stop()
		end
	end

	if Tag_ID ~= nil then
		for TagID, Info in pairs(module.Cache) do
			if Tag_ID == TagID then
				HandleStop(Info)
				break
			end
		end

	else
		for TagID, Info in pairs(module.Cache) do
			if AudioName == Info.AudioName then
				HandleStop(Info)
			end
		end
	end

end

-- [ SETUP ]--
for i,v in pairs(Sounds_Folder:GetDescendants()) do
	if v:IsA("Sound") then
		module.Audios[v.Name] = v

		local category = GetSoundCategory(v)
		module.SoundGroups[v.Name] = category

	end

	-- warn(`SOUNDS STUFF!!`, module)

end

return module
