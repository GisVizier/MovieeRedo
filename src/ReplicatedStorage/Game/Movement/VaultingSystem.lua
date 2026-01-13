local VaultingSystem = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local SlidingSystem = require(Locations.Game:WaitForChild("Movement"):WaitForChild("SlidingSystem"))

-- Minimal, readable vaulting:
-- 1) Detect a wall/ledge in front.
-- 2) Find a top surface behind that ledge.
-- 3) Ensure space at the landing point.
-- 4) Apply a clean upward+forward throw.

local UP = Vector3.new(0, 1, 0)

-- Tuned as small constants (no new config surface area).
local FORWARD_RAY_DISTANCE = 3.0
local DOWN_RAY_DISTANCE = 6.0
local MIN_LEDGE_HEIGHT = 2.0
local MAX_LEDGE_HEIGHT = 5.25
local LAND_FORWARD_OFFSET = 1.35
local LAND_UP_OFFSET = 2.5
local CLEARANCE_BOX_SIZE = Vector3.new(3, 5, 3)

local VAULT_LOCK_TIME = 0.28
local VAULT_UP_VELOCITY = 55
local VAULT_FORWARD_MIN = 26

local function getForwardFlatFromCameraYaw(cameraYawRadians: number)
	local cf = CFrame.Angles(0, cameraYawRadians, 0)
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function isMostlyVerticalSurface(normal: Vector3)
	-- Wall-like: not pointing up.
	return math.abs(normal:Dot(UP)) < 0.35
end

local function hasBlockingPartsAt(cframe: CFrame, overlapParams: OverlapParams)
	local parts = workspace:GetPartBoundsInBox(cframe, CLEARANCE_BOX_SIZE, overlapParams)
	for _, p in ipairs(parts) do
		if p and p:IsA("BasePart") and p.CanCollide then
			return true
		end
	end
	return false
end

function VaultingSystem:TryVault(characterController)
	-- Preconditions
	if not characterController then
		return false
	end
	if characterController.IsVaulting then
		return false
	end
	if MovementStateManager:IsSliding() then
		return false
	end

	local character = characterController.Character
	local primaryPart = characterController.PrimaryPart
	local raycastParams = characterController.RaycastParams
	if not character or not primaryPart or not raycastParams then
		return false
	end

	-- Vaults are grounded actions (prevents mid-air wall sticking issues).
	if not characterController.IsGrounded then
		return false
	end

	local forward = getForwardFlatFromCameraYaw(characterController.CachedCameraYAngle or 0)

	local body = CharacterLocations:GetBody(character) or primaryPart
	local origin = body.Position + Vector3.new(0, 1.2, 0)

	-- 1) Ledge face check
	local wallHit = workspace:Raycast(origin, forward * FORWARD_RAY_DISTANCE, raycastParams)
	if not wallHit or not wallHit.Normal or not isMostlyVerticalSurface(wallHit.Normal) then
		return false
	end

	-- 2) Find top surface behind the ledge by raycasting down from above/over it.
	local feet = CharacterLocations:GetFeet(character) or primaryPart
	local baseY = (feet.Position.Y - (feet.Size.Y * 0.5))

	local topProbeOrigin = wallHit.Position
		+ forward * LAND_FORWARD_OFFSET
		+ Vector3.new(0, MAX_LEDGE_HEIGHT + 1.0, 0)

	local topHit = workspace:Raycast(topProbeOrigin, Vector3.new(0, -DOWN_RAY_DISTANCE, 0), raycastParams)
	if not topHit or not topHit.Normal then
		return false
	end

	-- Require a reasonably walkable top surface.
	if topHit.Normal:Dot(UP) < 0.6 then
		return false
	end

	local ledgeHeight = topHit.Position.Y - baseY
	if ledgeHeight < MIN_LEDGE_HEIGHT or ledgeHeight > MAX_LEDGE_HEIGHT then
		return false
	end

	-- 3) Clearance check at landing point
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = raycastParams.FilterDescendantsInstances
	overlapParams.RespectCanCollide = true
	overlapParams.MaxParts = 20

	local landingPos = topHit.Position + forward * LAND_FORWARD_OFFSET + Vector3.new(0, LAND_UP_OFFSET, 0)
	local landingCF = CFrame.new(landingPos)

	if hasBlockingPartsAt(landingCF, overlapParams) then
		return false
	end

	-- Cancel slide buffers if any (vault should be intentional).
	if SlidingSystem.IsSlideBuffered then
		SlidingSystem:CancelSlideBuffer("Vault started")
	end

	-- 4) Apply throw
	local currentVel = primaryPart.AssemblyLinearVelocity
	local currentHoriz = Vector3.new(currentVel.X, 0, currentVel.Z)
	local forwardSpeed = math.max(VAULT_FORWARD_MIN, currentHoriz.Magnitude)

	primaryPart.AssemblyLinearVelocity = forward * forwardSpeed + Vector3.new(0, VAULT_UP_VELOCITY, 0)

	characterController.IsVaulting = true
	characterController.VaultEndTime = tick() + VAULT_LOCK_TIME

	return true
end

return VaultingSystem

