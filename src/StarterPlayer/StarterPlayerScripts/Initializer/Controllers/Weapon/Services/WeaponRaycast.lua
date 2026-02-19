local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local WeaponRaycast = {}
local TrainingRangeShot = nil

-- Pressure-based destruction system
local PressureDestruction = nil
pcall(function()
	PressureDestruction = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("PressureDestruction"))
end)

-- Debug flag (set to true to see hit logs)
-- TESTING: Enabled to debug match hit detection issues
local DEBUG_LOGGING = true

-- Debug raycast visualization (toggle with Y key) - only YOU see red lines showing shot path
WeaponRaycast.DebugRaycastEnabled = false
local _debugRayLines = {}
local DEBUG_RAY_DURATION = 5
local WALL_SKIP_STEP = 0.01

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

local function getPlayerFromCharacterFallback(character)
	if not character then
		return nil
	end
	local ownerPlayer = Players:GetPlayerFromCharacter(character)
	if ownerPlayer then
		return ownerPlayer
	end
	for _, player in Players:GetPlayers() do
		if player.Character == character then
			return player
		end
	end
	return nil
end

local function isNonBlockingDestroyedRemnant(part)
	if not part then
		return false
	end

	if part:HasTag("Debris") then
		return true
	end

	local destroyedFlag = part:GetAttribute("__Breakable") == false or part:GetAttribute("__BreakableClient") == false
	if not destroyedFlag then
		return false
	end

	-- Only skip if the part is effectively gone as a blocker.
	return part.Transparency >= 0.98 and (part.CanCollide == false or part.CanQuery == false)
end

--[[
	Debug raycast visualization - draws red line showing shot path.
	Uses Beam (client-only) so only the local player sees it.
	Lines persist in 3D world space for DEBUG_RAY_DURATION seconds.
]]
local _debugRayFolder = nil
local function getDebugRayFolder()
	if _debugRayFolder and _debugRayFolder.Parent then
		return _debugRayFolder
	end
	_debugRayFolder = Instance.new("Folder")
	_debugRayFolder.Name = "WeaponRaycastDebug"
	_debugRayFolder.Parent = Workspace.CurrentCamera
	return _debugRayFolder
end

local function addDebugRay(origin, hitPosition, camera)
	if not camera or not WeaponRaycast.DebugRaycastEnabled then
		return
	end
	local distance = (hitPosition - origin).Magnitude
	if distance < 0.01 then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame = CFrame.new(origin)
	part.Parent = getDebugRayFolder()

	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.zero
	att0.Parent = part

	local att1 = Instance.new("Attachment")
	att1.Position = part.CFrame:PointToObjectSpace(hitPosition)
	att1.Parent = part

	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Color = ColorSequence.new(Color3.new(1, 0.2, 0.2))
	beam.Width0 = 0.08
	beam.Width1 = 0.08
	beam.Parent = part

	local expireTime = os.clock() + DEBUG_RAY_DURATION
	table.insert(_debugRayLines, {
		part = part,
		expireTime = expireTime,
	})
end

local _debugRayUpdateConn = nil
local function ensureDebugRayUpdate()
	if _debugRayUpdateConn then
		return
	end
	_debugRayUpdateConn = RunService.Heartbeat:Connect(function()
		if #_debugRayLines == 0 then
			if _debugRayUpdateConn then
				_debugRayUpdateConn:Disconnect()
				_debugRayUpdateConn = nil
			end
			return
		end
		local now = os.clock()
		for i = #_debugRayLines, 1, -1 do
			local entry = _debugRayLines[i]
			if now >= entry.expireTime then
				if entry.part then
					entry.part:Destroy()
				end
				table.remove(_debugRayLines, i)
			end
		end
	end)
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

function WeaponRaycast.PerformRaycast(camera, localPlayer, weaponConfig, ignoreSpread, spreadMultiplier)
	if not camera then
		return nil
	end

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector.Unit
	local range = weaponConfig.range or 500
	local finalSpreadMultiplier = math.max(0, tonumber(spreadMultiplier) or 1)

	if not ignoreSpread and weaponConfig.spread and weaponConfig.spread > 0 then
		direction = WeaponRaycast.GetSpreadDirection(direction, weaponConfig.spread * finalSpreadMultiplier)
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
	-- Also exclude World.Map.Effects (match-loaded map effects like mob walls)
	local worldFolder = Workspace:FindFirstChild("World")
	local mapFolder = worldFolder and worldFolder:FindFirstChild("Map")
	if mapFolder then
		local mapEffects = mapFolder:FindFirstChild("Effects")
		if mapEffects then
			table.insert(filterList, mapEffects)
		end
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

	-- DEBUG: Log filter list contents
	warn("[RAYCAST] Filter list count:", #filterList)
	for i, inst in ipairs(filterList) do
		warn(string.format("[RAYCAST FILTER %d] %s", i, inst:GetFullName()))
	end
	-- END DEBUG

	local result = Workspace:Raycast(origin, direction * range, raycastParams)

	-- Skip through destroyed breakable walls (invisible) and loose debris (flying rubble).
	-- Re-raycast from just past the hit point instead of filtering the instance,
	-- because filtering a destroyed wall would also exclude its visible children (BreakablePiece).
	while result do
		local hitInst = result.Instance
		local isDestroyedRemnant = isNonBlockingDestroyedRemnant(hitInst)
		local isSelfHit = false
		local hitCharacterForSkip = getCharacterFromPart(hitInst)

		if hitCharacterForSkip and localPlayer then
			if character and hitCharacterForSkip == character then
				isSelfHit = true
			else
				local ownerPlayer = getPlayerFromCharacterFallback(hitCharacterForSkip)
				isSelfHit = ownerPlayer == localPlayer
			end
		end

		if isDestroyedRemnant or isSelfHit then
			local hitPos = result.Position
			local remaining = range - (hitPos - origin).Magnitude
			if remaining <= WALL_SKIP_STEP then
				result = nil
				break
			end
			result = Workspace:Raycast(hitPos + direction * WALL_SKIP_STEP, direction * remaining, raycastParams)
		else
			break
		end
	end

	if result then
		-- DEBUG: Log what the raycast hit
		local hitPath = result.Instance:GetFullName()
		local hitClass = result.Instance.ClassName
		local parentName = result.Instance.Parent and result.Instance.Parent.Name or "nil"
		local grandparentName = result.Instance.Parent and result.Instance.Parent.Parent and result.Instance.Parent.Parent.Name or "nil"
		warn(string.format("[RAYCAST HIT] Instance: %s | Class: %s | Parent: %s | Grandparent: %s", 
			hitPath, hitClass, parentName, grandparentName))
		
		-- Check if this looks like a Collider hitbox
		if parentName == "Standing" or parentName == "Crouching" then
			warn("[RAYCAST HIT] Detected hitbox structure! Looking for Collider...")
		elseif parentName == "Collider" or grandparentName == "Collider" then
			warn("[RAYCAST HIT] Hit something in Collider folder")
		end
		-- END DEBUG
		
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

		-- DEBUG: Log final hit resolution
		if hitPlayer then
			warn(string.format("[RAYCAST RESULT] HIT PLAYER: %s | Character: %s | Headshot: %s",
				hitPlayer.Name, hitCharacter and hitCharacter.Name or "nil", tostring(isHeadshot)))
		elseif hitCharacter then
			warn(string.format("[RAYCAST RESULT] HIT CHARACTER (no player): %s | Headshot: %s",
				hitCharacter.Name, tostring(isHeadshot)))
		else
			warn("[RAYCAST RESULT] NO PLAYER/CHARACTER - environment hit")
			
			-- Register environment hit for pressure destruction
			if PressureDestruction and result.Instance then
				-- Get destruction pressure from weapon config
				local destructionPressure = weaponConfig.destructionPressure or 20
				
				PressureDestruction:RegisterImpact(
					result.Position,
					result.Normal,
					result.Instance,
					destructionPressure,
					false, -- not a shotgun (hitscan weapons are single shot)
					nil,
					{
						origin = origin,
						range = range,
					}
				)
			end
		end
		-- END DEBUG

		if WeaponRaycast.DebugRaycastEnabled then
			ensureDebugRayUpdate()
			addDebugRay(origin, result.Position, Workspace.CurrentCamera)
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

	-- DEBUG: Log when ray missed everything
	warn("[RAYCAST MISS] Ray hit nothing - went full range to:", tostring(targetPosition))
	-- END DEBUG

	if WeaponRaycast.DebugRaycastEnabled then
		ensureDebugRayUpdate()
		addDebugRay(origin, targetPosition, Workspace.CurrentCamera)
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
