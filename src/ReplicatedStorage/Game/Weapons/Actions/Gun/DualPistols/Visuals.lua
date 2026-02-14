local Visuals = {}

local cachedTargetsByModel = setmetatable({}, { __mode = "k" })

local function isAmmoVisualName(name)
	if type(name) ~= "string" then
		return false
	end

	local lowerName = string.lower(name)
	return string.find(lowerName, "mag", 1, true) ~= nil or string.find(lowerName, "ammo", 1, true) ~= nil
end

local function getTargets(model)
	local cachedTargets = cachedTargetsByModel[model]
	if cachedTargets then
		return cachedTargets
	end

	local targets = {}
	for _, desc in model:GetDescendants() do
		if isAmmoVisualName(desc.Name) then
			table.insert(targets, desc)
		end
	end

	cachedTargetsByModel[model] = targets
	return targets
end

local function applyTransparency(target, value)
	pcall(function()
		if target:IsA("BasePart") then
			target.LocalTransparencyModifier = value
		elseif target:IsA("Decal") or target:IsA("Texture") then
			target.Transparency = value
		elseif target:IsA("ParticleEmitter") or target:IsA("Trail") or target:IsA("Beam") then
			target.Enabled = value < 1
		end
	end)
end

function Visuals.UpdateAmmoVisibility(weaponInstance, currentAmmo)
	if not weaponInstance or type(weaponInstance.GetRig) ~= "function" then
		return
	end

	local rig = weaponInstance.GetRig()
	local model = rig and rig.Model
	if not model then
		return
	end

	local shouldHide = (currentAmmo or 0) <= 0
	local transparencyValue = shouldHide and 1 or 0
	local targets = getTargets(model)

	for _, target in targets do
		if target and target.Parent then
			applyTransparency(target, transparencyValue)
		end
	end
end

return Visuals
