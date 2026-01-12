local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))

local WallDetectionUtils = {}

function WallDetectionUtils:DetectWall(character, primaryPart, direction, raycastParams, options)
	if not character or not primaryPart or not raycastParams then
		return nil
	end

	options = options or {}
	local rayDistance = options.RayDistance or Config.Gameplay.Sliding.WallDetection.RayDistance
	local minWallAngle = options.MinWallAngle or Config.Gameplay.Sliding.WallDetection.MinWallAngle
	local maxSlidingAngle = options.MaxSlidingAngle or Config.Gameplay.Sliding.WallDetection.MaxSlidingAngle
	local checkAngleToWall = options.CheckAngleToWall or false
	local logResults = options.LogResults
	if logResults == nil then
		logResults = TestMode.Logging.LogSlidingSystem
	end

	local bodyPart = CharacterLocations:GetBody(character) or primaryPart
	local rayOrigin = bodyPart.Position
	local slideDirection = direction.Unit
	local directions = {}

	table.insert(directions, slideDirection)

	local slideAngle = math.atan2(slideDirection.X, slideDirection.Z)
	for _, angleOffset in ipairs({ -30, -15, 15, 30 }) do
		local radianOffset = math.rad(angleOffset)
		local newAngle = slideAngle + radianOffset
		table.insert(directions, Vector3.new(math.sin(newAngle), 0, math.cos(newAngle)))
	end

	for _, dir in ipairs(directions) do
		local ray = workspace:Raycast(rayOrigin, dir * rayDistance, raycastParams)

		if ray and not ray.Instance:IsDescendantOf(character) and ray.Instance.CanCollide then
			local surfaceNormal = ray.Normal
			local worldUp = Vector3.new(0, 1, 0)
			local angleFromVertical = math.acos(math.clamp(math.abs(surfaceNormal:Dot(worldUp)), 0, 1))
			local degreesFromVertical = math.deg(angleFromVertical)

			if degreesFromVertical >= minWallAngle then
				local wallData = {
					Hit = true,
					Distance = ray.Distance,
					Position = ray.Position,
					Normal = surfaceNormal,
					Part = ray.Instance,
				}

				if checkAngleToWall then
					local intoWallDirection = -surfaceNormal
					local dotProduct = slideDirection:Dot(intoWallDirection)
					local angleTowardsWall = math.deg(math.acos(math.clamp(dotProduct, -1, 1)))
					wallData.AngleToWall = angleTowardsWall

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
