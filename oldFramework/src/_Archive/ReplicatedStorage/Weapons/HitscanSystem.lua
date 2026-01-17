--!strict
-- HitscanSystem.lua
-- Handles raycast-based hit detection for hitscan weapons (guns without bullet drop)
-- Uses whitelist (Include) filtering to only detect Hitbox parts, ignoring character rigs/colliders

local HitscanSystem = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CollisionUtils = require(Locations.Modules.Utils.CollisionUtils)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)

-- Cache for performance (reusable RaycastParams)
local raycastParamsCache = {}

--[[
	Gets all player hitbox folders except the shooter's
	@param shooterCharacter - The character model of the shooter
	@return Array of hitbox folders to target
]]
function HitscanSystem:GetTargetHitboxes(shooterCharacter: Model): { Folder }
	local hitboxFolders = {}

	for _, player in pairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character ~= shooterCharacter then
			local hitboxFolder = character:FindFirstChild("Hitbox")
			if hitboxFolder then
				table.insert(hitboxFolders, hitboxFolder)
			end
		end
	end

	return hitboxFolders
end

--[[
	Gets all parts of the shooter's character to ignore in raycasts
	@param shooterCharacter - The character model of the shooter
	@return Array of instances to ignore (shooter's character descendants)
]]
function HitscanSystem:GetShooterIgnoreList(shooterCharacter: Model): { Instance }
	local ignoreList = {}

	-- Add all shooter's character descendants
	if shooterCharacter then
		for _, descendant in pairs(shooterCharacter:GetDescendants()) do
			table.insert(ignoreList, descendant)
		end
	end

	-- Ignore other players' Collider, Rig, and other non-hitbox parts
	for _, player in pairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character ~= shooterCharacter then
			-- Ignore Collider folder
			local collider = character:FindFirstChild("Collider")
			if collider then
				table.insert(ignoreList, collider)
			end

			-- Ignore Rig folder (now in workspace.Rigs)
			local rig = CharacterLocations:GetRig(character)
			if rig then
				table.insert(ignoreList, rig)
			end

			-- Ignore Root part
			local root = character:FindFirstChild("Root")
			if root then
				table.insert(ignoreList, root)
			end

			-- Ignore HumanoidRootPart (voice chat part)
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Parent == character then -- Only if it's direct child
				table.insert(ignoreList, hrp)
			end

			-- Ignore Head (voice chat part, direct child)
			local head = character:FindFirstChild("Head")
			if head and head.Parent == character then -- Only if it's direct child
				table.insert(ignoreList, head)
			end

			-- Ignore Humanoid (voice chat)
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid and humanoid.Parent == character then
				table.insert(ignoreList, humanoid)
			end
		end
	end

	return ignoreList
end

--[[
	Creates optimized RaycastParams for weapon hit detection
	Uses blacklist (Exclude) filtering to ignore shooter and non-hitbox parts
	This allows bullets to hit walls, terrain, and enemy hitboxes

	@param shooterCharacter - The character model of the shooter
	@param cacheKey - Optional cache key for reusing params (e.g., playerUserId)
	@return Configured RaycastParams
]]
function HitscanSystem:CreateWeaponRaycastParams(shooterCharacter: Model, cacheKey: string?): RaycastParams
	-- Check cache first for performance
	if cacheKey and raycastParamsCache[cacheKey] then
		local cachedParams = raycastParamsCache[cacheKey]
		-- Update filter in case players joined/left
		cachedParams.FilterDescendantsInstances = self:GetShooterIgnoreList(shooterCharacter)
		return cachedParams
	end

	-- Get ignore list (shooter's character + other players' non-hitbox parts)
	local ignoreList = self:GetShooterIgnoreList(shooterCharacter)

	-- Create params with blacklist (Exclude) filtering
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude -- Blacklist shooter and non-hitbox parts
	params.FilterDescendantsInstances = ignoreList
	params.IgnoreWater = true -- Bullets pass through water
	params.RespectCanCollide = false -- Hit parts even if CanCollide=false (for hitboxes)

	-- Cache for reuse
	if cacheKey then
		raycastParamsCache[cacheKey] = params
	end

	return params
end

--[[
	Performs a single raycast for hitscan weapon

	@param origin - Starting position of the raycast (gun barrel or camera)
	@param direction - Direction and distance vector (lookVector * maxRange)
	@param shooterCharacter - The character model of the shooter
	@param cacheKey - Optional cache key for RaycastParams reuse
	@return RaycastResult or nil if no hit
]]
function HitscanSystem:PerformRaycast(
	origin: Vector3,
	direction: Vector3,
	shooterCharacter: Model,
	cacheKey: string?
): RaycastResult?
	-- Create/get cached raycast params
	local params = self:CreateWeaponRaycastParams(shooterCharacter, cacheKey)

	-- Perform raycast
	local result = workspace:Raycast(origin, direction, params)

	return result
end

--[[
	Performs multiple raycasts with spread (for shotguns or spread weapons)

	@param origin - Starting position of the raycasts
	@param baseDirection - Base direction vector
	@param spreadAngle - Spread angle in degrees
	@param pelletCount - Number of pellets/rays to cast
	@param shooterCharacter - The character model of the shooter
	@param cacheKey - Optional cache key for RaycastParams reuse
	@return Array of tables containing {Result = RaycastResult?, Direction = Vector3}
]]
function HitscanSystem:PerformSpreadRaycast(
	origin: Vector3,
	baseDirection: Vector3,
	spreadAngle: number,
	pelletCount: number,
	shooterCharacter: Model,
	cacheKey: string?
): { { Result: RaycastResult?, Direction: Vector3 } }
	local results = {}
	local params = self:CreateWeaponRaycastParams(shooterCharacter, cacheKey)

	-- Get base direction length (max range)
	local maxRange = baseDirection.Magnitude
	local baseLookVector = baseDirection.Unit

	for i = 1, pelletCount do
		-- Calculate random spread offset in degrees, then convert to radians
		local randomX = math.rad(math.random() * spreadAngle * 2 - spreadAngle)
		local randomY = math.rad(math.random() * spreadAngle * 2 - spreadAngle)

		-- Apply spread rotation in camera-relative space
		-- Create a CFrame pointing in the base direction, then rotate it
		local baseCFrame = CFrame.lookAt(Vector3.zero, baseLookVector)
		local spreadCFrame = baseCFrame * CFrame.Angles(randomY, randomX, 0)
		local finalDirection = spreadCFrame.LookVector * maxRange

		-- Perform raycast for this pellet
		local result = workspace:Raycast(origin, finalDirection, params)
		table.insert(results, {
			Result = result,
			Direction = finalDirection
		})
	end

	return results
end

--[[
	Helper function to check if the hit part is a valid hitbox part
	@param hitPart - The part that was hit
	@return true if it's a hitbox part, false otherwise
]]
function HitscanSystem:IsHitboxPart(hitPart: BasePart): boolean
	-- Check if part is inside a Hitbox folder
	local parent = hitPart.Parent
	if not parent or parent.Name ~= "Hitbox" then
		return false
	end

	-- Check if Hitbox folder is inside a character
	local character = parent.Parent
	if not character then
		return false
	end

	-- Verify it's actually a player's character
	local player = Players:GetPlayerFromCharacter(character)
	return player ~= nil
end

--[[
	Helper function to determine if a hit was a headshot
	@param hitPart - The part that was hit
	@return true if headshot, false otherwise
]]
function HitscanSystem:IsHeadshot(hitPart: BasePart): boolean
	return hitPart.Name == "Head" and self:IsHitboxPart(hitPart)
end

--[[
	Helper function to get the player who owns the hit character
	@param hitPart - The part that was hit (should be in Hitbox folder)
	@return Player or nil if not found
]]
function HitscanSystem:GetPlayerFromHit(hitPart: BasePart): Player?
	-- Hitbox structure: Character/Hitbox/HitPart
	local hitboxFolder = hitPart.Parent
	if not hitboxFolder or hitboxFolder.Name ~= "Hitbox" then
		return nil
	end

	local character = hitboxFolder.Parent
	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

--[[
	Clears cached RaycastParams for a specific player
	Should be called when a player leaves
	@param cacheKey - The cache key to clear
]]
function HitscanSystem:ClearCache(cacheKey: string)
	raycastParamsCache[cacheKey] = nil
end

--[[
	Clears all cached RaycastParams
]]
function HitscanSystem:ClearAllCache()
	raycastParamsCache = {}
end

return HitscanSystem
