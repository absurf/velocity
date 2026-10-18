local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpeedConfig = require(ReplicatedStorage.Shared.Modules.Configs.SpeedConfig)
local Generated = require(ReplicatedStorage.Shared.Modules.Speed.Courses.Generated)

local Service = {}
type Service = typeof(Service)

local PREFIX = "Map_"

-- [ STATE ]--
local CurrentMap: Model? = nil
local Seeds = Random.new()
local Judge = SpeedConfig.Judge ~= nil and SpeedConfig.Judge.On == true   -- (starts as the config says)

local function Courses(): Instance
	local world = workspace:FindFirstChild("World")
	if not world then
		world = Instance.new("Folder")
		world.Name = "World"
		world.Parent = workspace
	end
	local folder = world:FindFirstChild(SpeedConfig.Courses or "Courses")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = SpeedConfig.Courses or "Courses"
		folder.Parent = world
	end
	return folder
end

function Service.New(_self: Service, seed: number?, pieces: string?): (Model, any)
	seed = math.floor(tonumber(seed) or Seeds:NextInteger(1, 999999))
	local data = Generated.Build(seed, pieces, Judge)
	local model = Generated.MakeModel(data)
	local folder = Courses()
	for _, old in folder:GetChildren() do
		if old.Name:sub(1, #PREFIX) == PREFIX and old ~= model then old:Destroy() end
	end
	model.Parent = folder
	CurrentMap = model
	return model, data
end

function Service.Judge(_self: Service): boolean
	return Judge
end

function Service.SetJudge(_self: Service, on: boolean)
	Judge = on == true
end

function Service.Current(_self: Service): Model?
	return if CurrentMap and CurrentMap.Parent then CurrentMap else nil
end

return Service :: Service
