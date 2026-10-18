local RunService          = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService     = game:GetService("UserInputService")

local Input         = require(script.Input)
local PreferredInput = Input.PreferredInput
local GamepadClass  = Input.Gamepad

local InputServiceClient = {}

InputServiceClient.CurrentInputType = PreferredInput.Current :: string

local _inputTypeSubscribers: { (inputType: string) -> () } = {}

InputServiceClient.GamepadStyle = "Xbox"

local _styleSubscribers: { (style: string) -> () } = {}

local _gamepad = GamepadClass.new()

local _activeGroups = {}

local _registeredActions = {}

local _blocked: { [string]: true } = {}

local function BuildInputs(keys: {}): { any }
	local inputs = {}
	local function TryAdd(keyStr: string?)
		if not keyStr or keyStr == "" then return end
		if keyStr == "MouseButton1" then
			table.insert(inputs, Enum.UserInputType.MouseButton1)
		elseif keyStr == "MouseButton2" then
			table.insert(inputs, Enum.UserInputType.MouseButton2)
		elseif keyStr == "MouseWheel" then

			table.insert(inputs, Enum.UserInputType.MouseWheel)
		else
			local ok, kc = pcall(function() return Enum.KeyCode[keyStr] end)
			if ok and kc then table.insert(inputs, kc) end
		end
	end
	TryAdd(keys.MouseKeyboard)
	TryAdd(keys.Gamepad)
	TryAdd(keys.Touch)
	return inputs
end

function InputServiceClient.RegisterAction(groupName: string, actionName: string, keys: {}, handler: (...any) -> (), always: boolean?)
	if not _registeredActions[groupName] then
		_registeredActions[groupName] = {}
	end
	_registeredActions[groupName][actionName] = { keys = keys, handler = handler, always = always == true }
end

function InputServiceClient.BindGroup(groupName: string)
	local actions = _registeredActions[groupName]
	if not actions then
		warn("InputServiceClient.BindGroup: no actions registered for group '", groupName, "'")
		return
	end
	-- Unbind first to avoid duplicates
	for actionName in pairs(actions) do
		ContextActionService:UnbindAction(actionName)
	end
	_activeGroups[groupName] = true
	for actionName, data in pairs(actions) do
		local inputs = BuildInputs(data.keys)
		if #inputs > 0 then
			local handler = data.handler
			ContextActionService:BindAction(actionName, function(_name, state, input)

				if next(_blocked) and not data.always and (state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change) then
					return Enum.ContextActionResult.Sink
				end
				return handler(state, input)
			end, false, table.unpack(inputs))
		end
	end
end

function InputServiceClient.UnbindGroup(groupName: string)
	local actions = _registeredActions[groupName]
	if not actions then return end
	_activeGroups[groupName] = nil
	for actionName in pairs(actions) do
		ContextActionService:UnbindAction(actionName)
	end
end

function InputServiceClient.SetBlocked(reason: string, blocked: boolean)
	local was = next(_blocked) ~= nil
	_blocked[reason] = if blocked then true else nil
	if was or not blocked then return end
	for groupName in pairs(_activeGroups) do
		for _, data in pairs(_registeredActions[groupName] or {}) do
			if not data.always then pcall(data.handler, Enum.UserInputState.Cancel, nil) end
		end
	end
end

function InputServiceClient.IsGroupActive(groupName: string): boolean
	return _activeGroups[groupName] == true
end

local GAMEPAD_INPUTS = {}
for i = 1, 8 do GAMEPAD_INPUTS[Enum.UserInputType["Gamepad" .. i]] = true end

local function ProbeGamepadStyle()
	local ok, name = pcall(UserInputService.GetStringForKeyCode, UserInputService, Enum.KeyCode.ButtonA)
	local style = if ok and name == "ButtonCross" then "PlayStation" else "Xbox"
	if style == InputServiceClient.GamepadStyle then return end
	InputServiceClient.GamepadStyle = style
	for _, sub in ipairs(_styleSubscribers) do
		task.spawn(sub, style)
	end
	warn("[InputServiceClient] Gamepad style:", style)
end
ProbeGamepadStyle()

UserInputService.GamepadConnected:Connect(ProbeGamepadStyle)
UserInputService.GamepadDisconnected:Connect(ProbeGamepadStyle)
UserInputService.InputBegan:Connect(function(input)
	if GAMEPAD_INPUTS[input.UserInputType] then ProbeGamepadStyle() end
end)

PreferredInput.Observe(function(preferred: string)
	InputServiceClient.CurrentInputType = preferred

	if preferred == "Gamepad" then ProbeGamepadStyle() end

	local groups = {}
	for groupName in pairs(_activeGroups) do
		table.insert(groups, groupName)
	end
	for _, groupName in ipairs(groups) do
		InputServiceClient.UnbindGroup(groupName)
		InputServiceClient.BindGroup(groupName)
	end

	for _, sub in ipairs(_inputTypeSubscribers) do
		task.spawn(sub, preferred)
	end

	warn("[InputServiceClient] Input type:", preferred)
end)

function InputServiceClient.ObserveInputType(handler: (inputType: string) -> ()): () -> ()
	table.insert(_inputTypeSubscribers, handler)
	task.spawn(handler, InputServiceClient.CurrentInputType)
	return function()
		local i = table.find(_inputTypeSubscribers, handler)
		if i then table.remove(_inputTypeSubscribers, i) end
	end
end

function InputServiceClient.ObserveGamepadStyle(handler: (style: string) -> ()): () -> ()
	table.insert(_styleSubscribers, handler)
	task.spawn(handler, InputServiceClient.GamepadStyle)
	return function()
		local i = table.find(_styleSubscribers, handler)
		if i then table.remove(_styleSubscribers, i) end
	end
end

_gamepad.Connected:Connect(function()
	warn("[InputServiceClient] Gamepad connected:", _gamepad:GetUserInputType())
end)

_gamepad.Disconnected:Connect(function()
	warn("[InputServiceClient] Gamepad disconnected")
end)

function InputServiceClient.GetGamepad()
	return _gamepad
end

function InputServiceClient.Cleanup()
	for groupName in pairs(_activeGroups) do
		InputServiceClient.UnbindGroup(groupName)
	end
	_gamepad:Destroy()
end

function InputServiceClient.Init()

end

return InputServiceClient
