local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local AbilityUtils = {}

function AbilityUtils.GetLookPosition(player, maxDistance)
	maxDistance = maxDistance or 1000

	local character = player.Character
	if not character then
		return nil
	end

	local camera = workspace.CurrentCamera
	if not camera then
		local head = character:FindFirstChild("Head")
		if head then
			local origin = head.Position
			local direction = head.CFrame.LookVector * maxDistance
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = { character }
			local result = workspace:Raycast(origin, direction, rayParams)
			if result then
				return result.Position, result.Normal, result.Instance
			end
			return origin + direction, Vector3.yAxis, nil
		end
		return nil
	end

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * maxDistance

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(origin, direction, rayParams)

	if result then
		return result.Position, result.Normal, result.Instance
	end

	return origin + direction, Vector3.yAxis, nil
end

function AbilityUtils.GetTargetsInRadius(origin, radius, excludePlayer, filterFunc)
	local targets = {}

	for _, player in pairs(Players:GetPlayers()) do
		if player ~= excludePlayer and player.Character then
			local root = player.Character:FindFirstChild("HumanoidRootPart")
				or player.Character:FindFirstChild("Root")
				or player.Character.PrimaryPart

			if root then
				local distance = (root.Position - origin).Magnitude
				if distance <= radius then
					if not filterFunc or filterFunc(player) then
						table.insert(targets, {
							Player = player,
							Character = player.Character,
							Distance = distance,
							Position = root.Position,
						})
					end
				end
			end
		end
	end

	table.sort(targets, function(a, b)
		return a.Distance < b.Distance
	end)

	return targets
end

function AbilityUtils.GetClosestTarget(origin, maxDistance, excludePlayer, filterFunc)
	local targets = AbilityUtils.GetTargetsInRadius(origin, maxDistance, excludePlayer, filterFunc)
	return targets[1]
end

function AbilityUtils.GetTargetsInCone(origin, direction, angle, maxDistance, excludePlayer)
	local targets = {}
	local halfAngle = math.rad(angle / 2)

	for _, player in pairs(Players:GetPlayers()) do
		if player ~= excludePlayer and player.Character then
			local root = player.Character:FindFirstChild("HumanoidRootPart")
				or player.Character:FindFirstChild("Root")
				or player.Character.PrimaryPart

			if root then
				local toTarget = (root.Position - origin)
				local distance = toTarget.Magnitude

				if distance <= maxDistance then
					local targetDir = toTarget.Unit
					local dotProduct = direction.Unit:Dot(targetDir)
					local angleToTarget = math.acos(math.clamp(dotProduct, -1, 1))

					if angleToTarget <= halfAngle then
						table.insert(targets, {
							Player = player,
							Character = player.Character,
							Distance = distance,
							Position = root.Position,
							Angle = math.deg(angleToTarget),
						})
					end
				end
			end
		end
	end

	table.sort(targets, function(a, b)
		return a.Distance < b.Distance
	end)

	return targets
end

function AbilityUtils.IsLineOfSight(origin, targetPosition, ignoreList)
	local direction = targetPosition - origin
	local distance = direction.Magnitude

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignoreList or {}

	local result = workspace:Raycast(origin, direction.Unit * distance, rayParams)

	if result then
		local hitDistance = (result.Position - origin).Magnitude
		return hitDistance >= distance * 0.95
	end

	return true
end

function AbilityUtils.GetGroundPosition(position, maxDistance)
	maxDistance = maxDistance or 100

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {}

	local result = workspace:Raycast(position, Vector3.new(0, -maxDistance, 0), rayParams)

	if result then
		return result.Position, result.Normal, result.Instance
	end

	return nil
end

function AbilityUtils.ApplyDamage(target, damage, attacker, isHeadshot)
	if not target or not target.Character then
		return false
	end

	local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	if attacker then
		humanoid:SetAttribute("LastDamageDealer", attacker.UserId)
		humanoid:SetAttribute("WasHeadshot", isHeadshot or false)
	end

	humanoid:TakeDamage(damage)

	return true
end

function AbilityUtils.Heal(target, amount)
	if not target or not target.Character then
		return false
	end

	local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	humanoid.Health = math.min(humanoid.Health + amount, humanoid.MaxHealth)

	return true
end

function AbilityUtils.GetCharacterVelocity(character)
	if not character then
		return Vector3.zero
	end

	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart

	if root then
		return root.AssemblyLinearVelocity
	end

	return Vector3.zero
end

function AbilityUtils.SetCharacterVelocity(character, velocity)
	if not character then
		return false
	end

	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart

	if root then
		root.AssemblyLinearVelocity = velocity
		return true
	end

	return false
end

function AbilityUtils.ApplyImpulse(character, impulse)
	if not character then
		return false
	end

	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart

	if root then
		root:ApplyImpulse(impulse)
		return true
	end

	return false
end

function AbilityUtils.LerpPosition(startPos, endPos, alpha)
	return startPos:Lerp(endPos, alpha)
end

function AbilityUtils.BezierPosition(p0, p1, p2, t)
	local l1 = p0:Lerp(p1, t)
	local l2 = p1:Lerp(p2, t)
	return l1:Lerp(l2, t)
end

return AbilityUtils
