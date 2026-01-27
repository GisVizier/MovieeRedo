--[[
	WeaponProjectile.lua
	
	Client-side projectile service for weapons that use the projectile system.
	Handles spawning, physics simulation, hit detection, and networking.
	
	Similar pattern to WeaponRaycast but for projectile weapons.
	
	Usage in Attack.lua:
		local WeaponProjectile = require(WeaponServices.WeaponProjectile)
		
		-- Fire a projectile
		local projectileId = WeaponProjectile:Fire(weaponInstance, {
			chargePercent = 1.0,
		})
]]

local WeaponProjectile = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local workspace = game:GetService("Workspace")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ProjectilePhysics = require(Locations.Shared.Util:WaitForChild("ProjectilePhysics"))
local ProjectilePacketUtils = require(Locations.Shared.Util:WaitForChild("ProjectilePacketUtils"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local LocalPlayer = Players.LocalPlayer

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

local CONFIG = {
	-- Debug (set to true to see hit markers and logs)
	DebugVisualization = true,
	DebugLogging = false,
	
	-- Simulation
	PhysicsTickRate = 1/60,    -- 60 Hz physics
	MaxActiveProjectiles = 50, -- Per player limit (increased for shotgun pellets)
	
	-- Visual
	DefaultTracerLength = 5,
	DefaultTracerColor = Color3.fromRGB(255, 200, 100),
}

-- =============================================================================
-- STATE
-- =============================================================================

local ActiveProjectiles = {} -- { [projectileId] = projectileData }
local SimulationConnection = nil
local Net = nil

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

--[[
	Initialize the projectile service
	
	@param net table - Network module for events
]]
function WeaponProjectile:Init(net)
	Net = net
	
	-- Start simulation loop
	self:_startSimulation()
	
	-- Listen for server confirmations
	if Net then
		Net:ConnectClient("ProjectileHitConfirmed", function(data)
			self:_onHitConfirmed(data)
		end)
		
		Net:ConnectClient("ProjectileDestroyed", function(data)
			self:_onProjectileDestroyed(data)
		end)
		
		-- Listen for other players' projectiles
		Net:ConnectClient("ProjectileReplicate", function(data)
			self:_onProjectileReplicate(data)
		end)
	end
	
	if CONFIG.DebugLogging then
		print("[WeaponProjectile] Initialized")
	end
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--[[
	Fire a projectile
	
	@param weaponInstance table - The weapon instance from WeaponController
	@param options table? - Optional parameters:
		{
			chargePercent = number, -- 0-1 for charged weapons
			spreadOverride = number?, -- Override spread angle
		}
	@return number? - Projectile ID, or nil if failed
]]
function WeaponProjectile:Fire(weaponInstance, options)
	options = options or {}
	
	if not weaponInstance or not weaponInstance.Config then
		warn("[WeaponProjectile] Invalid weapon instance")
		return nil
	end
	
	local weaponConfig = weaponInstance.Config
	local projectileConfig = weaponConfig.projectile
	
	if not projectileConfig then
		warn("[WeaponProjectile] Weapon does not have projectile config:", weaponInstance.WeaponId)
		return nil
	end
	
	-- Limit active projectiles
	local count = 0
	for _ in pairs(ActiveProjectiles) do
		count = count + 1
	end
	if count >= CONFIG.MaxActiveProjectiles then
		-- Remove oldest
		local oldestId, oldestTime = nil, math.huge
		for id, proj in pairs(ActiveProjectiles) do
			if proj.fireTimestamp < oldestTime then
				oldestId = id
				oldestTime = proj.fireTimestamp
			end
		end
		if oldestId then
			self:_destroyProjectile(oldestId, "MaxProjectiles")
		end
	end
	
	-- Get fire origin and direction
	local origin, direction = self:_getFireOriginAndDirection(weaponInstance)
	if not origin or not direction then
		warn("[WeaponProjectile] Failed to get fire origin/direction")
		return nil
	end
	
	-- Calculate charge multipliers
	local chargePercent = options.chargePercent or 1
	local chargeMults = ProjectilePhysics.new(projectileConfig):CalculateChargeMultipliers(
		projectileConfig.charge,
		chargePercent * (projectileConfig.charge and projectileConfig.charge.maxTime or 1)
	)
	
	-- Calculate spread
	local spreadState = self:_getSpreadState(weaponInstance)
	local spreadAngle = self:_calculateSpread(projectileConfig, spreadState, weaponConfig.crosshair)
	spreadAngle = spreadAngle * (chargeMults.spreadMult or 1)
	
	-- Apply spread override if provided
	if options.spreadOverride then
		spreadAngle = options.spreadOverride
	end
	
	-- Apply spread to direction
	local physics = ProjectilePhysics.new(projectileConfig)
	local spreadSeed = math.random(0, 65535)
	
	local spreadMode = projectileConfig.spreadMode or "Cone"
	local finalDirections = {}
	
	if spreadMode == "Pattern" then
		-- Pattern spread (shotgun)
		finalDirections = physics:ApplyPatternSpread(
			direction,
			projectileConfig.spreadPattern,
			projectileConfig.spreadRandomization
		)
	elseif spreadMode == "Cone" then
		-- Cone spread (single projectile with random offset)
		local spreadDir = physics:ApplySpread(direction, spreadAngle, spreadSeed)
		table.insert(finalDirections, spreadDir)
	else
		-- No spread
		table.insert(finalDirections, direction.Unit)
	end
	
	-- Calculate final speed
	local speed = projectileConfig.speed * (chargeMults.speedMult or 1)
	
	-- Fire timestamp
	local fireTimestamp = workspace:GetServerTimeNow()
	
	-- Create projectiles for each direction (usually 1, multiple for shotgun)
	local projectileIds = {}
	
	for _, finalDirection in ipairs(finalDirections) do
		-- Create spawn packet
		local packetString, projectileId = ProjectilePacketUtils:CreateSpawnPacket({
			origin = origin,
			direction = finalDirection,
			speed = speed,
			chargePercent = chargePercent,
			timestamp = fireTimestamp,
		}, weaponInstance.WeaponId, spreadSeed)
		
		if not packetString or not projectileId then
			warn("[WeaponProjectile] Failed to create spawn packet")
			continue
		end
		
		-- Create local projectile data
		local projectileData = {
			id = projectileId,
			weaponId = weaponInstance.WeaponId,
			weaponConfig = weaponConfig,
			projectileConfig = projectileConfig,
			
			-- Physics state
			position = origin,
			velocity = finalDirection * speed,
			physics = ProjectilePhysics.new(projectileConfig),
			
			-- Timing
			fireTimestamp = fireTimestamp,
			lifetime = projectileConfig.lifetime or 5,
			elapsed = 0,
			
			-- Behaviors
			pierceCount = 0,
			maxPierce = projectileConfig.pierce or 0,
			bounceCount = 0,
			maxBounce = projectileConfig.ricochet or 0,
			hitTargets = {}, -- Track already-hit targets for pierce
			
			-- Charge
			chargePercent = chargePercent,
			chargeMults = chargeMults,
			
			-- Visual
			visual = nil, -- Will be created
			
			-- Network
			spawnPacket = packetString,
		}
		
		-- Store projectile
		ActiveProjectiles[projectileId] = projectileData
		
		-- Send spawn to server
		if Net and weaponInstance.Net then
			weaponInstance.Net:FireServer("ProjectileSpawned", {
				packet = packetString,
				weaponId = weaponInstance.WeaponId,
			})
		end
		
		-- Spawn visual
		self:_spawnVisual(projectileData)
		
		table.insert(projectileIds, projectileId)
		
		if CONFIG.DebugLogging then
			print(string.format(
				"[WeaponProjectile] Fired %s (ID: %d) at %.0f studs/sec",
				weaponInstance.WeaponId,
				projectileId,
				speed
			))
		end
	end
	
	-- Return first projectile ID (or array if multiple)
	if #projectileIds == 1 then
		return projectileIds[1]
	else
		return projectileIds
	end
end

--[[
	Fire multiple pellets (shotgun-style)
	
	Each pellet is a separate projectile with random cone spread.
	Server validates each pellet hit independently.
	
	@param weaponInstance table - The weapon instance from WeaponController
	@param options table? - Optional parameters:
		{
			pelletsPerShot = number, -- Override pellet count
		}
	@return table? - Array of projectile IDs, or nil if failed
]]
function WeaponProjectile:FirePellets(weaponInstance, options)
	options = options or {}
	
	if not weaponInstance or not weaponInstance.Config then
		warn("[WeaponProjectile] Invalid weapon instance for pellets")
		return nil
	end
	
	local weaponConfig = weaponInstance.Config
	local projectileConfig = weaponConfig.projectile
	
	if not projectileConfig then
		warn("[WeaponProjectile] Weapon does not have projectile config:", weaponInstance.WeaponId)
		return nil
	end
	
	-- Get pellet count
	local pelletsPerShot = options.pelletsPerShot or projectileConfig.pelletsPerShot or weaponConfig.pelletsPerShot or 8
	
	-- Get fire origin and direction
	local origin, baseDirection = self:_getFireOriginAndDirection(weaponInstance)
	if not origin or not baseDirection then
		warn("[WeaponProjectile] Failed to get fire origin/direction for pellets")
		return nil
	end
	
	-- Calculate spread
	local spreadState = self:_getSpreadState(weaponInstance)
	local baseSpread = self:_calculateSpread(projectileConfig, spreadState, weaponConfig.crosshair)
	
	-- Fire timestamp (same for all pellets)
	local fireTimestamp = workspace:GetServerTimeNow()
	
	-- Pellet speed
	local speed = projectileConfig.speed
	
	-- Create physics for spread calculation
	local physics = ProjectilePhysics.new(projectileConfig)
	
	-- Fire each pellet
	local projectileIds = {}
	
	for i = 1, pelletsPerShot do
		-- Limit active projectiles
		local count = 0
		for _ in pairs(ActiveProjectiles) do
			count = count + 1
		end
		if count >= CONFIG.MaxActiveProjectiles * 2 then -- Allow more for pellets
			local oldestId, oldestTime = nil, math.huge
			for id, proj in pairs(ActiveProjectiles) do
				if proj.fireTimestamp < oldestTime then
					oldestId = id
					oldestTime = proj.fireTimestamp
				end
			end
			if oldestId then
				self:_destroyProjectile(oldestId, "MaxProjectiles")
			end
		end
		
		-- Apply random cone spread to each pellet
		local spreadSeed = math.random(0, 65535)
		local pelletDirection = physics:ApplySpread(baseDirection, baseSpread, spreadSeed)
		
		-- Create spawn packet
		local packetString, projectileId = ProjectilePacketUtils:CreateSpawnPacket({
			origin = origin,
			direction = pelletDirection,
			speed = speed,
			chargePercent = 1, -- Pellets don't charge
			timestamp = fireTimestamp,
		}, weaponInstance.WeaponId, spreadSeed)
		
		if not packetString or not projectileId then
			warn("[WeaponProjectile] Failed to create pellet spawn packet", i)
			continue
		end
		
		-- Create local projectile data
		local projectileData = {
			id = projectileId,
			weaponId = weaponInstance.WeaponId,
			weaponConfig = weaponConfig,
			projectileConfig = projectileConfig,
			
			-- Physics state
			position = origin,
			velocity = pelletDirection * speed,
			physics = ProjectilePhysics.new(projectileConfig),
			
			-- Timing
			fireTimestamp = fireTimestamp,
			lifetime = projectileConfig.lifetime or 5,
			elapsed = 0,
			
			-- Behaviors
			pierceCount = 0,
			maxPierce = projectileConfig.pierce or 0,
			bounceCount = 0,
			maxBounce = projectileConfig.ricochet or 0,
			hitTargets = {},
			
			-- Charge (not used for pellets)
			chargePercent = 1,
			chargeMults = { damageMult = 1, speedMult = 1, spreadMult = 1 },
			
			-- Visual
			visual = nil,
			
			-- Network
			spawnPacket = packetString,
			
			-- Pellet metadata
			isPellet = true,
			pelletIndex = i,
		}
		
		-- Store projectile
		ActiveProjectiles[projectileId] = projectileData
		
		-- Send spawn to server (batch all pellets together)
		if Net and weaponInstance.Net then
			weaponInstance.Net:FireServer("ProjectileSpawned", {
				packet = packetString,
				weaponId = weaponInstance.WeaponId,
				isPellet = true,
				pelletIndex = i,
				pelletsPerShot = pelletsPerShot,
			})
		end
		
		-- Spawn visual
		self:_spawnVisual(projectileData)
		
		table.insert(projectileIds, projectileId)
	end
	
	if CONFIG.DebugLogging then
		print(string.format(
			"[WeaponProjectile] Fired %d pellets (%s) at %.0f studs/sec",
			#projectileIds,
			weaponInstance.WeaponId,
			speed
		))
	end
	
	return projectileIds
end

--[[
	Check if a weapon uses the projectile system
	
	@param weaponConfig table - Weapon configuration
	@return boolean - True if projectile weapon
]]
function WeaponProjectile:IsProjectileWeapon(weaponConfig)
	return ProjectilePacketUtils:IsProjectileWeapon(weaponConfig)
end

--[[
	Get active projectiles
	
	@return table - Map of projectile ID to data
]]
function WeaponProjectile:GetActiveProjectiles()
	return ActiveProjectiles
end

--[[
	Cancel/destroy a specific projectile
	
	@param projectileId number - The projectile to destroy
]]
function WeaponProjectile:DestroyProjectile(projectileId)
	self:_destroyProjectile(projectileId, "Cancelled")
end

-- =============================================================================
-- SIMULATION
-- =============================================================================

--[[
	Start the physics simulation loop
]]
function WeaponProjectile:_startSimulation()
	if SimulationConnection then
		return
	end
	
	local lastTime = os.clock()
	
	SimulationConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = now - lastTime
		lastTime = now
		
		self:_simulateProjectiles(dt)
	end)
end

--[[
	Simulate all active projectiles
]]
function WeaponProjectile:_simulateProjectiles(dt)
	for projectileId, projectile in pairs(ActiveProjectiles) do
		local shouldDestroy, destroyReason = self:_simulateProjectile(projectile, dt)
		
		if shouldDestroy then
			self:_destroyProjectile(projectileId, destroyReason)
		end
	end
end

--[[
	Simulate a single projectile
	
	@return boolean, string - Should destroy, reason
]]
function WeaponProjectile:_simulateProjectile(projectile, dt)
	-- Update elapsed time
	projectile.elapsed = projectile.elapsed + dt
	
	-- Check lifetime
	if projectile.elapsed >= projectile.lifetime then
		return true, "Timeout"
	end
	
	-- Create raycast params
	local raycastParams = self:_createRaycastParams(projectile)
	
	-- Step physics
	local newPosition, newVelocity, hitResult = projectile.physics:Step(
		projectile.position,
		projectile.velocity,
		dt,
		raycastParams
	)
	
	-- Handle collision
	if hitResult then
		local shouldContinue, reason = self:_handleCollision(projectile, hitResult)
		
		if not shouldContinue then
			return true, reason
		end
		
		-- Update position to just before hit (for ricochet)
		projectile.position = hitResult.Position
		-- Velocity already updated by ricochet handler if applicable
	else
		-- No collision, update state
		projectile.position = newPosition
		projectile.velocity = newVelocity
	end
	
	-- Update visual
	self:_updateVisual(projectile)
	
	-- Check if velocity is too low (stopped)
	if projectile.velocity.Magnitude < 1 then
		return true, "Stopped"
	end
	
	return false, nil
end

-- =============================================================================
-- COLLISION HANDLING
-- =============================================================================

--[[
	Handle projectile collision
	
	@return boolean, string - Should continue (true) or destroy (false), reason
]]
function WeaponProjectile:_handleCollision(projectile, hitResult)
	local hitInstance = hitResult.Instance
	
	-- Check if it's a player or rig hitbox
	local hitPlayer, hitCharacter, isHeadshot = self:_getPlayerFromHit(hitInstance)
	
	if hitCharacter then
		-- Check if it's our own character
		if hitPlayer and hitPlayer == LocalPlayer then
			-- Skip our own character
			return true, nil
		end
		
		-- Hit a player or rig/dummy
		return self:_handleTargetHit(projectile, hitResult, hitPlayer, hitCharacter, isHeadshot)
	else
		-- Hit environment
		return self:_handleEnvironmentHit(projectile, hitResult)
	end
end

--[[
	Handle hitting a target (player or rig/dummy)
]]
function WeaponProjectile:_handleTargetHit(projectile, hitResult, hitPlayer, hitCharacter, isHeadshot)
	-- Use userId for players, fullName for rigs
	local targetId = hitPlayer and hitPlayer.UserId or hitCharacter:GetFullName()
	
	-- Check if already hit this target (for pierce)
	if projectile.hitTargets[targetId] then
		-- Already hit, skip
		return true, nil
	end
	
	-- Mark as hit (store character reference for rigs to filter in raycasts)
	if hitPlayer then
		projectile.hitTargets[targetId] = true
	else
		projectile.hitTargets[targetId] = { character = hitCharacter }
	end
	projectile.pierceCount = projectile.pierceCount + 1
	
	-- Calculate impact timestamp
	local impactTimestamp = projectile.fireTimestamp + projectile.elapsed
	
	-- Create hit packet
	local hitPacket = ProjectilePacketUtils:CreateHitPacket({
		fireTimestamp = projectile.fireTimestamp,
		impactTimestamp = impactTimestamp,
		origin = projectile.position, -- Current position (start of this segment)
		hitPosition = hitResult.Position,
		hitPart = hitResult.Instance,
		hitPlayer = hitPlayer,
		hitCharacter = hitCharacter,
		isHeadshot = isHeadshot,
		projectileId = projectile.id,
		pierceCount = projectile.pierceCount - 1, -- Count before this hit
		bounceCount = projectile.bounceCount,
	}, projectile.weaponId)
	
	-- Send to server
	if Net and hitPacket then
		local rigName = not hitPlayer and hitCharacter.Name or nil
		
		print(string.format(
			"[WeaponProjectile] Sending hit to server - Target: %s, Rig: %s, Position: %s",
			hitPlayer and hitPlayer.Name or hitCharacter.Name,
			tostring(rigName),
			tostring(hitResult.Position)
		))
		
		Net:FireServer("ProjectileHit", {
			packet = hitPacket,
			weaponId = projectile.weaponId,
			rigName = rigName,
		})
	else
		warn("[WeaponProjectile] Cannot send hit - Net:", Net ~= nil, "Packet:", hitPacket ~= nil)
	end
	
	-- Play local impact effect
	self:_playImpactEffect(projectile, hitResult, true)
	
	local targetName = hitPlayer and hitPlayer.Name or hitCharacter.Name
	if CONFIG.DebugLogging then
		print(string.format(
			"[WeaponProjectile] Hit %s (%s) - Pierce: %d/%d",
			targetName,
			isHeadshot and "HEAD" or "Body",
			projectile.pierceCount,
			projectile.maxPierce + 1
		))
	end
	
	-- Check if should continue (pierce)
	if projectile.pierceCount <= projectile.maxPierce then
		-- Continue through target
		return true, nil
	else
		-- Max pierce reached, destroy
		return false, "HitTarget"
	end
end

--[[
	Handle hitting environment
]]
function WeaponProjectile:_handleEnvironmentHit(projectile, hitResult)
	-- Check for ricochet
	if projectile.bounceCount < projectile.maxBounce then
		-- Ricochet
		projectile.bounceCount = projectile.bounceCount + 1
		
		-- Calculate reflection
		local ricochetSpeedMult = projectile.projectileConfig.ricochetSpeedMult or 0.9
		projectile.velocity = projectile.physics:CalculateReflection(
			projectile.velocity,
			hitResult.Normal,
			ricochetSpeedMult
		)
		
		-- Play ricochet effect
		self:_playRicochetEffect(projectile, hitResult)
		
		if CONFIG.DebugLogging then
			print(string.format(
				"[WeaponProjectile] Ricochet %d/%d",
				projectile.bounceCount,
				projectile.maxBounce
			))
		end
		
		-- Continue
		return true, nil
	else
		-- No more bounces, check for AoE
		if projectile.projectileConfig.aoe then
			self:_handleAoEExplosion(projectile, hitResult)
		end
		
		-- Play impact effect
		self:_playImpactEffect(projectile, hitResult, false)
		
		-- Destroy
		return false, "HitEnvironment"
	end
end

--[[
	Handle AoE explosion
]]
function WeaponProjectile:_handleAoEExplosion(projectile, hitResult)
	local aoeConfig = projectile.projectileConfig.aoe
	local explosionCenter = hitResult.Position
	local radius = aoeConfig.radius or 15
	
	-- Find targets in radius
	local hitTargets = {}
	
	for _, player in pairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local distance = (hrp.Position - explosionCenter).Magnitude
				if distance <= radius then
					table.insert(hitTargets, {
						player = player,
						distance = distance,
						position = hrp.Position,
					})
				end
			end
		end
	end
	
	-- Send AoE hit for each target
	local impactTimestamp = projectile.fireTimestamp + projectile.elapsed
	
	for _, target in ipairs(hitTargets) do
		local hitPacket = ProjectilePacketUtils:CreateHitPacket({
			fireTimestamp = projectile.fireTimestamp,
			impactTimestamp = impactTimestamp,
			origin = projectile.position,
			hitPosition = explosionCenter,
			hitPlayer = target.player,
			hitCharacter = target.player.Character,
			isHeadshot = false, -- AoE doesn't headshot
			projectileId = projectile.id,
			pierceCount = 0,
			bounceCount = projectile.bounceCount,
		}, projectile.weaponId)
		
		if Net and hitPacket then
			Net:FireServer("ProjectileHit", {
				packet = hitPacket,
				weaponId = projectile.weaponId,
				isAoE = true,
				aoeDistance = target.distance,
				aoeRadius = radius,
			})
		end
	end
	
	-- Play explosion effect
	self:_playExplosionEffect(projectile, hitResult, aoeConfig)
	
	if CONFIG.DebugLogging then
		print(string.format(
			"[WeaponProjectile] AoE explosion hit %d targets",
			#hitTargets
		))
	end
end

-- =============================================================================
-- HIT DETECTION HELPERS
-- =============================================================================

--[[
	Create raycast params for projectile
]]
function WeaponProjectile:_createRaycastParams(projectile)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local filterList = {}
	
	-- Exclude local player
	if LocalPlayer and LocalPlayer.Character then
		table.insert(filterList, LocalPlayer.Character)
	end
	
	-- Exclude already-hit targets (for pierce)
	-- hitTargets stores both userId (number) for players and fullName (string) for rigs
	for targetId, targetData in pairs(projectile.hitTargets) do
		if type(targetId) == "number" then
			-- Player - look up by userId
			local player = Players:GetPlayerByUserId(targetId)
			if player and player.Character then
				table.insert(filterList, player.Character)
			end
		elseif type(targetData) == "table" and targetData.character then
			-- Rig - use stored character reference
			if targetData.character.Parent then
				table.insert(filterList, targetData.character)
			end
		end
	end

	local rigContainer = workspace:FindFirstChild("Rigs")
	if rigContainer then
		table.insert(filterList, rigContainer)
	end

	params.FilterDescendantsInstances = filterList

	return params
end

--[[
	Get target from hit instance (player or rig/dummy)
	
	@return Player?, Model?, boolean - Player (or nil for rigs), character/rig, isHeadshot
]]
function WeaponProjectile:_getPlayerFromHit(hitInstance)
	if not hitInstance then
		return nil, nil, false
	end
	
	-- Check for Collider model with OwnerUserId (player hitboxes)
	local current = hitInstance
	while current and current ~= workspace do
		if current.Name == "Collider" then
			local hitboxFolder = current:FindFirstChild("Hitbox")
			if not hitboxFolder or not hitInstance:IsDescendantOf(hitboxFolder) then
				return nil, nil, false
			end

			local standingFolder = hitboxFolder:FindFirstChild("Standing")
			local crouchingFolder = hitboxFolder:FindFirstChild("Crouching")
			if standingFolder and hitInstance:IsDescendantOf(standingFolder) then
				-- ok
			elseif crouchingFolder and hitInstance:IsDescendantOf(crouchingFolder) then
				-- ok
			else
				return nil, nil, false
			end

			local ownerUserId = current:GetAttribute("OwnerUserId")
			if ownerUserId then
				local player = Players:GetPlayerByUserId(ownerUserId)
				if player then
					local isHeadshot = hitInstance.Name == "Head"
					return player, player.Character, isHeadshot
				end
			end
			break
		end
		current = current.Parent
	end

	local rigContainer = workspace:FindFirstChild("Rigs")
	if rigContainer and hitInstance:IsDescendantOf(rigContainer) then
		return nil, nil, false
	end

	-- Check for humanoid in ancestors (players and rigs/dummies)
	local character = hitInstance:FindFirstAncestorOfClass("Model")
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local isHeadshot = hitInstance.Name == "Head"
			
			-- Check if it's a player
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				return nil, nil, false
			end
			
			-- It's a rig/dummy - return nil player but valid character
			return nil, character, isHeadshot
		end
	end
	
	return nil, nil, false
end

-- =============================================================================
-- FIRE ORIGIN & DIRECTION
-- =============================================================================

--[[
	Get fire origin and direction from weapon instance
]]
function WeaponProjectile:_getFireOriginAndDirection(weaponInstance)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	
	-- Origin: Camera position or muzzle position
	local origin = camera.CFrame.Position
	
	-- Try to get muzzle position from viewmodel
	local viewmodelController = weaponInstance.GetViewmodelController and weaponInstance.GetViewmodelController()
	if viewmodelController then
		local rig = viewmodelController:GetActiveRig()
		if rig and rig.Model then
			local muzzle = rig.Model:FindFirstChild("Muzzle", true)
			if muzzle then
				origin = muzzle.Position
			end
		end
	end
	
	-- Direction: Camera look vector
	local direction = camera.CFrame.LookVector
	
	return origin, direction
end

-- =============================================================================
-- SPREAD CALCULATION
-- =============================================================================

--[[
	Get current spread state from player/weapon
]]
function WeaponProjectile:_getSpreadState(weaponInstance)
	local state = {
		isMoving = false,
		isADS = false,
		inAir = false,
		isCrouching = false,
		isSliding = false,
		velocitySpread = 0,
		currentRecoil = 0,
	}
	
	-- Get character state
	if LocalPlayer and LocalPlayer.Character then
		local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local velocity = hrp.AssemblyLinearVelocity
			local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			
			state.isMoving = horizontalSpeed > 1
			state.velocitySpread = math.clamp(horizontalSpeed * 0.01, 0, 1)
		end
		
		local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			state.inAir = humanoid.FloorMaterial == Enum.Material.Air
		end
		
		state.isCrouching = LocalPlayer:GetAttribute("IsCrouching") == true
		state.isSliding = LocalPlayer:GetAttribute("IsSliding") == true
	end
	
	-- Get ADS state
	local cameraController = ServiceRegistry:GetController("CameraController")
	if cameraController and cameraController.IsADS then
		state.isADS = cameraController:IsADS()
	end
	
	return state
end

--[[
	Calculate spread angle
]]
function WeaponProjectile:_calculateSpread(projectileConfig, spreadState, crosshairConfig)
	local physics = ProjectilePhysics.new(projectileConfig)
	return physics:CalculateSpreadAngle(projectileConfig, spreadState, crosshairConfig)
end

-- =============================================================================
-- VISUALS
-- =============================================================================

--[[
	Spawn visual for projectile
]]
function WeaponProjectile:_spawnVisual(projectile)
	-- Get visual type
	local visualType = projectile.projectileConfig.visual or "Bullet"
	
	-- Create simple part for now (can be replaced with VFX module)
	local part = Instance.new("Part")
	part.Name = "Projectile_" .. projectile.id
	part.Size = Vector3.new(0.2, 0.2, 1)
	part.Shape = Enum.PartType.Block
	part.Material = Enum.Material.Neon
	part.Color = projectile.projectileConfig.tracerColor or CONFIG.DefaultTracerColor
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	
	-- Position and orient
	part.CFrame = CFrame.lookAt(projectile.position, projectile.position + projectile.velocity)
	
	-- Add trail
	if projectile.projectileConfig.trailEnabled ~= false then
		local attachment0 = Instance.new("Attachment")
		attachment0.Position = Vector3.new(0, 0, -0.5)
		attachment0.Parent = part
		
		local attachment1 = Instance.new("Attachment")
		attachment1.Position = Vector3.new(0, 0, 0.5)
		attachment1.Parent = part
		
		local trail = Instance.new("Trail")
		trail.Attachment0 = attachment0
		trail.Attachment1 = attachment1
		trail.Color = ColorSequence.new(part.Color)
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Lifetime = 0.2
		trail.MinLength = 0.1
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Parent = part
	end
	
	part.Parent = workspace
	
	projectile.visual = part
end

--[[
	Update visual position
]]
function WeaponProjectile:_updateVisual(projectile)
	if not projectile.visual or not projectile.visual.Parent then
		return
	end
	
	-- Update CFrame to face velocity direction
	projectile.visual.CFrame = CFrame.lookAt(
		projectile.position,
		projectile.position + projectile.velocity.Unit
	)
end

--[[
	Destroy visual
]]
function WeaponProjectile:_destroyVisual(projectile)
	if projectile.visual and projectile.visual.Parent then
		projectile.visual:Destroy()
	end
	projectile.visual = nil
end

-- =============================================================================
-- EFFECTS
-- =============================================================================

--[[
	Play impact effect
]]
function WeaponProjectile:_playImpactEffect(projectile, hitResult, isTarget)
	-- Debug visualization - red for targets, yellow for environment
	if CONFIG.DebugVisualization then
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.4, 0.4, 0.4)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
		part.Color = isTarget and Color3.new(1, 0, 0) or Color3.new(1, 1, 0)
		part.Position = hitResult.Position
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = workspace
		
		-- Stay visible for 2 seconds then fade
		task.delay(2, function()
			if part and part.Parent then
				part:Destroy()
			end
		end)
	end
end

--[[
	Play ricochet effect
]]
function WeaponProjectile:_playRicochetEffect(projectile, hitResult)
	-- TODO: Integrate with VFX system
	if CONFIG.DebugVisualization then
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.3, 0.3, 0.3)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
		part.Color = Color3.new(0, 1, 1)
		part.Position = hitResult.Position
		part.Anchored = true
		part.CanCollide = false
		part.Parent = workspace
		
		task.delay(0.5, function()
			part:Destroy()
		end)
	end
end

--[[
	Play explosion effect
]]
function WeaponProjectile:_playExplosionEffect(projectile, hitResult, aoeConfig)
	-- TODO: Integrate with VFX system
	if CONFIG.DebugVisualization then
		local part = Instance.new("Part")
		part.Size = Vector3.new(aoeConfig.radius * 2, aoeConfig.radius * 2, aoeConfig.radius * 2)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
		part.Color = Color3.new(1, 0.5, 0)
		part.Transparency = 0.5
		part.Position = hitResult.Position
		part.Anchored = true
		part.CanCollide = false
		part.Parent = workspace
		
		task.delay(0.3, function()
			part:Destroy()
		end)
	end
end

-- =============================================================================
-- PROJECTILE LIFECYCLE
-- =============================================================================

--[[
	Destroy a projectile
]]
function WeaponProjectile:_destroyProjectile(projectileId, reason)
	local projectile = ActiveProjectiles[projectileId]
	if not projectile then
		return
	end
	
	-- Destroy visual
	self:_destroyVisual(projectile)
	
	-- Remove from active
	ActiveProjectiles[projectileId] = nil
	
	if CONFIG.DebugLogging then
		print(string.format(
			"[WeaponProjectile] Destroyed projectile %d: %s",
			projectileId,
			reason or "Unknown"
		))
	end
end

-- =============================================================================
-- NETWORK HANDLERS
-- =============================================================================

--[[
	Handle hit confirmation from server
]]
function WeaponProjectile:_onHitConfirmed(data)
	-- Play confirmed hit effect
	if CONFIG.DebugLogging then
		print("[WeaponProjectile] Hit confirmed by server")
	end
end

--[[
	Handle projectile destroyed by server
]]
function WeaponProjectile:_onProjectileDestroyed(data)
	local parsed = ProjectilePacketUtils:ParseDestroyedPacket(data.packet)
	if not parsed then
		return
	end
	
	self:_destroyProjectile(parsed.projectileId, parsed.destroyReasonName)
end

--[[
	Handle projectile from other player
]]
function WeaponProjectile:_onProjectileReplicate(data)
	local parsed = ProjectilePacketUtils:ParseReplicatePacket(data.packet)
	if not parsed then
		return
	end
	
	-- Don't spawn our own projectiles
	if parsed.shooterUserId == LocalPlayer.UserId then
		return
	end
	
	-- Get weapon config
	local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
	local weaponConfig = LoadoutConfig.getWeapon(parsed.weaponName)
	
	if not weaponConfig or not weaponConfig.projectile then
		return
	end
	
	local projectileConfig = weaponConfig.projectile
	
	-- Create remote projectile (visual only, no hit detection)
	local projectileData = {
		id = parsed.projectileId,
		weaponId = parsed.weaponName,
		weaponConfig = weaponConfig,
		projectileConfig = projectileConfig,
		
		position = parsed.origin,
		velocity = parsed.direction * parsed.speed,
		physics = ProjectilePhysics.new(projectileConfig),
		
		fireTimestamp = workspace:GetServerTimeNow(),
		lifetime = projectileConfig.lifetime or 5,
		elapsed = 0,
		
		isRemote = true, -- Flag as remote (no hit detection)
		hitTargets = {},
		pierceCount = 0,
		maxPierce = 0,
		bounceCount = 0,
		maxBounce = projectileConfig.ricochet or 0,
		
		chargePercent = parsed.chargePercent,
	}
	
	ActiveProjectiles[parsed.projectileId] = projectileData
	self:_spawnVisual(projectileData)
	
	if CONFIG.DebugLogging then
		print(string.format(
			"[WeaponProjectile] Replicated projectile from %s",
			parsed.shooter and parsed.shooter.Name or "Unknown"
		))
	end
end

-- =============================================================================
-- CLEANUP
-- =============================================================================

function WeaponProjectile:Destroy()
	if SimulationConnection then
		SimulationConnection:Disconnect()
		SimulationConnection = nil
	end
	
	-- Destroy all projectiles
	for id, _ in pairs(ActiveProjectiles) do
		self:_destroyProjectile(id, "Shutdown")
	end
end

return WeaponProjectile
