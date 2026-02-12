local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WeaponRaycast = {}
local TrainingRangeShot = nil

-- Debug flag (set to true to see hit logs)
local DEBUG_LOGGING = false

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

--[[
	Traverse up from a hit part to find the character model or rig owner.
	Handles:
	- Character/Collider/Default/Part (standing hitbox)
	- Character/Collider/Crouch/Part (crouching hitbox)
	- Character/Hitbox/Part (player hitbox folder)
	- Dummy/Root/Part (dummy hitbox structure)
	- Character/Part (direct body part hits)
	- Rig/Part (visual rig with OwnerUserId attribute)
]]
local function getCharacterFromPart(part)
	if not part then
		return nil
	end

	local current = part.Parent

	-- Handle new Hitbox structure: Character/Collider/Hitbox/Standing|Crouching/Part
	if current and (current.Name == "Standing" or current.Name == "Crouching") then
		local hitboxFolder = current.Parent
		if hitboxFolder and hitboxFolder.Name == "Hitbox" then
			local colliderFolder = hitboxFolder.Parent
			if colliderFolder and colliderFolder.Name == "Collider" then
				-- Check for OwnerUserId on Collider folder
				local ownerUserId = colliderFolder:GetAttribute("OwnerUserId")
				if ownerUserId then
					local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
					-- Fallback for test clients with negative IDs
					if not ownerPlayer then
						for _, player in Players:GetPlayers() do
							if player.UserId == ownerUserId then
								ownerPlayer = player
								break
							end
						end
					end
					if ownerPlayer and ownerPlayer.Character then
						return ownerPlayer.Character
					end
				end
				-- Fallback to parent of Collider (should be the character model)
				local characterModel = colliderFolder.Parent
				-- Use recursive search for nested Humanoids (e.g., dummies with Rig subfolder)
				if
					characterModel
					and characterModel:IsA("Model")
					and characterModel:FindFirstChildWhichIsA("Humanoid", true)
				then
					return characterModel
				end
				current = characterModel
			end
		end
	end

	-- Handle legacy Collider structure: Character/Collider/Default|Crouch/Part
	if current and (current.Name == "Default" or current.Name == "Crouch") then
		local colliderFolder = current.Parent
		if colliderFolder and colliderFolder.Name == "Collider" then
			local ownerUserId = colliderFolder:GetAttribute("OwnerUserId")
			if ownerUserId then
				local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
				if not ownerPlayer then
					for _, player in Players:GetPlayers() do
						if player.UserId == ownerUserId then
							ownerPlayer = player
							break
						end
					end
				end
				if ownerPlayer and ownerPlayer.Character then
					return ownerPlayer.Character
				end
			end
			local characterModel = colliderFolder.Parent
			-- Use recursive search for nested Humanoids (e.g., dummies with Rig subfolder)
			if
				characterModel
				and characterModel:IsA("Model")
				and characterModel:FindFirstChildWhichIsA("Humanoid", true)
			then
				return characterModel
			end
			current = characterModel
		end
	end

	-- Handle Hitbox folder: Character/Hitbox/Part
	if current and current.Name == "Hitbox" and current:IsA("Folder") then
		current = current.Parent
	end

	-- Handle Root folder (dummies): Dummy/Root/Part
	if current and current.Name == "Root" then
		current = current.Parent
	end

	-- Search up for a character model (has Humanoid)
	local searchCurrent = current
	while searchCurrent and searchCurrent ~= Workspace do
		if searchCurrent:IsA("Model") then
			-- Check if it's a character (has Humanoid) - use recursive search for nested Humanoids
			if searchCurrent:FindFirstChildWhichIsA("Humanoid", true) then
				return searchCurrent
			end

			-- Check if it's a Rig or Collider (has OwnerUserId attribute)
			local ownerUserId = searchCurrent:GetAttribute("OwnerUserId")
			if ownerUserId then
				local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
				if ownerPlayer and ownerPlayer.Character then
					return ownerPlayer.Character
				end
			end
		end
		searchCurrent = searchCurrent.Parent
	end

	return nil
end

--[[
	Check if a hit part is a headshot.
	Handles hitbox parts and regular character parts.
]]
local function isHeadshotPart(part)
	if not part then
		return false
	end

	local name = part.Name
	return name == "Head" or name == "CrouchHead" or name == "HitboxHead"
end

-- =============================================================================
-- SPREAD CALCULATION
-- =============================================================================

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

-- =============================================================================
-- MAIN RAYCAST
-- =============================================================================

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
	-- Exclude effects folder (kit VFX, blue projectile, etc.)
	local effectsFolder = Workspace:FindFirstChild("Effects")
	if effectsFolder then
		table.insert(filterList, effectsFolder)
	end
	-- Exclude VoxelDestruction cached/debris parts so hitscan passes through rubble
	local voxelCache = Workspace:FindFirstChild("VoxelCache")
	if voxelCache then
		table.insert(filterList, voxelCache)
	end
	-- Exclude voxel destruction record clones
	local destructionFolder = Workspace:FindFirstChild("__Destruction")
	if destructionFolder then
		table.insert(filterList, destructionFolder)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local result = Workspace:Raycast(origin, direction * range, raycastParams)

	-- Skip through destroyed breakable walls (invisible) and loose debris (flying rubble).
	-- Re-raycast from just past the hit point instead of filtering the instance,
	-- because filtering a destroyed wall would also exclude its visible children (BreakablePiece).
	while result do
		local hitInst = result.Instance
		local isDestroyedWall = hitInst:GetAttribute("__Breakable") == false
			or hitInst:GetAttribute("__BreakableClient") == false
		local isDebris = hitInst:HasTag("Debris")

		if isDestroyedWall or isDebris then
			local hitPos = result.Position
			local remaining = range - (hitPos - origin).Magnitude
			if remaining <= 0.1 then
				result = nil
				break
			end
			result = Workspace:Raycast(hitPos + direction * 0.1, direction * remaining, raycastParams)
		else
			break
		end
	end

	if result then
		if not TrainingRangeShot then
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local Locations =
				require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
			TrainingRangeShot = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("TrainingRangeShot"))
		end
		if TrainingRangeShot then
			TrainingRangeShot:TryHandleHit(result.Instance, result.Position)
		end

		-- Enforce hitbox-only hits for players (Collider/Hitbox/Standing|Crouching)
		local current = result.Instance.Parent
		local hitCharacter = nil
		if current and (current.Name == "Standing" or current.Name == "Crouching") then
			local hitboxFolder = current.Parent
			if hitboxFolder and hitboxFolder.Name == "Hitbox" then
				local colliderFolder = hitboxFolder.Parent
				if colliderFolder and colliderFolder.Name == "Collider" then
					local ownerUserId = colliderFolder:GetAttribute("OwnerUserId")
					if ownerUserId then
						local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
						if not ownerPlayer then
							for _, player in Players:GetPlayers() do
								if player.UserId == ownerUserId then
									ownerPlayer = player
									break
								end
							end
						end
						if ownerPlayer and ownerPlayer.Character then
							hitCharacter = ownerPlayer.Character
						end
					end
					if not hitCharacter then
						local characterModel = colliderFolder.Parent
						-- Use recursive search for nested Humanoids (e.g., dummies with Rig subfolder)
						if
							characterModel
							and characterModel:IsA("Model")
							and characterModel:FindFirstChildWhichIsA("Humanoid", true)
						then
							hitCharacter = characterModel
						end
					end
				end
			end
		end

		if not hitCharacter then
			hitCharacter = getCharacterFromPart(result.Instance)
			if hitCharacter then
				local hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
				if hitPlayer then
					-- Reject only when hit is on Rig/cosmetic copy (not the actual character).
					-- When Collider is missing, we need to accept hits on HumanoidRootPart/Head.
					if not result.Instance:IsDescendantOf(hitCharacter) then
						return {
							origin = origin,
							direction = direction,
							hitPart = nil,
							hitPosition = targetPosition,
							hitPlayer = nil,
							hitCharacter = nil,
							isHeadshot = false,
						}
					end
					-- Hit is on the actual character (e.g. HumanoidRootPart, Head) - accept it
				end
			end
		end

		-- Get player from character
		local hitPlayer = nil
		if hitCharacter then
			hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
			-- Fallback for test clients
			if not hitPlayer then
				for _, player in Players:GetPlayers() do
					if player.Character == hitCharacter then
						hitPlayer = player
						break
					end
				end
			end
		end

		-- Check for headshot (handles hitbox head parts)
		local isHeadshot = isHeadshotPart(result.Instance)

		-- Debug logging
		if DEBUG_LOGGING then
			local targetName = hitPlayer and hitPlayer.Name or (hitCharacter and hitCharacter.Name or "Unknown")
			print(string.format("[WeaponRaycast DEBUG] HIT DETECTED:"))
			print(string.format("  Target: %s | Part: %s", targetName, result.Instance.Name))
			print(
				string.format("  HitPos: (%.1f, %.1f, %.1f)", result.Position.X, result.Position.Y, result.Position.Z)
			)
			print(string.format("  Origin: (%.1f, %.1f, %.1f)", origin.X, origin.Y, origin.Z))
			print(string.format("  Headshot: %s | Timestamp: %.3f", tostring(isHeadshot), workspace:GetServerTimeNow()))
		end

		return {
			origin = origin,
			direction = direction,
			hitPart = result.Instance,
			hitPosition = result.Position,
			hitNormal = result.Normal,
			hitPlayer = hitPlayer,
			hitCharacter = hitCharacter,
			isHeadshot = isHeadshot,
			travelTime = weaponConfig.projectileSpeed
				and (result.Position - origin).Magnitude / weaponConfig.projectileSpeed,
		}
	end

	-- Debug logging for misses
	if DEBUG_LOGGING then
		print(
			string.format(
				"[WeaponRaycast DEBUG] MISS - No target hit at (%.1f, %.1f, %.1f)",
				targetPosition.X,
				targetPosition.Y,
				targetPosition.Z
			)
		)
	end

	return {
		origin = origin,
		direction = direction,
		hitPart = nil,
		hitPosition = targetPosition,
		hitNormal = direction.Unit * -1,
		hitPlayer = nil,
		hitCharacter = nil,
		isHeadshot = false,
	}
end

return WeaponRaycast
