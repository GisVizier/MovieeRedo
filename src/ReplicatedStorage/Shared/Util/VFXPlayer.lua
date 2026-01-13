local Debris = game:GetService("Debris")

local VFXPlayer = {}

-- One-shot spawn at a world position.
-- Template must be Folder or effect instance (ParticleEmitter/Beam/Trail/Light).
function VFXPlayer:Play(template: Instance, position: Vector3, lifetime: number?)
	if typeof(position) ~= "Vector3" or typeof(template) ~= "Instance" then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "VFXAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Massless = true
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	local att = Instance.new("Attachment")
	att.Name = "VFX"
	att.Parent = anchor

	local clone = template:Clone()
	clone.Parent = att

	local lt = lifetime
	if type(lt) ~= "number" then
		local attr = template:GetAttribute("Lifetime")
		if type(attr) == "number" then
			lt = attr
		else
			lt = 0.5
		end
	end

	Debris:AddItem(anchor, lt)
end

-- Continuous attach to a BasePart; stop by key.
VFXPlayer._active = {}

function VFXPlayer:Start(key: string, template: Instance, part: BasePart)
	if type(key) ~= "string" or key == "" then
		return
	end
	if typeof(template) ~= "Instance" or typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	if self._active[key] then
		return
	end

	local att = Instance.new("Attachment")
	att.Name = "VFX_" .. key
	att.Parent = part

	local clone = template:Clone()
	clone.Parent = att

	self._active[key] = att
end

function VFXPlayer:Stop(key: string)
	local att = self._active[key]
	if att and att.Parent then
		att:Destroy()
	end
	self._active[key] = nil
end

function VFXPlayer:IsActive(key: string): boolean
	return self._active[key] ~= nil
end

function VFXPlayer:UpdateYaw(key: string, direction: Vector3)
	local att = self._active[key]
	if not att or not att.Parent then
		return
	end
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	flat = flat.Unit
	local yaw = math.atan2(-flat.X, -flat.Z)
	att.CFrame = CFrame.Angles(0, yaw, 0)
end

return VFXPlayer

