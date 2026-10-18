local FadeGroup = {}
FadeGroup.__index = FadeGroup

type Entry = { Object: Instance, Property: string, Authored: any }

function FadeGroup.new(roots: { Instance })
	local entries: { Entry } = {}
	local function add(object: Instance, property: string)
		table.insert(entries, { Object = object, Property = property, Authored = (object :: any)[property] })
	end
	local function visit(inst: Instance)
		if inst:IsA("UIGradient") or inst:IsA("UIStroke") then
			add(inst, "Transparency")
		elseif inst:IsA("GuiObject") and not inst:FindFirstChildOfClass("UIGradient") then
			if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
				add(inst, "ImageTransparency")
			elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
				add(inst, "TextTransparency")
			end
			if inst.BackgroundTransparency < 1 then
				add(inst, "BackgroundTransparency")
			end
		end
		for _, child in inst:GetChildren() do
			visit(child)
		end
	end
	for _, root in roots do
		visit(root)
	end
	return setmetatable({ _entries = entries }, FadeGroup)
end

local function faded(authored: number, alpha: number): number
	return 1 - (1 - authored) * alpha
end

function FadeGroup.Set(self, alpha: number)
	for _, entry in self._entries do
		local authored = entry.Authored
		if typeof(authored) == "NumberSequence" then
			local points = {}
			for i, point in authored.Keypoints do
				points[i] = NumberSequenceKeypoint.new(point.Time, faded(point.Value, alpha), point.Envelope)
			end
			(entry.Object :: any)[entry.Property] = NumberSequence.new(points)
		else
			(entry.Object :: any)[entry.Property] = faded(authored, alpha)
		end
	end
end

return FadeGroup
