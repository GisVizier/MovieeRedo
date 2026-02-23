local Visuals = {}

local cachedBulletsByModel = setmetatable({}, { __mode = "k" })
local BULLET_NAMES = { "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8" }

local function applyVisibility(target, isVisible)
	pcall(function()
		if target:IsA("BasePart") then
			target.LocalTransparencyModifier = isVisible and 0 or 1
		elseif target:IsA("Decal") or target:IsA("Texture") then
			target.Transparency = isVisible and 0 or 1
		elseif target:IsA("ParticleEmitter") or target:IsA("Trail") or target:IsA("Beam") then
			target.Enabled = isVisible
		end
	end)
end

local function getBulletParts(model)
	local cached = cachedBulletsByModel[model]
	if cached then
		return cached
	end

	local bulletsFolder = model:FindFirstChild("Bullets", true)
	if not bulletsFolder then
		cachedBulletsByModel[model] = {}
		return {}
	end

	local targets = {}
	for _, name in ipairs(BULLET_NAMES) do
		local bullet = bulletsFolder:FindFirstChild(name, true)
		if bullet then
			table.insert(targets, bullet)
		end
	end

	if #targets == 0 then
		local fallback = {}
		for _, desc in ipairs(bulletsFolder:GetDescendants()) do
			local index = tonumber(string.match(desc.Name, "^B(%d+)$"))
			if index then
				table.insert(fallback, {
					index = index,
					part = desc,
				})
			end
		end
		table.sort(fallback, function(a, b)
			return a.index < b.index
		end)
		for _, entry in ipairs(fallback) do
			table.insert(targets, entry.part)
		end
	end

	cachedBulletsByModel[model] = targets
	return targets
end

local function getRigModel(weaponInstance)
	if not weaponInstance or type(weaponInstance.GetRig) ~= "function" then
		return nil
	end

	local rig = weaponInstance.GetRig()
	return rig and rig.Model or nil
end

function Visuals.UpdateAmmoVisibility(weaponInstance, currentAmmo, clipSize)
	local model = getRigModel(weaponInstance)
	if not model then
		return
	end

	local bullets = getBulletParts(model)
	if #bullets == 0 then
		return
	end

	local maxClip = math.max(math.floor(tonumber(clipSize) or #bullets), 0)
	local activeSlots = math.min(maxClip, #bullets)
	local ammo = math.clamp(math.floor(tonumber(currentAmmo) or 0), 0, activeSlots)
	local consumed = math.clamp(activeSlots - ammo, 0, activeSlots)

	for i, target in ipairs(bullets) do
		if target and target.Parent then
			local isVisible = false
			if i <= activeSlots then
				isVisible = i > consumed
			end
			applyVisibility(target, isVisible)
		end
	end
end

function Visuals.SetAllVisible(weaponInstance, isVisible, clipSize)
	local model = getRigModel(weaponInstance)
	if not model then
		return
	end

	local bullets = getBulletParts(model)
	if #bullets == 0 then
		return
	end

	local maxClip = math.max(math.floor(tonumber(clipSize) or #bullets), 0)
	local activeSlots = math.min(maxClip, #bullets)
	for i, target in ipairs(bullets) do
		if target and target.Parent then
			local shouldShow = (i <= activeSlots) and (isVisible == true)
			applyVisibility(target, shouldShow)
		end
	end
end

return Visuals
