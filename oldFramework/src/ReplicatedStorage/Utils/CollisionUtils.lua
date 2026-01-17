--!strict
-- CollisionUtils.lua
-- Utility functions for creating raycast and overlap parameters
-- Reduces code duplication across CrouchUtils, HitController, MovementUtils, etc.

local CollisionUtils = {}

--[[
	Creates OverlapParams with exclusion filter (most common pattern)
	@param excludedInstances - Array of instances to exclude
	@param options - Optional table with:
		- MaxParts: number (default 20)
		- RespectCanCollide: boolean (default true)
		- CollisionGroup: string (optional)
	@return Configured OverlapParams
]]
function CollisionUtils:CreateExclusionOverlapParams(
	excludedInstances: { Instance },
	options: {
		MaxParts: number?,
		RespectCanCollide: boolean?,
		CollisionGroup: string?,
	}?
): OverlapParams
	options = options or {}

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludedInstances
	params.RespectCanCollide = if options.RespectCanCollide ~= nil then options.RespectCanCollide else true
	params.MaxParts = options.MaxParts or 20

	if options.CollisionGroup then
		params.CollisionGroup = options.CollisionGroup
	end

	return params
end

--[[
	Creates OverlapParams with inclusion filter
	@param includedInstances - Array of instances to include
	@param options - Optional configuration
	@return Configured OverlapParams
]]
function CollisionUtils:CreateInclusionOverlapParams(
	includedInstances: { Instance },
	options: {
		MaxParts: number?,
		RespectCanCollide: boolean?,
	}?
): OverlapParams
	options = options or {}

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = includedInstances
	params.RespectCanCollide = if options.RespectCanCollide ~= nil then options.RespectCanCollide else true
	params.MaxParts = options.MaxParts or 20

	return params
end

--[[
	Creates RaycastParams with exclusion filter (most common pattern for character raycasts)
	@param excludedInstances - Array of instances to exclude
	@param options - Optional table with:
		- RespectCanCollide: boolean (default true)
		- CollisionGroup: string (optional)
		- IgnoreWater: boolean (default false)
	@return Configured RaycastParams
]]
function CollisionUtils:CreateExclusionRaycastParams(
	excludedInstances: { Instance },
	options: {
		RespectCanCollide: boolean?,
		CollisionGroup: string?,
		IgnoreWater: boolean?,
	}?
): RaycastParams
	options = options or {}

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludedInstances
	params.RespectCanCollide = if options.RespectCanCollide ~= nil then options.RespectCanCollide else true
	params.IgnoreWater = if options.IgnoreWater ~= nil then options.IgnoreWater else false

	if options.CollisionGroup then
		params.CollisionGroup = options.CollisionGroup
	end

	return params
end

--[[
	Creates RaycastParams specifically for character ground detection
	This is the common pattern used across the movement system
	@param character - The character model to exclude
	@return Configured RaycastParams with "Players" collision group
]]
function CollisionUtils:CreateCharacterRaycastParams(character: Model): RaycastParams
	return self:CreateExclusionRaycastParams({ character }, {
		RespectCanCollide = true,
		CollisionGroup = "Players",
	})
end

--[[
	Creates RaycastParams with inclusion filter
	@param includedInstances - Array of instances to include
	@param options - Optional configuration
	@return Configured RaycastParams
]]
function CollisionUtils:CreateInclusionRaycastParams(
	includedInstances: { Instance },
	options: {
		RespectCanCollide: boolean?,
		CollisionGroup: string?,
	}?
): RaycastParams
	options = options or {}

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = includedInstances
	params.RespectCanCollide = if options.RespectCanCollide ~= nil then options.RespectCanCollide else true

	if options.CollisionGroup then
		params.CollisionGroup = options.CollisionGroup
	end

	return params
end

--[[
	Creates RaycastParams specifically for weapon hit detection
	Uses whitelist (Include) filtering to only hit Hitbox parts
	@param targetHitboxFolders - Array of Hitbox folders to target
	@return Configured RaycastParams optimized for weapon raycasts
]]
function CollisionUtils:CreateWeaponRaycastParams(targetHitboxFolders: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include -- Whitelist only hitboxes
	params.FilterDescendantsInstances = targetHitboxFolders
	params.IgnoreWater = true -- Bullets pass through water
	params.RespectCanCollide = false -- CRITICAL: Hitbox parts have CanCollide=false
	params.CollisionGroup = "Hitboxes" -- Use Hitboxes collision group for performance

	return params
end

return CollisionUtils
