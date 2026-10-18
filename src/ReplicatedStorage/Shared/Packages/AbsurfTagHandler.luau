local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TaskScheduler = require(ReplicatedStorage.Shared.Packages.AbsurfTaskScheduler)

local Tags = {}

local PREFIX = "Tag_"
local IS_SERVER = RunService:IsServer()

export type Hook = { Start: ((Instance) -> ())?, End: ((Instance) -> ())? }
type Entry = { Id: number, Name: string, Object: Instance, EndsAt: number? }
type Record = { Tags: { [string]: { [number]: Entry } }, Destroying: RBXScriptConnection }

-- [ STATE ]--
local Records: { [Instance]: Record } = {}
local Hooks: { [string]: Hook } = {}
local Timed: { [number]: Entry } = {}
local ExpiryTask: string? = nil
local NextId = 0

local function Switched(object: Instance, name: string, on: boolean, quiet: boolean)
	if quiet then return end
	if IS_SERVER then object:SetAttribute(PREFIX .. name, if on then true else nil) end
	local hook = Hooks[name]
	local run = hook and (if on then hook.Start else hook.End)
	if run then task.spawn(run, object) end
end

local function Finish(entry: Entry, quiet: boolean)
	local record = Records[entry.Object]
	local list = record and record.Tags[entry.Name]
	if not list or not list[entry.Id] then return end   -- ended already
	list[entry.Id] = nil
	Timed[entry.Id] = nil
	if next(list) ~= nil then return end
	record.Tags[entry.Name] = nil
	if next(record.Tags) == nil then
		record.Destroying:Disconnect()
		Records[entry.Object] = nil
	end
	Switched(entry.Object, entry.Name, false, quiet)
end

local function ClearAll(object: Instance, quiet: boolean)
	local record = Records[object]
	if not record then return end
	local entries = {}
	for _, list in record.Tags do
		for _, entry in list do table.insert(entries, entry) end
	end
	for _, entry in entries do Finish(entry, quiet) end
end

local function Expire()
	local now = os.clock()
	local due = {}
	for _, entry in Timed do
		if now >= entry.EndsAt :: number then table.insert(due, entry) end
	end
	for _, entry in due do Finish(entry, false) end
	if next(Timed) == nil and ExpiryTask then
		TaskScheduler.RemoveTask(ExpiryTask, false)
		ExpiryTask = nil
	end
end

function Tags.Add(object: Instance, name: string, seconds: number?): number
	assert(typeof(object) == "Instance", "Tags.Add: tag an Instance")
	assert(type(name) == "string" and name ~= "", "Tags.Add: a tag name")
	assert(seconds == nil or (type(seconds) == "number" and seconds >= 0), "Tags.Add: seconds >= 0, or nil")
	local record = Records[object]
	if not record then
		record = {
			Tags = {},
			Destroying = object.Destroying:Connect(function() ClearAll(object, true) end),
		}
		Records[object] = record
	end
	NextId += 1
	local entry: Entry = { Id = NextId, Name = name, Object = object, EndsAt = if seconds then os.clock() + seconds else nil }
	local list = record.Tags[name]
	local fresh = list == nil
	if not list then
		list = {}
		record.Tags[name] = list
	end
	list[entry.Id] = entry
	if entry.EndsAt then
		Timed[entry.Id] = entry
		if not ExpiryTask then ExpiryTask = TaskScheduler.Add(Expire) end
	end
	if fresh then Switched(object, name, true, false) end
	return entry.Id
end

function Tags.Remove(object: Instance, which: string | number)
	local record = Records[object]
	if not record then return end
	if type(which) == "number" then
		for _, list in record.Tags do
			local entry = list[which]
			if entry then
				Finish(entry, false)
				return
			end
		end
		return
	end
	local list = record.Tags[which]
	if not list then return end
	local entries = {}
	for _, entry in list do table.insert(entries, entry) end
	for _, entry in entries do Finish(entry, false) end   -- the last one switches it off, once
end

function Tags.Has(object: Instance?, name: string): boolean
	if not object then return false end
	local record = Records[object]
	if record and record.Tags[name] then return true end
	return not IS_SERVER and object:GetAttribute(PREFIX .. name) == true
end

function Tags.Changed(object: Instance, name: string): RBXScriptSignal
	return object:GetAttributeChangedSignal(PREFIX .. name)
end

function Tags.Hook(name: string, hook: Hook)
	assert(type(name) == "string" and name ~= "", "Tags.Hook: a tag name")
	assert(Hooks[name] == nil, "Tags.Hook: '" .. name .. "' already has an owner")
	Hooks[name] = hook
end

function Tags.Clear(object: Instance)
	ClearAll(object, false)
end

return Tags
