local WallJumpUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local Net = require(Locations.Shared.Net.Net)

local function toVec3(value)
	if typeof(value) == "Vector3" then
		return { x = value.X, y = value.Y, z = value.Z }
	end
	return value
end

local function sendDebug(hypothesisId, location, message, data)
	if false then
		return
	end
	local payload = {
		sessionId = "debug-session",
		runId = "walljump_debug",
		hypothesisId = hypothesisId,
		location = location,
		message = message,
		data = data,
		timestamp = DateTime.now().UnixTimestampMillis,
	}
	Net:FireServer("DebugLog", payload)
end

WallJumpUtils.RemainingCharges = 3
WallJumpUtils.HasResetThisLanding = true
WallJumpUtils.LastWallJumpTime = 0
WallJumpUtils.LastLandingTime = 0

function WallJumpUtils:AttemptWallJump(character, primaryPart, raycastParams, cameraAngles, characterController)
	-- #region agent log
	sendDebug("H1", "WallJumpUtils.lua:AttemptWallJump", "enter", {
		hasCharacter = character ~= nil,
		hasPrimaryPart = primaryPart ~= nil,
		hasRaycastParams = raycastParams ~= nil,
		isSliding = MovementStateManager:IsSliding(),
		remainingCharges = self.RemainingCharges,
		lastWallJumpTime = self.LastWallJumpTime,
		lastLandingTime = self.LastLandingTime,
	})
	-- #endregion
	if not Config.Gameplay.Character.WallJump.Enabled then
		-- #region agent log
		sendDebug("H1", "WallJumpUtils.lua:AttemptWallJump", "disabled", {})
		-- #endregion
		return false, nil
	end

	if not character or not primaryPart or not raycastParams then
		-- #region agent log
		sendDebug("H1", "WallJumpUtils.lua:AttemptWallJump", "invalid_inputs", {
			hasCharacter = character ~= nil,
			hasPrimaryPart = primaryPart ~= nil,
			hasRaycastParams = raycastParams ~= nil,
		})
		-- #endregion
		if TestMode.Logging.LogSlidingSystem then
			LogService:Warn("WALL_JUMP", "Invalid inputs for wall jump", {
				HasCharacter = character ~= nil,
				HasPrimaryPart = primaryPart ~= nil,
				HasRaycastParams = raycastParams ~= nil,
			})
		end
		return false, nil
	end

	local currentTime = tick()
	local cooldown = Config.Gameplay.Character.WallJump.CooldownBetweenJumps or 0.15
	local timeSinceLastJump = currentTime - self.LastWallJumpTime

	if timeSinceLastJump < cooldown then
		-- #region agent log
		sendDebug("H2", "WallJumpUtils.lua:AttemptWallJump", "cooldown", {
			timeSinceLastJump = timeSinceLastJump,
			cooldown = cooldown,
		})
		-- #endregion
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "Wall jump on cooldown", {
				TimeSinceLastJump = timeSinceLastJump,
				Cooldown = cooldown,
			})
		end
		return false, nil
	end

	local landingGracePeriod = 0.15
	local timeSinceLanding = currentTime - self.LastLandingTime
	if timeSinceLanding < landingGracePeriod then
		-- #region agent log
		sendDebug("H2", "WallJumpUtils.lua:AttemptWallJump", "landing_grace_block", {
			timeSinceLanding = timeSinceLanding,
			landingGracePeriod = landingGracePeriod,
		})
		-- #endregion
		return false, nil
	end

	if self.RemainingCharges <= 0 then
		-- #region agent log
		sendDebug("H2", "WallJumpUtils.lua:AttemptWallJump", "no_charges", {
			remainingCharges = self.RemainingCharges,
		})
		-- #endregion
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "No wall jump charges remaining", {
				RemainingCharges = self.RemainingCharges,
			})
		end
		return false, nil
	end

	local isGrounded = self:IsCharacterGrounded(character, primaryPart, raycastParams)
	if Config.Gameplay.Character.WallJump.RequireAirborne and isGrounded then
		-- #region agent log
		sendDebug("H3", "WallJumpUtils.lua:AttemptWallJump", "blocked_grounded", {
			isGrounded = isGrounded,
		})
		-- #endregion
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "Wall jump requires airborne state", {
				IsGrounded = isGrounded,
			})
		end
		return false, nil
	end

	if Config.Gameplay.Character.WallJump.RequireSprinting then
		local isSprinting = characterController and characterController.IsSprinting or false
		if not isSprinting then
			-- #region agent log
			sendDebug("H3", "WallJumpUtils.lua:AttemptWallJump", "blocked_sprinting", {
				isSprinting = isSprinting,
			})
			-- #endregion
			if TestMode.Logging.LogSlidingSystem then
				LogService:Debug("WALL_JUMP", "Wall jump requires sprinting", {
					IsSprinting = isSprinting,
				})
			end
			return false, nil
		end
	end

	local isSliding = MovementStateManager:IsSliding()
	if Config.Gameplay.Character.WallJump.ExcludeDuringSlide and isSliding then
		-- #region agent log
		sendDebug("H3", "WallJumpUtils.lua:AttemptWallJump", "blocked_sliding", {
			currentState = MovementStateManager:GetCurrentState(),
		})
		-- #endregion
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "Wall jump disabled during slide", {
				CurrentState = MovementStateManager:GetCurrentState(),
			})
		end
		return false, nil
	end

	local wallDetected, wallData = self:DetectWallRadial(character, primaryPart, raycastParams)
	-- #region agent log
	sendDebug("H4", "WallJumpUtils.lua:AttemptWallJump", "detect_result", {
		wallDetected = wallDetected,
		wallPart = wallData and wallData.Part and wallData.Part.Name or "nil",
		wallNormal = wallData and toVec3(wallData.Normal) or nil,
		wallDistance = wallData and wallData.Distance or nil,
	})
	-- #endregion
	if not wallDetected then
		-- #region agent log
		sendDebug("H4", "WallJumpUtils.lua:AttemptWallJump", "no_wall", {})
		-- #endregion
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "No wall detected for wall jump", {
				CameraAngles = cameraAngles,
			})
		end
		return false, nil
	end

	self:ExecuteWallJump(primaryPart, wallData, cameraAngles, characterController)
	-- #region agent log
	sendDebug("H4", "WallJumpUtils.lua:AttemptWallJump", "executed", {
		wallPart = wallData and wallData.Part and wallData.Part.Name or "nil",
		wallNormal = wallData and wallData.Normal or nil,
	})
	-- #endregion

	return true, wallData
end

function WallJumpUtils:ExecuteWallJump(primaryPart, wallData, cameraAngles, characterController)
	local config = Config.Gameplay.Character.WallJump

	local yaw = math.rad(cameraAngles.X)
	local cameraDirection = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	-- #region agent log
	sendDebug("H5", "WallJumpUtils.lua:ExecuteWallJump", "start", {
		cameraAngles = cameraAngles,
		cameraDirection = toVec3(cameraDirection),
	})
	-- #endregion

	local wallNormal = wallData.Normal
	local wallNormalHorizontal = Vector3.new(wallNormal.X, 0, wallNormal.Z)
	if wallNormalHorizontal.Magnitude > 0.01 then
		wallNormalHorizontal = wallNormalHorizontal.Unit
	else
		wallNormalHorizontal = cameraDirection
	end

	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local incomingHorizontal = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local angleMultiplier = config.AnglePushMultiplier or 1.5
	-- #region agent log
	sendDebug("H5", "WallJumpUtils.lua:ExecuteWallJump", "velocity_context", {
		currentVelocity = toVec3(currentVelocity),
		incomingHorizontal = toVec3(incomingHorizontal),
		wallNormal = toVec3(wallNormal),
		wallNormalHorizontal = toVec3(wallNormalHorizontal),
		angleMultiplier = angleMultiplier,
	})
	-- #endregion

	-- 4-direction wall boost selection:
	-- Use player intent (movement input / facing) + wall normal to pick Forward/Back/Left/Right.
	local intentDir = nil
	local intentSource = "input"
	if characterController and characterController.MovementInput and characterController.MovementInput.Magnitude > 0.1 then
		intentDir = characterController:CalculateMovementDirection()
		intentSource = "input"
	end
	if not intentDir or intentDir.Magnitude < 0.1 then
		-- Prefer incoming velocity (feels consistent at speed), then fallback to camera.
		if incomingHorizontal.Magnitude > 0.1 then
			intentDir = incomingHorizontal
			intentSource = "velocity"
		else
			intentDir = cameraDirection
			intentSource = "camera"
		end
	end
	intentDir = Vector3.new(intentDir.X, 0, intentDir.Z)
	if intentDir.Magnitude < 0.01 then
		intentDir = -wallNormalHorizontal
		intentSource = "fallback"
	end
	intentDir = intentDir.Unit
	-- #region agent log
	sendDebug("H5", "WallJumpUtils.lua:ExecuteWallJump", "intent_basis", {
		intentSource = intentSource,
		intentDir = toVec3(intentDir),
		incomingHorizontal = toVec3(incomingHorizontal),
		cameraDirection = toVec3(cameraDirection),
		wallNormalHorizontal = toVec3(wallNormalHorizontal),
	})
	-- #endregion

	-- Determine relative direction to wall.
	local intoWall = intentDir:Dot(-wallNormalHorizontal) -- + = pushing into wall
	local boostType = "lateral"
	if intoWall > 0.55 then
		boostType = "forward"
	elseif intoWall < -0.55 then
		boostType = "backward"
	end
	-- #region agent log
	sendDebug("H5", "WallJumpUtils.lua:ExecuteWallJump", "boost_choice", {
		boostType = boostType,
		intoWall = intoWall,
		angleMultiplier = angleMultiplier,
	})
	-- #endregion

	local pushDirection = wallNormalHorizontal
	local horizontalBoost = config.HorizontalBoost
	if boostType == "forward" then
		-- Reflect (bounce) based on approach angle; more reliable than just wall normal.
		if incomingHorizontal.Magnitude > 1 then
			local incomingDir = incomingHorizontal.Unit
			local dotProduct = incomingDir:Dot(wallNormalHorizontal)
			local reflection = incomingDir - 2 * dotProduct * wallNormalHorizontal
			pushDirection = reflection.Unit
		else
			pushDirection = wallNormalHorizontal
		end
		horizontalBoost = horizontalBoost * 1.15
	elseif boostType == "backward" then
		-- Pulling away from wall: bias toward your intent direction with a lift.
		pushDirection = intentDir
		horizontalBoost = horizontalBoost * 0.85
	else
		-- Left/right: blend reflection + wall normal, then bias by side sign.
		if incomingHorizontal.Magnitude > 1 then
			local incomingDir = incomingHorizontal.Unit
			local dotProduct = incomingDir:Dot(wallNormalHorizontal)
			local reflection = incomingDir - 2 * dotProduct * wallNormalHorizontal
			local blendedDirection = (reflection * angleMultiplier + wallNormalHorizontal)
			if blendedDirection.Magnitude > 0.01 then
				pushDirection = blendedDirection.Unit
			end
		end
	end

	local wallPushVelocity = pushDirection * config.WallPushForce
	local cameraPushVelocity = cameraDirection * horizontalBoost

	local horizontalVelocity = wallPushVelocity + cameraPushVelocity
	local verticalVelocity = config.VerticalBoost
	-- #region agent log
	sendDebug("H5", "WallJumpUtils.lua:ExecuteWallJump", "velocity_components", {
		pushDirection = toVec3(pushDirection),
		wallPushVelocity = toVec3(wallPushVelocity),
		cameraPushVelocity = toVec3(cameraPushVelocity),
		horizontalVelocity = toVec3(horizontalVelocity),
		verticalVelocity = verticalVelocity,
	})
	-- #endregion

	local newVelocity = Vector3.new(
		horizontalVelocity.X,
		verticalVelocity,
		horizontalVelocity.Z
	)

	primaryPart.AssemblyLinearVelocity = newVelocity
	-- #region agent log
	sendDebug("H5", "WallJumpUtils.lua:ExecuteWallJump", "velocity_applied", {
		newVelocity = toVec3(newVelocity),
		currentVelocity = toVec3(currentVelocity),
		wallNormal = toVec3(wallNormal),
		pushDirection = toVec3(pushDirection),
		boostType = boostType,
	})
	-- #endregion

	self.RemainingCharges = self.RemainingCharges - 1
	self.HasResetThisLanding = false
	self.LastWallJumpTime = tick()
	-- #region agent log
	sendDebug("H5", "WallJumpUtils.lua:ExecuteWallJump", "charges_update", {
		remainingCharges = self.RemainingCharges,
		hasResetThisLanding = self.HasResetThisLanding,
		lastWallJumpTime = self.LastWallJumpTime,
	})
	-- #endregion

	local wallPos = wallData.Position
	local wallNormal = wallData.Normal
	local pivot = CFrame.lookAt(wallPos, wallPos + wallNormal)
	VFXRep:Fire("All", { Module = "WallJump" }, {
		position = wallPos,
		pivot = pivot,
	})
	-- #region agent log
	sendDebug("H5", "WallJumpUtils.lua:ExecuteWallJump", "vfx_fired", {
		position = toVec3(wallPos),
		normal = toVec3(wallNormal),
	})
	-- #endregion

	local animationController = ServiceRegistry:GetController("AnimationController")

	if self.RemainingCharges <= 0 and animationController then
		task.delay(0.3, function()
			if self.RemainingCharges <= 0 and animationController.PlayFallingAnimation then
				animationController:PlayFallingAnimation()
				-- #region agent log
				sendDebug("H5", "WallJumpUtils.lua:ExecuteWallJump", "falling_forced", {
					remainingCharges = self.RemainingCharges,
				})
				-- #endregion
			end
		end)
	end

	if animationController and animationController.TriggerWallBoostAnimation then
		-- Drive animation name from selected boostType.
		local animationName = "WallBoostForward"
		if boostType == "backward" then
			animationName = "WallBoostBack"
		elseif boostType == "lateral" then
			-- Use wall side relative to intent.
			local side = intentDir:Cross(wallNormalHorizontal).Y
			animationName = (side > 0) and "WallBoostRight" or "WallBoostLeft"
		end

		animationController:PlayAirborneAnimation(animationName)
		-- #region agent log
		sendDebug("H5", "WallJumpUtils.lua:ExecuteWallJump", "animation_play", {
			animationName = animationName,
			boostType = boostType,
		})
		-- #endregion
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("WALL_JUMP", "Wall jump executed", {
			WallNormal = wallData.Normal,
			WallPart = wallData.Part.Name,
			WallPushVelocity = wallPushVelocity,
			CameraPushVelocity = cameraPushVelocity,
			HorizontalVelocity = horizontalVelocity,
			VerticalVelocity = verticalVelocity,
			NewVelocity = newVelocity,
			RemainingCharges = self.RemainingCharges,
		})
	end
end

function WallJumpUtils:DetectWallRadial(character, primaryPart, raycastParams)
	local bodyPart = CharacterLocations:GetBody(character)
	if not bodyPart then
		-- #region agent log
		sendDebug("H4", "WallJumpUtils.lua:DetectWallRadial", "missing_body", {})
		-- #endregion
		return false, nil
	end

	local bodyPosition = bodyPart.Position
	local bodySize = bodyPart.Size
	local rayOrigin = bodyPosition - Vector3.new(0, bodySize.Y / 2, 0)

	local detectionRadius = Config.Gameplay.Character.WallJump.WallDetectionDistance
	local numDirections = 16
	local minWallAngle = Config.Gameplay.Character.WallJump.MinWallAngle

	local directions = {}
	for i = 1, numDirections do
		local angle = (i - 1) * (360 / numDirections)
		local radians = math.rad(angle)
		table.insert(directions, Vector3.new(math.sin(radians), 0, math.cos(radians)))
	end

	-- #region agent log
	sendDebug("H4", "WallJumpUtils.lua:DetectWallRadial", "radial_begin", {
		rayOrigin = toVec3(rayOrigin),
		detectionRadius = detectionRadius,
		minWallAngle = minWallAngle,
		numDirections = numDirections,
	})
	-- #endregion

	for _, direction in ipairs(directions) do
		local ray = workspace:Raycast(rayOrigin, direction * detectionRadius, raycastParams)

		if ray and not ray.Instance:IsDescendantOf(character) and ray.Instance.CanCollide then
			local surfaceNormal = ray.Normal
			local worldUp = Vector3.new(0, 1, 0)
			local angleFromVertical = math.acos(math.clamp(math.abs(surfaceNormal:Dot(worldUp)), 0, 1))
			local degreesFromVertical = math.deg(angleFromVertical)

			-- #region agent log
			sendDebug("H4", "WallJumpUtils.lua:DetectWallRadial", "ray_hit", {
				hitPart = ray.Instance.Name,
				distance = ray.Distance,
				normal = toVec3(ray.Normal),
				degreesFromVertical = degreesFromVertical,
			})
			-- #endregion

			if degreesFromVertical >= minWallAngle then
				local wallData = {
					Hit = true,
					Distance = ray.Distance,
					Position = ray.Position,
					Normal = surfaceNormal,
					Part = ray.Instance,
				}

				if TestMode.Logging.LogSlidingSystem then
					LogService:Info("WALL_JUMP", "Wall detected via radial raycast", {
						Distance = ray.Distance,
						Direction = direction,
						HitPart = ray.Instance.Name,
						VerticalAngle = degreesFromVertical,
					})
				end
				-- #region agent log
				sendDebug("H4", "WallJumpUtils.lua:DetectWallRadial", "wall_hit", {
					hitPart = ray.Instance.Name,
					distance = ray.Distance,
					normal = toVec3(ray.Normal),
					degreesFromVertical = degreesFromVertical,
				})
				-- #endregion
				-- #region agent log
				sendDebug("H4", "WallJumpUtils.lua:DetectWallRadial", "radial_accept", {
					degreesFromVertical = degreesFromVertical,
					minWallAngle = minWallAngle,
				})
				-- #endregion

				return true, wallData
			end
		end
	end

	-- #region agent log
	sendDebug("H4", "WallJumpUtils.lua:DetectWallRadial", "radial_none", {})
	-- #endregion
	return false, nil
end

function WallJumpUtils:IsCharacterGrounded(character, primaryPart, raycastParams)
	local feetPart = CharacterLocations:GetFeet(character)
	if not feetPart then
		return false
	end

	local rayOrigin = feetPart.Position - Vector3.new(0, feetPart.Size.Y / 2, 0)
	local rayDirection = Vector3.new(0, -1, 0)
	local rayDistance = Config.Gameplay.Character.GroundRayDistance + Config.Gameplay.Character.GroundRayOffset

	local ray = workspace:Raycast(rayOrigin, rayDirection * rayDistance, raycastParams)
	-- #region agent log
	sendDebug("H3", "WallJumpUtils.lua:IsCharacterGrounded", "ground_check", {
		hit = ray ~= nil,
		rayDistance = rayDistance,
		hitPart = ray and ray.Instance and ray.Instance.Name or "nil",
	})
	-- #endregion

	return ray ~= nil
end

function WallJumpUtils:ResetCharges()
	if self.HasResetThisLanding then
		return
	end

	local config = Config.Gameplay.Character.WallJump
	self.RemainingCharges = config.MaxCharges
	self.HasResetThisLanding = true
	self.LastLandingTime = tick()
	-- #region agent log
	sendDebug("H2", "WallJumpUtils.lua:ResetCharges", "reset", {
		remainingCharges = self.RemainingCharges,
		lastLandingTime = self.LastLandingTime,
	})
	-- #endregion
end

return WallJumpUtils
