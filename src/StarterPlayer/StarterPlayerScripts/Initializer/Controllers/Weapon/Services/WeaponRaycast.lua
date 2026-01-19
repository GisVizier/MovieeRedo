local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WeaponRaycast = {}

function WeaponRaycast.GetSpreadDirection(baseDirection, spread)
	local angle = math.random() * math.pi * 2
	local radius = math.random() * spread
	local offset = Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)

	local basis = CFrame.lookAt(Vector3.zero, baseDirection)
	local right = basis.RightVector
	local up = basis.UpVector

	return (baseDirection + right * offset.X + up * offset.Y).Unit
end

function WeaponRaycast.GeneratePelletDirections(camera, weaponConfig)
	if not camera then
		return nil
	end

	local baseDirection = camera.CFrame.LookVector.Unit
	local spread = weaponConfig.spread or 0.05
	local pellets = weaponConfig.pelletsPerShot or 1
	local directions = {}

	for _ = 1, pellets do
		table.insert(directions, WeaponRaycast.GetSpreadDirection(baseDirection, spread))
	end

	return directions
end

function WeaponRaycast.PerformRaycast(camera, localPlayer, weaponConfig, ignoreSpread)
	if not camera then
		return nil
	end

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector.Unit
	local range = weaponConfig.range or 500

	if not ignoreSpread and weaponConfig.spread and weaponConfig.spread > 0 then
		direction = WeaponRaycast.GetSpreadDirection(direction, weaponConfig.spread)
	end

	local targetPosition = origin + direction * range

	if weaponConfig.projectileSpeed and weaponConfig.bulletDrop then
		local distance = range
		local travelTime = distance / weaponConfig.projectileSpeed
		local gravity = weaponConfig.gravity or Workspace.Gravity
		local dropAmount = 0.5 * gravity * (travelTime ^ 2)
		targetPosition = targetPosition - Vector3.new(0, dropAmount, 0)
		direction = (targetPosition - origin).Unit
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local character = localPlayer and localPlayer.Character
	local filterList = { camera }
	if character then
		table.insert(filterList, character)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local result = Workspace:Raycast(origin, direction * range, raycastParams)

	if result then
		local hitPlayer = Players:GetPlayerFromCharacter(result.Instance.Parent)
		local isHeadshot = result.Instance.Name == "Head"

		local hitCharacter = nil
		if result.Instance.Parent:FindFirstChildOfClass("Humanoid") then
			hitCharacter = result.Instance.Parent
		end

		return {
			origin = origin,
			direction = direction,
			hitPart = result.Instance,
			hitPosition = result.Position,
			hitPlayer = hitPlayer,
			hitCharacter = hitCharacter,
			isHeadshot = isHeadshot,
			travelTime = weaponConfig.projectileSpeed
				and (result.Position - origin).Magnitude / weaponConfig.projectileSpeed,
		}
	end

	return {
		origin = origin,
		direction = direction,
		hitPart = nil,
		hitPosition = targetPosition,
		hitPlayer = nil,
		isHeadshot = false,
	}
end

return WeaponRaycast
