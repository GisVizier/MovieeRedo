local VaultingSystem = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

-- Clean, minimal constants
local VAULT_CONFIG = {
	-- Detection
	ForwardDistance = 4.5,         -- How far ahead to detect ledges
	MinHeight = 1.8,               -- Minimum vaultable height (lower obstacles)
	MaxHeight = 4.5,               -- Maximum vaultable height (shoulder+)
	MinSurfaceDepth = 1.0,         -- Minimum landing surface depth
	
	-- Physics
	FlightDuration = 0.4,          -- Fixed vault animation time
	MinForwardSpeed = 16,          -- Minimum horizontal speed during vault
	MomentumPreservation = 0.85,   -- How much speed to preserve (85%)
	MinLandingDistance = 2.5,      -- Minimum distance beyond obstacle to land
	
	-- Clearance
	LandingCheckSize = Vector3.new(2.5, 4.5, 2.5),
	LandingForwardOffset = 1.2,    -- Used for clearance check only
	LandingUpOffset = 0.5,
	
	-- Cooldowns
	VaultCooldown = 0.6,           -- Cooldown between vaults
	
	-- Debug
	EnableDebug = false,           -- Enable debug prints
}

VaultingSystem.LastVaultTime = 0

-- Helper: Get player's intended forward direction
local function getForwardDirection(characterController)
	if characterController.MovementInput.Magnitude > 0.1 then
		local forward = characterController:CalculateMovementDirection()
		return Vector3.new(forward.X, 0, forward.Z).Unit
	end
	
	-- Fallback to camera direction
	local yaw = characterController.CachedCameraYAngle or 0
	local cf = CFrame.Angles(0, yaw, 0)
	local look = cf.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

-- Helper: Check if surface is vertical enough to be a wall
local function isVerticalSurface(normal)
	return math.abs(normal:Dot(Vector3.new(0, 1, 0))) < 0.5
end

-- Helper: Check if surface is flat enough to land on
local function isFlatSurface(normal)
	return normal:Dot(Vector3.new(0, 1, 0)) > 0.7
end

-- Helper: Get obstacle depth in given direction
local function getObstacleDepth(part, direction)
	local localDir = part.CFrame:VectorToObjectSpace(direction.Unit)
	return math.abs(localDir.X) * part.Size.X
		+ math.abs(localDir.Y) * part.Size.Y
		+ math.abs(localDir.Z) * part.Size.Z
end

-- Helper: Check if landing zone is clear
local function isLandingClear(position, excludeParts, characterController)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeParts
	params.RespectCanCollide = true
	params.MaxParts = 20
	
	local parts = workspace:GetPartBoundsInBox(
		CFrame.new(position),
		VAULT_CONFIG.LandingCheckSize,
		params
	)
	
	for _, part in ipairs(parts) do
		if part and part:IsA("BasePart") and part.CanCollide then
			return false
		end
	end
	
	return true
end

-- Main detection function
function VaultingSystem:CanVault(characterController)
	local function debugFail(reason, data)
		if VAULT_CONFIG.EnableDebug then
			if data then
				print("[VAULT DEBUG]", reason, data)
			else
				print("[VAULT DEBUG]", reason)
			end
		end
		return false, nil
	end
	
	-- Preconditions
	if not characterController or not characterController.Character then
		return debugFail("No character controller or character")
	end
	
	if characterController.IsVaulting then
		return debugFail("Already vaulting")
	end
	
	-- Don't vault while sliding or crouching
	if MovementStateManager:IsSliding() then
		return debugFail("Currently sliding")
	end
	
	if MovementStateManager:IsCrouching() then
		return debugFail("Currently crouching")
	end
	
	-- Must be grounded
	if not characterController.IsGrounded then
		return debugFail("Not grounded")
	end
	
	-- Cooldown check
	local timeSinceLastVault = tick() - self.LastVaultTime
	if timeSinceLastVault < VAULT_CONFIG.VaultCooldown then
		return debugFail("Cooldown", string.format("%.2fs remaining", VAULT_CONFIG.VaultCooldown - timeSinceLastVault))
	end
	
	-- Get required components
	local primaryPart = characterController.PrimaryPart
	local raycastParams = characterController.RaycastParams
	if not primaryPart or not raycastParams then
		return debugFail("Missing primary part or raycast params")
	end
	
	-- Get forward direction
	local forward = getForwardDirection(characterController)
	if not forward or forward.Magnitude < 0.01 then
		return debugFail("No forward direction")
	end
	
	if VAULT_CONFIG.EnableDebug then
		print("[VAULT DEBUG] Attempting vault - forward:", forward)
	end
	
	-- Setup raycast params
	local params = RaycastParams.new()
	params.FilterType = raycastParams.FilterType
	params.FilterDescendantsInstances = raycastParams.FilterDescendantsInstances
	params.RespectCanCollide = true
	params.CollisionGroup = raycastParams.CollisionGroup or "Players"
	
	-- Step 1: Detect wall/obstacle ahead
	local feet = CharacterLocations:GetFeet(characterController.Character) or primaryPart
	local feetY = feet.Position.Y - (feet.Size.Y * 0.5)
	local rayOrigin = Vector3.new(primaryPart.Position.X, feetY + 1.5, primaryPart.Position.Z)
	
	local wallHit = workspace:Raycast(
		rayOrigin,
		forward * VAULT_CONFIG.ForwardDistance,
		params
	)
	
	if not wallHit then
		return debugFail("No wall detected ahead")
	end
	
	if not isVerticalSurface(wallHit.Normal) then
		return debugFail("Surface not vertical enough", string.format("Y-dot: %.2f", wallHit.Normal:Dot(Vector3.new(0, 1, 0))))
	end
	
	if VAULT_CONFIG.EnableDebug then
		print("[VAULT DEBUG] Wall found at distance:", wallHit.Distance)
	end
	
	-- Step 2: Find top surface
	local searchOrigin = wallHit.Position 
		+ forward * VAULT_CONFIG.LandingForwardOffset 
		+ Vector3.new(0, VAULT_CONFIG.MaxHeight, 0)
	
	local topHit = workspace:Raycast(
		searchOrigin,
		Vector3.new(0, -(VAULT_CONFIG.MaxHeight + 2), 0),
		params
	)
	
	if not topHit then
		return debugFail("No top surface found")
	end
	
	if not isFlatSurface(topHit.Normal) then
		return debugFail("Top surface not flat enough", string.format("Y-dot: %.2f", topHit.Normal:Dot(Vector3.new(0, 1, 0))))
	end
	
	-- Step 3: Validate height
	local ledgeHeight = topHit.Position.Y - feetY
	if ledgeHeight < VAULT_CONFIG.MinHeight then
		return debugFail("Ledge too low", string.format("%.2f < %.2f", ledgeHeight, VAULT_CONFIG.MinHeight))
	end
	
	if ledgeHeight > VAULT_CONFIG.MaxHeight then
		return debugFail("Ledge too high", string.format("%.2f > %.2f", ledgeHeight, VAULT_CONFIG.MaxHeight))
	end
	
	if VAULT_CONFIG.EnableDebug then
		print("[VAULT DEBUG] Ledge height:", ledgeHeight)
	end
	
	-- Step 4: Check surface depth
	local topPart = topHit.Instance
	local obstacleDepth = 0
	if topPart and topPart:IsA("BasePart") then
		local depth = getObstacleDepth(topPart, forward)
		if depth < VAULT_CONFIG.MinSurfaceDepth then
			return debugFail("Surface too thin", string.format("%.2f < %.2f", depth, VAULT_CONFIG.MinSurfaceDepth))
		end
		obstacleDepth = depth
		if VAULT_CONFIG.EnableDebug then
			print("[VAULT DEBUG] Surface depth:", depth)
		end
	end
	
	-- Step 5: Calculate proper landing position based on speed
	-- This ensures even from standstill, you land BEYOND the obstacle
	-- Landing should be: obstacle depth + minimum safe distance beyond
	local landingForwardDist = math.max(
		obstacleDepth + VAULT_CONFIG.MinLandingDistance,
		VAULT_CONFIG.MinForwardSpeed * VAULT_CONFIG.FlightDuration * 0.6
	)
	
	local landingPos = topHit.Position 
		+ forward * landingForwardDist
		+ Vector3.new(0, VAULT_CONFIG.LandingUpOffset, 0)
	
	-- Also check immediate landing spot (original offset for clearance)
	local immediateLandingPos = topHit.Position 
		+ forward * VAULT_CONFIG.LandingForwardOffset 
		+ Vector3.new(0, VAULT_CONFIG.LandingUpOffset, 0)
	
	local excludeList = table.clone(raycastParams.FilterDescendantsInstances or {})
	table.insert(excludeList, characterController.Character)
	if wallHit.Instance then table.insert(excludeList, wallHit.Instance) end
	if topHit.Instance then table.insert(excludeList, topHit.Instance) end
	
	-- Check both immediate landing and final landing are clear
	if not isLandingClear(immediateLandingPos, excludeList, characterController) then
		return debugFail("Immediate landing zone blocked")
	end
	
	if not isLandingClear(landingPos, excludeList, characterController) then
		return debugFail("Final landing zone blocked")
	end
	
	-- All checks passed!
	if VAULT_CONFIG.EnableDebug then
		print("[VAULT DEBUG] ✓ VAULT SUCCESS - Height:", ledgeHeight, "Distance:", wallHit.Distance, "Landing:", landingForwardDist)
	end
	
	return true, {
		forward = forward,
		landingPos = landingPos,
		ledgeHeight = ledgeHeight,
	}
end

-- Execute the vault
function VaultingSystem:ExecuteVault(characterController, data)
	if not characterController or not data then
		return false
	end
	
	local primaryPart = characterController.PrimaryPart
	if not primaryPart then
		return false
	end
	
	-- Calculate velocity with momentum preservation
	local currentVel = primaryPart.AssemblyLinearVelocity
	local currentHorizontal = Vector3.new(currentVel.X, 0, currentVel.Z)
	local currentSpeed = currentHorizontal.Magnitude
	
	-- Preserve momentum, but enforce minimum
	local targetSpeed = math.max(
		currentSpeed * VAULT_CONFIG.MomentumPreservation,
		VAULT_CONFIG.MinForwardSpeed
	)
	
	-- Calculate ballistic arc
	local startPos = primaryPart.Position
	local targetPos = data.landingPos
	local delta = targetPos - startPos
	local t = VAULT_CONFIG.FlightDuration
	
	local horizontalDir = data.forward * targetSpeed
	local verticalVel = (delta.Y + 0.5 * workspace.Gravity * t * t) / t
	
	local vaultVelocity = Vector3.new(horizontalDir.X, verticalVel, horizontalDir.Z)
	
	-- Apply velocity
	primaryPart.AssemblyLinearVelocity = vaultVelocity
	
	-- Trigger animation
	local animController = ServiceRegistry:GetController("AnimationController")
	if animController and animController.TriggerVaultAnimation then
		animController:TriggerVaultAnimation()
	end
	
	-- Set vault state
	characterController.IsVaulting = true
	characterController.VaultEndTime = tick() + t
	self.LastVaultTime = tick()
	
	return true
end

-- Attempt vault (combined check + execute)
function VaultingSystem:TryVault(characterController)
	local canVault, data = self:CanVault(characterController)
	if not canVault then
		return false
	end
	return self:ExecuteVault(characterController, data)
end

return VaultingSystem
