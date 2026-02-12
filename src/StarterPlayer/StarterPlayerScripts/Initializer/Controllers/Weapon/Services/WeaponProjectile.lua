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
local TrainingRangeShot = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("TrainingRangeShot"))
local Tracers = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Tracers"))

local LocalPlayer = Players.LocalPlayer

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

local CONFIG = {
	-- Debug (set to true to see hit markers and logs)
	DebugVisualization = true,
	DebugLogging = false,

	-- Simulation
	PhysicsTickRate = 1 / 60, -- 60 Hz physics
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
	-- Prevent double-initialization (now initialized early in WeaponController:Init)
	if self._initialized then
		return
	end
	self._initialized = true
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
		finalDirections =
			physics:ApplyPatternSpread(direction, projectileConfig.spreadPattern, projectileConfig.spreadRandomization)
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
			startPosition = origin, -- Store original fire position for flight time calculation
			initialSpeed = speed, -- Store initial speed for flight time calculation

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

		-- Get gun model for muzzle effects (rig is a table with .Model property)
		local rig = weaponInstance.GetRig and weaponInstance.GetRig()
		local gunModel = rig and rig.Model or nil

		-- Spawn visual with gun model (always play muzzle for single shot)
		self:_spawnVisual(projectileData, gunModel, true)

		table.insert(projectileIds, projectileId)

		if CONFIG.DebugLogging then
			print(
				string.format(
					"[WeaponProjectile] Fired %s (ID: %d) at %.0f studs/sec",
					weaponInstance.WeaponId,
					projectileId,
					speed
				)
			)
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
			startPosition = origin, -- Store original fire position for flight time calculation
			initialSpeed = speed, -- Store initial speed for flight time calculation

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

		-- Get gun model for muzzle effects
		local rig = weaponInstance.GetRig and weaponInstance.GetRig()
		local gunModel = rig and rig.Model or nil

		-- Spawn visual with gun model (only play muzzle FX on first pellet)
		local playMuzzle = (i == 1)
		self:_spawnVisual(projectileData, gunModel, playMuzzle)

		table.insert(projectileIds, projectileId)
	end

	if CONFIG.DebugLogging then
		print(
			string.format(
				"[WeaponProjectile] Fired %d pellets (%s) at %.0f studs/sec",
				#projectileIds,
				weaponInstance.WeaponId,
				speed
			)
		)
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
	local newPosition, newVelocity, hitResult =
		projectile.physics:Step(projectile.position, projectile.velocity, dt, raycastParams)

	-- Handle collision
	if hitResult then
		if CONFIG.DebugLogging then
			print(
				string.format(
					"[WeaponProjectile] Collision detected: Part=%s, Parent=%s, FullName=%s",
					hitResult.Instance.Name,
					hitResult.Instance.Parent and hitResult.Instance.Parent.Name or "nil",
					hitResult.Instance:GetFullName()
				)
			)
		end

		local shouldContinue, reason = self:_handleCollision(projectile, hitResult)

		if not shouldContinue then
			return true, reason
		end

		-- Nudge position past the hit point so the next frame's raycast
		-- doesn't re-detect the same surface (pierce, destroyed wall, etc.)
		projectile.position = hitResult.Position + projectile.velocity.Unit * 0.1
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

	-- Pass through destroyed breakable walls (invisible remnants from VoxelDestruction)
	-- Also pass through loose debris (flying rubble)
	if hitInstance:GetAttribute("__Breakable") == false
		or hitInstance:GetAttribute("__BreakableClient") == false
		or hitInstance:HasTag("Debris")
	then
		return true, nil
	end

	-- Check if it's a player or rig hitbox
	local hitPlayer, hitCharacter, isHeadshot = self:_getPlayerFromHit(hitInstance)

	if hitCharacter then
		-- Skip hit detection for remote projectiles (visual only, no hit registration)
		if projectile.isRemote then
			return true, nil
		end

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
	-- Normalize nested rig hits to canonical character model (e.g. Dummy/Rig -> Dummy)
	if hitCharacter and hitCharacter:IsA("Model") then
		local parentModel = hitCharacter.Parent
		if
			hitCharacter.Name == "Rig"
			and parentModel
			and parentModel:IsA("Model")
			and parentModel:FindFirstChild("Root")
			and parentModel:FindFirstChild("Collider")
		then
			hitCharacter = parentModel
		end
	end

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

	-- Calculate physics-based flight time (not game loop elapsed time)
	-- This ensures server validation passes since it uses the same physics calculation
	local actualFlightTime =
		projectile.physics:CalculateFlightTime(projectile.startPosition, hitResult.Position, projectile.initialSpeed)
	local impactTimestamp = projectile.fireTimestamp + actualFlightTime

	-- Create hit packet
	local hitPacket = ProjectilePacketUtils:CreateHitPacket({
		fireTimestamp = projectile.fireTimestamp,
		impactTimestamp = impactTimestamp,
		origin = projectile.startPosition, -- Original fire position for server validation
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

		if CONFIG.DebugLogging then
			print(
				string.format(
					"[WeaponProjectile] Sending hit to server - Target: %s, Rig: %s, Position: %s",
					hitPlayer and hitPlayer.Name or hitCharacter.Name,
					tostring(rigName),
					tostring(hitResult.Position)
				)
			)
		end

		Net:FireServer("ProjectileHit", {
			packet = hitPacket,
			weaponId = projectile.weaponId,
			rigName = rigName,
		})
	else
		warn("[WeaponProjectile] Cannot send hit - Net:", Net ~= nil, "Packet:", hitPacket ~= nil)
	end

	-- Play local impact effect (pass hitCharacter for tracer HitPlayer)
	self:_playImpactEffect(projectile, hitResult, true, hitCharacter)

	local targetName = hitPlayer and hitPlayer.Name or hitCharacter.Name
	if CONFIG.DebugLogging then
		print(
			string.format(
				"[WeaponProjectile] Hit %s (%s) - Pierce: %d/%d",
				targetName,
				isHeadshot and "HEAD" or "Body",
				projectile.pierceCount,
				projectile.maxPierce + 1
			)
		)
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
	if TrainingRangeShot then
		TrainingRangeShot:TryHandleHit(hitResult.Instance, hitResult.Position)
	end

	-- Check for ricochet
	if projectile.bounceCount < projectile.maxBounce then
		-- Ricochet
		projectile.bounceCount = projectile.bounceCount + 1

		-- Calculate reflection
		local ricochetSpeedMult = projectile.projectileConfig.ricochetSpeedMult or 0.9
		projectile.velocity =
			projectile.physics:CalculateReflection(projectile.velocity, hitResult.Normal, ricochetSpeedMult)

		-- Play ricochet effect
		self:_playRicochetEffect(projectile, hitResult)

		if CONFIG.DebugLogging then
			print(string.format("[WeaponProjectile] Ricochet %d/%d", projectile.bounceCount, projectile.maxBounce))
		end

		-- Continue
		return true, nil
	else
		-- No more bounces, check for AoE
		if projectile.projectileConfig.aoe then
			self:_handleAoEExplosion(projectile, hitResult)
		end

		-- Play impact effect (nil hitCharacter for world hit)
		self:_playImpactEffect(projectile, hitResult, false, nil)

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
	-- Calculate physics-based flight time (not game loop elapsed time)
	local actualFlightTime =
		projectile.physics:CalculateFlightTime(projectile.startPosition, explosionCenter, projectile.initialSpeed)
	local impactTimestamp = projectile.fireTimestamp + actualFlightTime

	for _, target in ipairs(hitTargets) do
		local hitPacket = ProjectilePacketUtils:CreateHitPacket({
			fireTimestamp = projectile.fireTimestamp,
			impactTimestamp = impactTimestamp,
			origin = projectile.startPosition, -- Original fire position for server validation
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
		print(string.format("[WeaponProjectile] AoE explosion hit %d targets", #hitTargets))
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
	for targetId, targetData in pairs(projectile.hitTargets) do
		if type(targetId) == "number" then
			local player = Players:GetPlayerByUserId(targetId)
			if player and player.Character then
				table.insert(filterList, player.Character)
			end
		elseif type(targetData) == "table" and targetData.character then
			if targetData.character.Parent then
				table.insert(filterList, targetData.character)
			end
		end
	end

	local rigContainer = workspace:FindFirstChild("Rigs")
	if rigContainer then
		table.insert(filterList, rigContainer)
	end

	-- Exclude cosmetic Rig sub-models inside all characters so projectiles
	-- only collide with Collider/Hitbox parts, not R6 visual rig parts.
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			local rig = player.Character:FindFirstChild("Rig")
			if rig then
				table.insert(filterList, rig)
			end
		end
	end

	-- Exclude Rig sub-models inside dummy characters
	local dummiesFolder = workspace:FindFirstChild("Dummies")
	if dummiesFolder then
		for _, dummy in ipairs(dummiesFolder:GetChildren()) do
			if dummy:IsA("Model") then
				local rig = dummy:FindFirstChild("Rig")
				if rig then
					table.insert(filterList, rig)
				end
			end
		end
	end

	local effectsFolder = workspace:FindFirstChild("Effects")
	if effectsFolder then
		table.insert(filterList, effectsFolder)
	end

	local voxelCache = workspace:FindFirstChild("VoxelCache")
	if voxelCache then
		table.insert(filterList, voxelCache)
	end

	-- Exclude voxel destruction record clones (debris/pieces use CanQuery=false)
	local destructionFolder = workspace:FindFirstChild("__Destruction")
	if destructionFolder then
		table.insert(filterList, destructionFolder)
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

	local rigContainer = workspace:FindFirstChild("Rigs")
	if rigContainer and hitInstance:IsDescendantOf(rigContainer) then
		return nil, nil, false
	end

	local isHeadshot = hitInstance.Name == "Head"
		or hitInstance.Name == "CrouchHead"
		or hitInstance.Name == "HitboxHead"

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
			elseif crouchingFolder and hitInstance:IsDescendantOf(crouchingFolder) then
			else
				return nil, nil, false
			end

			local ownerUserId = current:GetAttribute("OwnerUserId")
			if ownerUserId then
				local player = Players:GetPlayerByUserId(ownerUserId)
				if player then
					return player, player.Character, isHeadshot
				end
			end

			local characterModel = current.Parent
			if characterModel and characterModel:IsA("Model") then
				local humanoid = characterModel:FindFirstChildWhichIsA("Humanoid", true)
				if humanoid then
					return nil, characterModel, isHeadshot
				end
			end

			return nil, nil, false
		end

		if current.Name == "Rig" and current:IsA("Model") then
			return nil, nil, false
		end

		current = current.Parent
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
		isSprinting = false,
		velocitySpread = 0,
		currentRecoil = 0,
	}

	-- Get character state from CharacterController (more reliable)
	local characterController = ServiceRegistry:GetController("CharacterController")
	
	if characterController and characterController.PrimaryPart then
		local velocity = characterController.PrimaryPart.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		state.isMoving = horizontalSpeed > 1
		state.velocitySpread = math.clamp(horizontalSpeed * 0.01, 0, 1)
		
		-- Use CharacterController's grounded state
		state.inAir = not characterController.IsGrounded
	elseif LocalPlayer and LocalPlayer.Character then
		-- Fallback to character
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
	end

	-- Get movement state from MovementStateManager (most reliable for crouch/slide/sprint)
	local MovementStateManager = nil
	pcall(function()
		MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
	end)
	
	if MovementStateManager then
		state.isCrouching = MovementStateManager:IsCrouching()
		state.isSliding = MovementStateManager:IsSliding()
		state.isSprinting = MovementStateManager:IsSprinting()
	else
		-- Fallback to player attributes
		if LocalPlayer then
			state.isCrouching = LocalPlayer:GetAttribute("IsCrouching") == true
			state.isSliding = LocalPlayer:GetAttribute("IsSliding") == true
		end
	end

	-- Get ADS state from WeaponController
	local weaponController = ServiceRegistry:GetController("WeaponController")
	if weaponController then
		if type(weaponController.IsADS) == "function" then
			state.isADS = weaponController:IsADS()
		elseif weaponController._isADS ~= nil then
			state.isADS = weaponController._isADS == true
		end
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
-- VISUALS (Using Tracer System)
-- =============================================================================

--[[
	Spawn visual for projectile using Tracer system
	@param projectile table - Projectile data
	@param gunModel Model? - The weapon model for muzzle effects
	@param playMuzzle boolean? - Whether to play muzzle FX (default true)
]]
function WeaponProjectile:_spawnVisual(projectile, gunModel, playMuzzle)
	-- Get tracer ID from weapon config (or use default)
	local tracerId = projectile.projectileConfig.tracerId or projectile.weaponConfig.tracerId

	-- Resolve tracer (weapon config > player cosmetic > default)
	local resolvedTracerId = Tracers:Resolve(tracerId, nil)

	-- Fire tracer - get attachment handle (playMuzzle controls muzzle FX)
	local handle = Tracers:Fire(resolvedTracerId, projectile.position, gunModel, playMuzzle)
	if not handle then
		warn("[WeaponProjectile] Failed to get tracer handle")
		return
	end

	-- Store the tracer handle
	projectile.tracerHandle = handle

	-- Update initial position
	handle.attachment.WorldPosition = projectile.position
end

--[[
	Update visual position using Tracer attachment
]]
function WeaponProjectile:_updateVisual(projectile)
	if not projectile.tracerHandle or not projectile.tracerHandle.attachment then
		return
	end

	-- Update attachment WorldPosition to match projectile
	projectile.tracerHandle.attachment.WorldPosition = projectile.position
end

--[[
	Destroy visual - cleanup tracer handle
]]
function WeaponProjectile:_destroyVisual(projectile)
	if projectile.tracerHandle then
		if projectile.tracerHandle.cleanup then
			projectile.tracerHandle.cleanup()
		end
		projectile.tracerHandle = nil
	end
end

-- =============================================================================
-- EFFECTS (Using Tracer System)
-- =============================================================================

--[[
	Play impact effect using Tracer system
	@param projectile table - Projectile data
	@param hitResult RaycastResult - Hit result
	@param isTarget boolean - True if hit a character/dummy
	@param hitCharacter Model? - The character that was hit (if any)
]]
function WeaponProjectile:_playImpactEffect(projectile, hitResult, isTarget, hitCharacter)
	-- Use tracer system for impact effects
	if projectile.tracerHandle then
		if isTarget and hitCharacter then
			-- Hit player/dummy - call tracer HitPlayer
			Tracers:HitPlayer(projectile.tracerHandle, hitResult.Position, hitResult.Instance, hitCharacter)
		else
			-- Hit world - call tracer HitWorld
			Tracers:HitWorld(projectile.tracerHandle, hitResult.Position, hitResult.Normal, hitResult.Instance)
		end
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
		print(string.format("[WeaponProjectile] Destroyed projectile %d: %s", projectileId, reason or "Unknown"))
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
	-- Remote projectiles don't have access to gun model, don't play muzzle (already played on owner's client)
	self:_spawnVisual(projectileData, nil, false)

	if CONFIG.DebugLogging then
		print(
			string.format(
				"[WeaponProjectile] Replicated projectile from %s",
				parsed.shooter and parsed.shooter.Name or "Unknown"
			)
		)
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
