local WallDetectionUtils = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local TestMode = require(ReplicatedStorage.TestMode)

--[[
	WallDetectionUtils - Utility for detecting walls in the direction of movement

	This module provides wall detection functionality for future mechanics like wall jumping.
	It casts multiple rays in a cone pattern to detect walls ahead of the character.

	Usage:
		local wallData = WallDetectionUtils:DetectWall(character, primaryPart, direction, raycastParams, options)
		if wallData then
			print("Wall detected:", wallData.Distance, wallData.Normal, wallData.Part)
		end
]]

--[[
	Detects walls in a given direction using cone-based raycasting

	@param character - The character model to detect walls for
	@param primaryPart - The character's primary part (Root)
	@param direction - The direction to check for walls (should be normalized)
	@param raycastParams - RaycastParams to use for wall detection
	@param options - Optional table with detection parameters:
		{
			RayDistance: number,        -- How far ahead to check (default: from config)
			MinWallAngle: number,       -- Minimum degrees from vertical to be a wall (default: from config)
			MaxSlidingAngle: number,    -- Maximum angle toward wall to allow (default: from config)
			CheckAngleToWall: boolean,  -- Whether to check if moving toward wall (default: false)
			LogResults: boolean,        -- Whether to log detection results (default: TestMode setting)
		}

	@return wallData table if wall detected, nil otherwise:
		{
			Hit: boolean,              -- True if wall was detected
			Distance: number,          -- Distance to the wall
			Position: Vector3,         -- Position where raycast hit the wall
			Normal: Vector3,           -- Surface normal of the wall
			Part: BasePart,            -- The part that was hit
			AngleToWall: number,       -- Angle in degrees between direction and wall (if CheckAngleToWall = true)
		}
]]
function WallDetectionUtils:DetectWall(character, primaryPart, direction, raycastParams, options)
	if not character or not primaryPart or not raycastParams then
		return nil
	end

	-- Default options from config
	options = options or {}
	local rayDistance = options.RayDistance or Config.Gameplay.Sliding.WallDetection.RayDistance
	local minWallAngle = options.MinWallAngle or Config.Gameplay.Sliding.WallDetection.MinWallAngle
	local maxSlidingAngle = options.MaxSlidingAngle or Config.Gameplay.Sliding.WallDetection.MaxSlidingAngle
	local checkAngleToWall = options.CheckAngleToWall or false
	local logResults = options.LogResults
	if logResults == nil then
		logResults = TestMode.Logging.LogSlidingSystem
	end

	-- Get Body part center for raycasting
	local bodyPart = CharacterLocations:GetBody(character) or primaryPart
	local rayOrigin = bodyPart.Position

	-- Normalize direction
	local slideDirection = direction.Unit

	-- Cast multiple rays in a cone around the direction for better coverage
	local directions = {}

	-- Main direction (straight ahead)
	table.insert(directions, slideDirection)

	-- Add angled rays to left and right (±15° and ±30°) for wider detection
	local slideAngle = math.atan2(slideDirection.X, slideDirection.Z)
	for _, angleOffset in ipairs({ -30, -15, 15, 30 }) do
		local radianOffset = math.rad(angleOffset)
		local newAngle = slideAngle + radianOffset
		table.insert(directions, Vector3.new(math.sin(newAngle), 0, math.cos(newAngle)))
	end

	-- Check each direction for walls
	for _, dir in ipairs(directions) do
		local ray = workspace:Raycast(rayOrigin, dir * rayDistance, raycastParams)

		-- Check if we hit something that isn't part of our character and is collidable
		if ray and not ray.Instance:IsDescendantOf(character) and ray.Instance.CanCollide then
			-- Check if the surface is actually a wall (vertical/near-vertical surface)
			local surfaceNormal = ray.Normal
			local worldUp = Vector3.new(0, 1, 0)
			local angleFromVertical = math.acos(math.clamp(math.abs(surfaceNormal:Dot(worldUp)), 0, 1))
			local degreesFromVertical = math.deg(angleFromVertical)

			-- Only consider it a wall if the surface is within the configured degrees of vertical
			-- This excludes slopes, floors, and ceilings
			if degreesFromVertical >= minWallAngle then
				local wallData = {
					Hit = true,
					Distance = ray.Distance,
					Position = ray.Position,
					Normal = surfaceNormal,
					Part = ray.Instance,
				}

				-- Optionally check angle to wall if requested
				if checkAngleToWall then
					-- Wall normal points AWAY from wall, so negate it to get "into wall" direction
					local intoWallDirection = -surfaceNormal

					-- Calculate angle between slide direction and "into wall" direction
					local dotProduct = slideDirection:Dot(intoWallDirection)
					local angleTowardsWall = math.deg(math.acos(math.clamp(dotProduct, -1, 1)))

					wallData.AngleToWall = angleTowardsWall

					-- Check if angle is too head-on
					if angleTowardsWall <= maxSlidingAngle then
						if logResults then
							LogService:Info("WALL_DETECTION", "Wall detected - head-on collision", {
								Distance = ray.Distance,
								Direction = dir,
								HitPart = ray.Instance.Name,
								WallVerticalAngle = degreesFromVertical,
								AngleTowardsWall = angleTowardsWall,
								MaxAllowedAngle = maxSlidingAngle,
							})
						end
						return wallData
					elseif logResults then
						LogService:Debug("WALL_DETECTION", "Wall detected but angle OK", {
							Distance = ray.Distance,
							Direction = dir,
							HitPart = ray.Instance.Name,
							WallVerticalAngle = degreesFromVertical,
							AngleTowardsWall = angleTowardsWall,
							MaxAllowedAngle = maxSlidingAngle,
						})
					end
				else
					-- No angle check requested, return immediately
					if logResults then
						LogService:Info("WALL_DETECTION", "Wall detected", {
							Distance = ray.Distance,
							Direction = dir,
							HitPart = ray.Instance.Name,
							WallVerticalAngle = degreesFromVertical,
						})
					end
					return wallData
				end
			elseif logResults then
				LogService:Debug("WALL_DETECTION", "Surface ignored - not vertical enough", {
					Distance = ray.Distance,
					Direction = dir,
					HitPart = ray.Instance.Name,
					SurfaceAngle = degreesFromVertical,
				})
			end
		end
	end

	return nil
end

return WallDetectionUtils
