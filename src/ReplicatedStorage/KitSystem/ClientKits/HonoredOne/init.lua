--[[
	HonoredOne Client Kit (Gojo)
	
	Ability: DUALITY - Blue (not crouching) / Red (crouching)
	
	Blue: Moving vacuum hitbox that pulls targets toward center,
	      then explodes outward at the end. No damage.
	
	Red: Piercing projectile that:
	     - Charges while held (freeze event)
	     - Fires on release (shoot event)
	     - Pierces through players, knocking them away + damage
	     - Explodes on world collision
	     - Headshot = bonus crit damage
	
	Blue Flow (Animation Events):
	   - start: VFX/sounds
	   - open: Spawn hitbox, start pulling
	   - _finish: Cleanup, restore weapon
	
	Red Flow (Animation Events):
	   - start: Start charging VFX
	   - freeze: Pause animation, player aims
	   - (release): Resume animation
	   - shoot: Fire projectile
	   - _finish: Cleanup, restore weapon
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local Hitbox = require(Locations.Shared.Util:WaitForChild("Hitbox"))
local ProjectilePhysics = require(Locations.Shared.Util:WaitForChild("ProjectilePhysics"))

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Animation names
local BLUE_ANIM_NAME = "Blue"
local RED_ANIM_NAME = "Red"

-- BLUE ABILITY (Pull/Vacuum with Orbit)
local BLUE_CONFIG = {
	HITBOX_RADIUS = 14,          -- Studs - size of the vacuum sphere
	TRAVEL_DISTANCE = 60,        -- Studs - how far forward it travels
	LIFETIME = 3.5,              -- Seconds - how long it's active

	-- Start position
	START_DISTANCE = 10,         -- Default start distance in front of player
	RAYCAST_DISTANCE = 15,       -- Raycast forward to find surface

	-- Pull + Orbit settings (creates swirling effect)
	PULL_MIN_STRENGTH = 25,      -- Pull strength when very close to center
	PULL_MAX_STRENGTH = 50,      -- Pull strength when at edge of hitbox
	ORBIT_STRENGTH = 30,         -- Tangential velocity for orbit effect
	PULL_UPWARD = 20,            -- Slight upward to keep them floating

	-- Explosion settings
	EXPLOSION_UPWARD = 90,      -- Upward velocity on explosion
	EXPLOSION_OUTWARD = 80,     -- Outward velocity on explosion

	-- Technical
	TICK_RATE = 0.03,            -- Seconds between each tick (~33hz)
	HITBOX_LERP_SPEED = 6.5,       -- How fast hitbox follows aim (higher = faster)
}

-- RED ABILITY (Piercing Projectile) - Uses ProjectilePhysics
local RED_CONFIG = {
	-- Projectile settings (FAST!)
	PROJECTILE_SPEED = 400,      -- Studs per second (was 200, now 2x faster)
	MAX_RANGE = 321,             -- Max distance before despawn
	PROJECTILE_RADIUS = 1.5,     -- Visual size (smaller, was 3)
	
	-- Damage
	BODY_DAMAGE = 35,            -- Normal hit damage
	HEADSHOT_DAMAGE = 90,        -- Crit/headshot damage
	EXPLOSION_DAMAGE = 10,       -- AoE explosion damage
	
	-- Explosion
	EXPLOSION_RADIUS = 20,       -- Studs
	EXPLOSION_UPWARD = 60,       -- Upward knockback on explosion
	EXPLOSION_OUTWARD = 100,     -- Outward knockback on explosion
}

-- ProjectilePhysics config for Red (straight line, no gravity)
local RED_PHYSICS_CONFIG = {
	speed = RED_CONFIG.PROJECTILE_SPEED,
	gravity = 0,       -- Flies straight
	drag = 0,          -- No slowdown
	lifetime = RED_CONFIG.MAX_RANGE / RED_CONFIG.PROJECTILE_SPEED + 0.2,  -- ~1 second total
}

--------------------------------------------------------------------------------
-- Debug Helpers
--------------------------------------------------------------------------------

local function log(...)
	print("[HonoredOne Client]", ...)
end

local function createDebugSphere(position, radius, color, duration)
	local part = Instance.new("Part")
	part.Name = "BlueHitboxViz"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	part.CFrame = CFrame.new(position)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0.6
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(0, 150, 255)
	part.Parent = Workspace
	
	if duration then
		Debris:AddItem(part, duration)
	end
	
	return part
end

local function getEffectsFolder()
	local folder = Workspace:FindFirstChild("Effects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local HonoredOne = {}
HonoredOne.__index = HonoredOne

HonoredOne.Ability = {}
HonoredOne.Ultimate = {}

HonoredOne._ctx = nil
HonoredOne._connections = {}
HonoredOne._abilityState = nil

--------------------------------------------------------------------------------
-- Blue Ability - Moving Vacuum Hitbox (Pull)
-- Called from animation "open" event
--------------------------------------------------------------------------------

local function runBlueHitbox(state)
	local abilityRequest = state.abilityRequest
	local character = state.character
	
	log("=== BLUE HITBOX OPEN ===")
	
	local knockbackController = ServiceRegistry:GetController("Knockback")
	if not knockbackController then
		warn("[HonoredOne] KnockbackController not found!")
	end
	
	local camera = Workspace.CurrentCamera
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
	if not hrp then return end
	
	-- Get current look direction
	local lookVector = camera.CFrame.LookVector
	
	-- Default start position: 10 studs in front of player
	local defaultStart = hrp.Position + (lookVector * BLUE_CONFIG.START_DISTANCE)
	
	-- Raycast to find surface within 15 studs
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local effectsFolder = Workspace:FindFirstChild("Effects")
	rayParams.FilterDescendantsInstances = effectsFolder and { character, effectsFolder } or { character }
	
	local rayResult = Workspace:Raycast(hrp.Position, lookVector * BLUE_CONFIG.RAYCAST_DISTANCE, rayParams)
	
	local startPosition
	if rayResult and rayResult.Position then
		-- Hit a surface - start there
		startPosition = rayResult.Position
		log("Hitbox starting on SURFACE at:", startPosition)
	else
		-- No surface - start 10 studs in front
		startPosition = defaultStart
		log("Hitbox starting 10 STUDS IN FRONT at:", startPosition)
	end
	
	local elapsed = 0
	local pullCount = 0
	
	-- CAPTURED TARGETS - once caught, they stay caught until ability ends
	local capturedTargets = {}
	
	-- Current hitbox position (will lerp smoothly)
	local currentPosition = startPosition
	local targetPosition = startPosition
	
	-- Create the visual hitbox sphere
	local hitboxViz = createDebugSphere(startPosition, BLUE_CONFIG.HITBOX_RADIUS, Color3.fromRGB(0, 100, 255))
	hitboxViz.Name = "BlueHitbox_Active"
	hitboxViz.Parent = getEffectsFolder()
	
	-- Store for cleanup on cancel
	state.hitboxViz = hitboxViz
	state.hitboxActive = true
	
	log("Created hitbox visualization")
	
	-- Main ability loop (runs for full LIFETIME, independent of animation)
	while elapsed < BLUE_CONFIG.LIFETIME do
		-- Only stop if hard cancelled (interrupt/weapon switch)
		if state.cancelled then
			log("Blue hitbox cancelled early")
			break
		end
		
		local dt = task.wait(BLUE_CONFIG.TICK_RATE)
		elapsed += dt
		
		-- GET CURRENT LOOK DIRECTION (follows player's aim!)
		local currentLookVector = camera.CFrame.LookVector
		
		-- Calculate distance based on progress (grows from START_DISTANCE to TRAVEL_DISTANCE)
		local progress = elapsed / BLUE_CONFIG.LIFETIME
		local currentDistance = BLUE_CONFIG.START_DISTANCE + 
			(BLUE_CONFIG.TRAVEL_DISTANCE - BLUE_CONFIG.START_DISTANCE) * progress
		
		-- Target position is CURRENT player position + distance in look direction
		-- This keeps hitbox relative to player, not a fixed start point
		local playerPos = hrp.Position
		targetPosition = playerPos + (currentLookVector * currentDistance)
		
		-- SMOOTHLY LERP current position toward target
		local lerpAlpha = math.min(1, BLUE_CONFIG.HITBOX_LERP_SPEED * dt)
		currentPosition = currentPosition:Lerp(targetPosition, lerpAlpha)
		
		-- Update visual
		if hitboxViz and hitboxViz.Parent then
			hitboxViz.CFrame = CFrame.new(currentPosition)
		end
		
		-- Find NEW targets entering the sphere and add to captured list
		local newTargets = Hitbox.GetCharactersInSphere(currentPosition, BLUE_CONFIG.HITBOX_RADIUS, {
			Exclude = abilityRequest.player,
		})
		
		for _, targetChar in ipairs(newTargets) do
			if not capturedTargets[targetChar] then
				-- Assign random orbit parameters for this target
				capturedTargets[targetChar] = {
					orbitDirection = math.random() > 0.5 and 1 or -1,  -- Clockwise or counter-clockwise
					orbitAngle = math.random() * math.pi * 2,          -- Random starting angle
					orbitSpeed = 0.8 + math.random() * 0.4,            -- Speed variation (0.8 to 1.2)
				}
				log("CAPTURED:", targetChar.Name, "orbit dir:", capturedTargets[targetChar].orbitDirection)
			end
		end
		
		-- Apply ORBIT + PULL to ALL CAPTURED targets (even if they've left the radius)
		for targetChar, orbitData in pairs(capturedTargets) do
			-- Check if target still exists
			if not targetChar or not targetChar.Parent then
				capturedTargets[targetChar] = nil
				continue
			end
			
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Root") or targetChar.PrimaryPart
			if targetRoot and knockbackController then
				local toCenter = (currentPosition - targetRoot.Position)
				local distance = toCenter.Magnitude
				
				if distance > 0.5 then
					local pullDirection = toCenter.Unit
					
					-- Scale pull strength based on distance (stronger when further away)
					local distanceRatio = math.clamp(distance / BLUE_CONFIG.HITBOX_RADIUS, 0, 1.5)
					local pullStrength = BLUE_CONFIG.PULL_MIN_STRENGTH + 
						(BLUE_CONFIG.PULL_MAX_STRENGTH - BLUE_CONFIG.PULL_MIN_STRENGTH) * distanceRatio
					
					-- Calculate TANGENTIAL velocity for orbit (perpendicular to pull)
					-- Use random orbit angle for variety
					local baseAngle = orbitData.orbitAngle + (elapsed * 2) -- Rotate over time
					local rotatedUp = CFrame.fromAxisAngle(pullDirection, baseAngle) * Vector3.yAxis
					local tangent = pullDirection:Cross(rotatedUp)
					if tangent.Magnitude < 0.1 then
						tangent = pullDirection:Cross(Vector3.xAxis)
					end
					tangent = tangent.Unit
					
					-- Apply random direction and speed variation
					tangent = tangent * orbitData.orbitDirection * orbitData.orbitSpeed
					
					-- Build combined velocity: pull inward + orbit tangentially + slight lift
					local pullVelocity = pullDirection * pullStrength
					local orbitVelocity = tangent * BLUE_CONFIG.ORBIT_STRENGTH
					local liftVelocity = Vector3.new(0, BLUE_CONFIG.PULL_UPWARD, 0)
					
					local totalVelocity = pullVelocity + orbitVelocity + liftVelocity
					
					knockbackController:_sendKnockbackVelocity(targetChar, totalVelocity, 0)
					pullCount += 1
					
					if pullCount % 20 == 1 then
						log(string.format("Orbiting %s (dist: %.1f)", targetChar.Name, distance))
					end
				end
			else
				-- Target lost root, remove from captured
				capturedTargets[targetChar] = nil
			end
		end
	end
	
	-- Check if cancelled before explosion
	if state.cancelled then
		if hitboxViz and hitboxViz.Parent then
			hitboxViz:Destroy()
		end
		state.hitboxActive = false
		return
	end
	
	log("=== BLUE HITBOX LIFETIME ENDED ===")
	log("Total pulls:", pullCount)
	
	-- EXPLOSION at end (use current lerped position)
	local finalPosition = currentPosition
	log("Final explosion at:", finalPosition)
	
	-- Update visual for explosion
	if hitboxViz and hitboxViz.Parent then
		hitboxViz.CFrame = CFrame.new(finalPosition)
		hitboxViz.Color = Color3.fromRGB(255, 100, 0)
		hitboxViz.Size = Vector3.new(BLUE_CONFIG.HITBOX_RADIUS * 4, BLUE_CONFIG.HITBOX_RADIUS * 4, BLUE_CONFIG.HITBOX_RADIUS * 4)
		Debris:AddItem(hitboxViz, 0.5)
	end
	
	-- Explosion knockback to ALL CAPTURED targets (no damage, just knockback)
	local capturedCount = 0
	for _ in pairs(capturedTargets) do capturedCount += 1 end
	log("Explosion on", capturedCount, "captured targets")
	
	for targetChar, orbitData in pairs(capturedTargets) do
		if not targetChar or not targetChar.Parent then continue end
		
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Root") or targetChar.PrimaryPart
		if targetRoot and knockbackController then
			local awayFromCenter = (targetRoot.Position - finalPosition)
			local outwardDir = awayFromCenter.Magnitude > 0.1 and awayFromCenter.Unit or Vector3.new(0, 0, 1)
			local explosionVelocity = (outwardDir * BLUE_CONFIG.EXPLOSION_OUTWARD) + Vector3.new(0, BLUE_CONFIG.EXPLOSION_UPWARD, 0)
			
			knockbackController:_sendKnockbackVelocity(targetChar, explosionVelocity, 0)
			log("EXPLOSION:", targetChar.Name)
		end
	end
	
	-- Blue ability does NO damage - just knockback/CC
	log("Blue ability complete - no damage sent")
	
	-- Hitbox finished - clear state
	state.hitboxActive = false
	if HonoredOne._abilityState == state then
		HonoredOne._abilityState = nil
	end
	
	log("=== BLUE HITBOX COMPLETE ===")
end

--------------------------------------------------------------------------------
-- Red Ability - Piercing Projectile (Using ProjectilePhysics + Collider Hitbox)
-- Called from animation "shoot" event when crouching
--------------------------------------------------------------------------------

-- Helper: Get player from hit using Collider/Hitbox system (matches WeaponProjectile)
local function getPlayerFromHit(hitInstance)
	if not hitInstance then
		return nil, nil, false
	end
	
	-- Check for Collider model with OwnerUserId (player hitboxes)
	local current = hitInstance
	while current and current ~= Workspace do
		if current.Name == "Collider" then
			local hitboxFolder = current:FindFirstChild("Hitbox")
			if not hitboxFolder or not hitInstance:IsDescendantOf(hitboxFolder) then
				return nil, nil, false
			end
			
			-- Must be inside Standing or Crouching subfolder
			local standingFolder = hitboxFolder:FindFirstChild("Standing")
			local crouchingFolder = hitboxFolder:FindFirstChild("Crouching")
			local validHit = false
			if standingFolder and hitInstance:IsDescendantOf(standingFolder) then
				validHit = true
			elseif crouchingFolder and hitInstance:IsDescendantOf(crouchingFolder) then
				validHit = true
			end
			
			if not validHit then
				return nil, nil, false
			end
			
			local ownerUserId = current:GetAttribute("OwnerUserId")
			if ownerUserId then
				local player = Players:GetPlayerByUserId(ownerUserId)
				if player then
					-- Headshot = hit part named "Head"
					local isHeadshot = hitInstance.Name == "Head"
					return player, player.Character, isHeadshot
				end
			end
			break
		end
		current = current.Parent
	end
	
	-- Check for dummies/rigs (no Collider, but has Humanoid)
	current = hitInstance.Parent
	if current and current.Name == "Root" and current:IsA("BasePart") then
		current = current.Parent
	end
	
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local humanoid = current:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid then
				-- Check if player character (skip - should use Collider)
				local player = Players:GetPlayerFromCharacter(current)
				if player then
					return nil, nil, false
				end
				-- It's a dummy/rig
				local isHeadshot = hitInstance.Name == "Head" or hitInstance.Name == "HitboxHead"
				return nil, current, isHeadshot
			end
		end
		current = current.Parent
	end
	
	return nil, nil, false
end

local function runRedProjectile(state)
	local abilityRequest = state.abilityRequest
	local character = state.character
	
	log("=== RED PROJECTILE FIRED ===")
	
	local knockbackController = ServiceRegistry:GetController("Knockback")
	if not knockbackController then
		warn("[HonoredOne] KnockbackController not found!")
	end
	
	local camera = Workspace.CurrentCamera
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
	if not hrp then return end
	
	-- Get fire direction and starting position
	local direction = camera.CFrame.LookVector
	local startPosition = hrp.Position + (direction * 3) + Vector3.new(0, 1, 0)
	
	log("Start:", startPosition, "Direction:", direction, "Speed:", RED_CONFIG.PROJECTILE_SPEED)
	
	-- Create projectile physics
	local physics = ProjectilePhysics.new(RED_PHYSICS_CONFIG)
	local position = startPosition
	local velocity = direction * RED_CONFIG.PROJECTILE_SPEED
	
	-- Create projectile visual (debug sphere - red)
	local projectileViz = Instance.new("Part")
	projectileViz.Name = "RedProjectile"
	projectileViz.Shape = Enum.PartType.Ball
	projectileViz.Size = Vector3.new(RED_CONFIG.PROJECTILE_RADIUS * 2, RED_CONFIG.PROJECTILE_RADIUS * 2, RED_CONFIG.PROJECTILE_RADIUS * 2)
	projectileViz.CFrame = CFrame.new(startPosition)
	projectileViz.Anchored = true
	projectileViz.CanCollide = false
	projectileViz.CanQuery = false
	projectileViz.CanTouch = false
	projectileViz.Transparency = 0.3
	projectileViz.Material = Enum.Material.Neon
	projectileViz.Color = Color3.fromRGB(255, 50, 50)
	projectileViz.Parent = getEffectsFolder()
	
	state.projectileViz = projectileViz
	state.projectileActive = true
	
	-- Raycast params - exclude self, effects, and pierced targets
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local effectsFolder = Workspace:FindFirstChild("Effects")
	local filterList = { character }
	if effectsFolder then table.insert(filterList, effectsFolder) end
	rayParams.FilterDescendantsInstances = filterList
	
	-- Track state
	local piercedTargets = {} -- { [userId or charName] = true }
	local hitList = {}
	local distanceTraveled = 0
	local exploded = false
	
	-- Use Heartbeat for smooth physics
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		-- Check for cancel
		if state.cancelled then
			connection:Disconnect()
			if projectileViz and projectileViz.Parent then
				projectileViz:Destroy()
			end
			state.projectileActive = false
			return
		end
		
		-- Check max range
		if distanceTraveled >= RED_CONFIG.MAX_RANGE then
			connection:Disconnect()
			exploded = true
			return
		end
		
		-- Step physics (uses ProjectilePhysics for consistent simulation)
		local newPosition, newVelocity, hitResult = physics:Step(position, velocity, dt, rayParams)
		local moveDistance = (newPosition - position).Magnitude
		distanceTraveled += moveDistance
		
		-- Check if hit something
		if hitResult then
			local hitPlayer, hitCharacter, isHeadshot = getPlayerFromHit(hitResult.Instance)
			
			if hitPlayer then
				-- Hit a player's Collider/Hitbox - pierce through
				local targetId = hitPlayer.UserId
				
				if not piercedTargets[targetId] then
					piercedTargets[targetId] = true
					
					local damage = isHeadshot and RED_CONFIG.HEADSHOT_DAMAGE or RED_CONFIG.BODY_DAMAGE
					log(string.format("PIERCED %s (%s) - %d damage", 
						hitPlayer.Name, 
						isHeadshot and "HEADSHOT" or "body",
						damage
					))
					
					-- No knockback on pierce (just damage)
					
					-- Add to hit list
					table.insert(hitList, {
						playerId = targetId,
						isHeadshot = isHeadshot,
						damage = damage,
						hitPosition = { X = hitResult.Position.X, Y = hitResult.Position.Y, Z = hitResult.Position.Z },
					})
					
					-- Add character to filter so we don't hit again
					local filter = rayParams.FilterDescendantsInstances
					table.insert(filter, hitPlayer.Character)
					rayParams.FilterDescendantsInstances = filter
				end
				
			elseif hitCharacter then
				-- Hit a dummy/rig
				local targetId = hitCharacter:GetFullName()
				
				if not piercedTargets[targetId] then
					piercedTargets[targetId] = true
					
					local damage = isHeadshot and RED_CONFIG.HEADSHOT_DAMAGE or RED_CONFIG.BODY_DAMAGE
					log(string.format("PIERCED DUMMY %s (%s) - %d damage", 
						hitCharacter.Name, 
						isHeadshot and "HEADSHOT" or "body",
						damage
					))
					
					-- No knockback on pierce (just damage)
					
					-- Add to hit list
					table.insert(hitList, {
						characterName = hitCharacter.Name,
						isDummy = true,
						isHeadshot = isHeadshot,
						damage = damage,
					})
					
					-- Add to filter
					local filter = rayParams.FilterDescendantsInstances
					table.insert(filter, hitCharacter)
					rayParams.FilterDescendantsInstances = filter
				end
				
			else
				-- Hit world/environment - explode here
				log("Hit world at:", hitResult.Position)
				position = hitResult.Position
				
				if projectileViz and projectileViz.Parent then
					projectileViz.CFrame = CFrame.new(position)
				end
				
				connection:Disconnect()
				exploded = true
				return
			end
		end
		
		-- Update state
		position = newPosition
		velocity = newVelocity
		
		-- Update visual
		if projectileViz and projectileViz.Parent then
			projectileViz.CFrame = CFrame.lookAt(position, position + velocity.Unit)
		end
	end)
	
	-- Wait for projectile to finish
	while state.projectileActive and not exploded and not state.cancelled do
		task.wait(0.05)
	end
	
	-- Disconnect if still connected
	if connection.Connected then
		connection:Disconnect()
	end
	
	-- Check if cancelled
	if state.cancelled then
		if projectileViz and projectileViz.Parent then
			projectileViz:Destroy()
		end
		state.projectileActive = false
		return
	end
	
	log("=== RED PROJECTILE EXPLOSION ===")
	log("Explosion at:", position)
	
	-- Explosion visual
	if projectileViz and projectileViz.Parent then
		projectileViz.Color = Color3.fromRGB(255, 150, 50)
		projectileViz.Size = Vector3.new(RED_CONFIG.EXPLOSION_RADIUS * 2, RED_CONFIG.EXPLOSION_RADIUS * 2, RED_CONFIG.EXPLOSION_RADIUS * 2)
		projectileViz.Transparency = 0.6
		Debris:AddItem(projectileViz, 0.5)
	end
	
	-- Find targets in explosion radius
	local explosionTargets = Hitbox.GetCharactersInSphere(position, RED_CONFIG.EXPLOSION_RADIUS, {
		Exclude = abilityRequest.player,
	})
	
	log("Explosion targets:", #explosionTargets)
	
	for _, targetChar in ipairs(explosionTargets) do
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Root") or targetChar.PrimaryPart
		if targetRoot and knockbackController then
			-- Knockback away from explosion
			local awayDir = (targetRoot.Position - position)
			awayDir = awayDir.Magnitude > 0.1 and awayDir.Unit or direction
			
			local explosionVelocity = (awayDir * RED_CONFIG.EXPLOSION_OUTWARD) + Vector3.new(0, RED_CONFIG.EXPLOSION_UPWARD, 0)
			knockbackController:_sendKnockbackVelocity(targetChar, explosionVelocity, 0)
			
			log("Explosion knockback:", targetChar.Name)
		end
		
		-- Add explosion damage if not already pierced
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		local targetId = targetPlayer and targetPlayer.UserId or targetChar:GetFullName()
		
		if not piercedTargets[targetId] then
			table.insert(hitList, {
				playerId = targetPlayer and targetPlayer.UserId or nil,
				characterName = targetChar.Name,
				isDummy = targetPlayer == nil,
				isHeadshot = false,
				isExplosion = true,
				damage = RED_CONFIG.EXPLOSION_DAMAGE,
			})
		end
	end
	
	-- Send all hits to server
	if #hitList > 0 then
		log("Sending", #hitList, "hits to server")
		abilityRequest.Send({
			action = "redHit",
			hits = hitList,
			explosionPosition = { X = position.X, Y = position.Y, Z = position.Z },
		})
	end
	
	state.projectileActive = false
	if HonoredOne._abilityState == state then
		HonoredOne._abilityState = nil
	end
	
	log("=== RED PROJECTILE COMPLETE ===")
end

--------------------------------------------------------------------------------
-- Ability: E Press - DUALITY (Animation-Driven)
--------------------------------------------------------------------------------

function HonoredOne.Ability:OnStart(abilityRequest)
	local hrp = abilityRequest.humanoidRootPart
	local character = abilityRequest.character
	if not hrp or not character then 
		log("ERROR: No character/hrp")
		return 
	end

	local kitController = ServiceRegistry:GetController("Kit")
	local inputManager = ServiceRegistry:GetController("Input")

	if kitController:IsAbilityActive() then 
		log("Ability already active, ignoring")
		return 
	end
	if abilityRequest.IsOnCooldown() then 
		log("Ability on cooldown, ignoring")
		return 
	end

	-- Check crouch state to determine Blue vs Red
	local isCrouching = false
	if inputManager and inputManager.IsCrouchHeld then
		isCrouching = inputManager:IsCrouchHeld()
	end
	
	log("Crouch check:", isCrouching and "CROUCHING (Red/Push)" or "NOT CROUCHING (Blue/Pull)")

	-- Start ability
	local ctx = abilityRequest.StartAbility()
	local unlock = kitController:LockWeaponSwitch()

	-- Get viewmodel animator
	local viewmodelAnimator = ctx.viewmodelAnimator
	local viewmodelController = abilityRequest.viewmodelController
	local viewmodelRig = viewmodelController and viewmodelController:GetActiveRig()

	-- Choose animation based on crouch state
	local animName = isCrouching and RED_ANIM_NAME or BLUE_ANIM_NAME
	
	-- Play viewmodel animation
	local animation = viewmodelAnimator:PlayKitAnimation(animName, {
		priority = Enum.AnimationPriority.Action4,
		stopOthers = true,
	})

	if not animation then
		log("ERROR: Could not play animation:", animName)
		unlock()
		kitController:_unholsterWeapon()
		return
	end

	log("Playing animation:", animName)

	-- State tracking
	local state = {
		active = true,           -- Animation is playing
		hitboxActive = false,    -- Blue hitbox is running
		projectileActive = false, -- Red projectile is running
		cancelled = false,       -- Hard cancel (interrupt)
		released = false,        -- Button released (for Red freeze/aim)
		isCrouching = isCrouching,
		animation = animation,
		unlock = unlock,
		abilityRequest = abilityRequest,
		character = character,
		viewmodelRig = viewmodelRig,
		connections = {},
		hitboxViz = nil,
		projectileViz = nil,
	}
	HonoredOne._abilityState = state

	-- Animation event handlers
	local Events = {
		["start"] = function()
			log("Animation Event: start")
			-- VFX/sounds on ability start (charging for Red)
			-- TODO: Add VFXRep call for start effects
		end,

		["freeze"] = function()
			-- RED ONLY: Pause animation while player aims
			if not isCrouching then return end
			log("Animation Event: freeze (Red charging)")
			if state.active and not state.released then
				state.animation:AdjustSpeed(0)
			end
		end,

		["open"] = function()
			-- BLUE ONLY: Spawn hitbox
			if isCrouching then return end
			log("Animation Event: open (Blue)")
			if not state.active or state.cancelled then return end
			task.spawn(runBlueHitbox, state)
		end,

		["shoot"] = function()
			-- RED ONLY: Fire projectile
			if not isCrouching then return end
			log("Animation Event: shoot (Red)")
			if not state.active or state.cancelled then return end
			task.spawn(runRedProjectile, state)
		end,

		["_finish"] = function()
			log("Animation Event: _finish")
			if not state.active then return end
			
			state.active = false
			-- NOTE: Don't clear _abilityState yet - hitbox/projectile may still be running
			-- NOTE: Don't set cancelled - let ability run to completion

			-- Cleanup animation connections
			for _, conn in ipairs(state.connections) do
				if typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				end
			end
			state.connections = {}

			-- Restore weapon (animation done, but hitbox/projectile continues)
			state.unlock()
			kitController:_unholsterWeapon()
			log("Animation finished - weapon restored")
		end,
	}

	-- Connect to animation events
	state.connections[#state.connections + 1] = animation:GetMarkerReachedSignal("Event"):Connect(function(eventName)
		log("Animation marker received:", eventName)
		if Events[eventName] then
			Events[eventName]()
		end
	end)

	-- Safety cleanup on animation end
	state.connections[#state.connections + 1] = animation.Stopped:Once(function()
		if state.active then
			log("Animation stopped - triggering _finish")
			Events["_finish"]()
		end
	end)

	state.connections[#state.connections + 1] = animation.Ended:Once(function()
		if state.active then
			log("Animation ended - triggering _finish")
			Events["_finish"]()
		end
	end)
end

function HonoredOne.Ability:OnEnded(abilityRequest)
	local state = HonoredOne._abilityState
	if not state or not state.active then return end
	
	-- Mark as released
	state.released = true
	
	-- Resume animation from freeze (Red ability)
	if state.isCrouching and state.animation and state.animation.IsPlaying then
		log("OnEnded: Resuming Red animation")
		state.animation:AdjustSpeed(1)
	end
end

function HonoredOne.Ability:OnInterrupt(abilityRequest, reason)
	local state = HonoredOne._abilityState
	if not state then return end
	
	-- Already fully finished
	if not state.active and not state.hitboxActive and not state.projectileActive then return end

	log("Ability interrupted:", reason)
	
	-- Hard cancel - stops everything including hitbox/projectile
	state.cancelled = true
	state.active = false
	state.hitboxActive = false
	state.projectileActive = false
	HonoredOne._abilityState = nil

	-- Stop animation
	if state.animation and state.animation.IsPlaying then
		state.animation:Stop(0.1)
	end

	-- Cleanup hitbox visual (Blue)
	if state.hitboxViz and state.hitboxViz.Parent then
		state.hitboxViz:Destroy()
	end

	-- Cleanup projectile visual (Red)
	if state.projectileViz and state.projectileViz.Parent then
		state.projectileViz:Destroy()
	end

	-- Cleanup connections
	for _, conn in ipairs(state.connections or {}) do
		if typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end

	-- Restore weapon (if animation hadn't finished yet)
	if state.unlock then
		state.unlock()
	end
	ServiceRegistry:GetController("Kit"):_unholsterWeapon()
end

--------------------------------------------------------------------------------
-- Ultimate (placeholder)
--------------------------------------------------------------------------------

function HonoredOne.Ultimate:OnStart(abilityRequest)
	log("Ultimate not implemented yet")
	abilityRequest.Send()
end

function HonoredOne.Ultimate:OnEnded(abilityRequest)
end

function HonoredOne.Ultimate:OnInterrupt(abilityRequest, reason)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function HonoredOne.new(ctx)
	local self = setmetatable({}, HonoredOne)
	self._ctx = ctx
	self._connections = {}
	self.Ability = HonoredOne.Ability
	self.Ultimate = HonoredOne.Ultimate
	log("HonoredOne kit created")
	return self
end

function HonoredOne:OnEquip(ctx)
	self._ctx = ctx
	log("HonoredOne kit equipped")
end

function HonoredOne:OnUnequip(reason)
	log("HonoredOne kit unequipped:", reason)
	for _, conn in pairs(self._connections) do
		if typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end
	self._connections = {}

	-- Cancel active ability
	if HonoredOne._abilityState and HonoredOne._abilityState.active then
		HonoredOne.Ability:OnInterrupt(nil, "unequip")
	end
end

function HonoredOne:Destroy()
	self:OnUnequip("Destroy")
end

return HonoredOne
