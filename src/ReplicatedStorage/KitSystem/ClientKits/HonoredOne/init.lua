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
local ContentProvider = game:GetService("ContentProvider")
local CollectionService = game:GetService("CollectionService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local Hitbox = require(Locations.Shared.Util:WaitForChild("Hitbox"))
local ProjectilePhysics = require(Locations.Shared.Util:WaitForChild("ProjectilePhysics"))
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))
local Dialogue = require(ReplicatedStorage:WaitForChild("Dialogue"))

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
	START_DISTANCE = 17.5,         -- Default start distance in front of player
	RAYCAST_DISTANCE = 17.5,       -- Raycast forward to find surface

	-- Pull + Orbit settings (creates swirling effect)
	PULL_MIN_STRENGTH = 25,      -- Pull strength when very close to center
	PULL_MAX_STRENGTH = 50,      -- Pull strength when at edge of hitbox
	ORBIT_STRENGTH = 30,         -- Tangential velocity for orbit effect
	PULL_UPWARD = 20,            -- Slight upward to keep them floating

	-- Explosion settings
	EXPLOSION_UPWARD = 90,      -- Upward velocity on explosion
	EXPLOSION_OUTWARD = 80,     -- Outward velocity on explosion

	-- Destruction
	DESTRUCTION_INTERVAL = 0.3,  -- Seconds between each destruction tick
	DESTRUCTION_RADIUS = 8,      -- Radius of each destruction explosion
	DESTRUCTION_VOXEL_SIZE = 2,  -- Voxel size for destruction

	-- Debris orbit (swirling rubble effect)
	DEBRIS_CAPTURE_RADIUS = 20,  -- Capture debris within this radius
	DEBRIS_ORBIT_SPEED_MIN = 1.5, -- Min orbit speed (radians/sec)
	DEBRIS_ORBIT_SPEED_MAX = 3.5, -- Max orbit speed (radians/sec)
	DEBRIS_SPIRAL_RATE = 1.5,    -- How fast debris spirals inward
	DEBRIS_ORBIT_RADIUS_MIN = 2, -- Inner orbit limit
	DEBRIS_MAX_COUNT = 55,       -- Cap orbiting pieces for perf
	DEBRIS_LIFETIME_OVERRIDE = 10, -- Keep debris alive during orbit

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
	
	-- Recoil (pushes player back when firing)
	RECOIL_STRENGTH = 80,        -- How hard the player gets pushed back on fire
	
	-- Hold limit
	MAX_HOLD_TIME = 10,          -- Max seconds player can hold before auto-fire

	-- Destruction (pierce through breakable walls)
	DESTRUCTION_INTERVAL = 0.15,
	DESTRUCTION_RADIUS = 10,
	DESTRUCTION_VOXEL_SIZE = 2,
}

-- ProjectilePhysics config for Red (straight line, no gravity)
local RED_PHYSICS_CONFIG = {
	speed = RED_CONFIG.PROJECTILE_SPEED,
	gravity = 0,       -- Flies straight
	drag = 0,          -- No slowdown
	lifetime = RED_CONFIG.MAX_RANGE / RED_CONFIG.PROJECTILE_SPEED + 0.2,  -- ~1 second total
}
local PROJECTILE_REPLICATION_INTERVAL = 1 / 18


--------------------------------------------------------------------------------
-- Sound Configuration & Preloading
--------------------------------------------------------------------------------

local SOUND_CONFIG = {
	-- Red ability sounds
	start = { id = "rbxassetid://103690871211615", volume = 1 },
	shoot = { id = "rbxassetid://111984395150553", volume = 1 },
	explosion = { id = "rbxassetid://109996936076104", volume = 1.5 },
	-- Blue ability sounds
	blueStart = { id = "rbxassetid://128253195405132", volume = 1 },
	blueIdle = { id = "rbxassetid://100714867966748", volume = 1, looped = true },
}

-- Create and preload all sounds
local preloadItems = {}
for name, config in pairs(SOUND_CONFIG) do
	if not script:FindFirstChild(name) then
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = config.id
		sound.Volume = config.volume
		sound.Looped = config.looped or false
		sound.Parent = script
	end
	table.insert(preloadItems, script:FindFirstChild(name))
end

-- Preload synchronously to prevent delay on first use
ContentProvider:PreloadAsync(preloadItems)

--------------------------------------------------------------------------------
-- Sound Helpers (same pattern as Aki)
--------------------------------------------------------------------------------

local activeSounds = {}
local chargeSound = nil

local function playHitVoice()
	-- Use the Dialogue system to play the hit voice line (handles sound + subtitles)
	Dialogue.generate("HonoredOne", "Ability", "Hit", { override = true })
end

local function playStartSound(viewmodelRig: any): Sound?
	-- Play the "start" sound on the viewmodel root part
	local startSound = script:FindFirstChild("start")
	if not startSound then return nil end
	
	local rootPart = viewmodelRig and viewmodelRig.Model and viewmodelRig.Model:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end
	
	local sound = startSound:Clone()
	sound.Parent = rootPart
	sound:Play()
	
	table.insert(activeSounds, sound)
	chargeSound = sound
	
	sound.Ended:Once(function()
		local idx = table.find(activeSounds, sound)
		if idx then table.remove(activeSounds, idx) end
		sound:Destroy()
	end)
	
	return sound
end

local function playShootSound(parent: Instance?): Sound?
	local shootSound = script:FindFirstChild("shoot")
	if not shootSound then return nil end
	
	local sound = shootSound:Clone()
	sound.Parent = parent or Workspace
	sound:Play()
	
	table.insert(activeSounds, sound)
	
	sound.Ended:Once(function()
		local idx = table.find(activeSounds, sound)
		if idx then table.remove(activeSounds, idx) end
		sound:Destroy()
	end)
	
	return sound
end

local function playExplosionSound(position: Vector3?): Sound?
	local explosionSound = script:FindFirstChild("explosion")
	if not explosionSound then return nil end

	local sound = explosionSound:Clone()

	-- If position provided, create an anchored part at that location for 3D audio
	if position then
		local soundAnchor = Instance.new("Part")
		soundAnchor.Name = "ExplosionSoundAnchor"
		soundAnchor.Size = Vector3.new(1, 1, 1)
		soundAnchor.CFrame = CFrame.new(position)
		soundAnchor.Anchored = true
		soundAnchor.CanCollide = false
		soundAnchor.CanQuery = false
		soundAnchor.CanTouch = false
		soundAnchor.Transparency = 1
		soundAnchor.Parent = Workspace
		sound.Parent = soundAnchor

		sound.Ended:Once(function()
			local idx = table.find(activeSounds, sound)
			if idx then table.remove(activeSounds, idx) end
			soundAnchor:Destroy()
		end)
	else
		sound.Parent = Workspace
		sound.Ended:Once(function()
			local idx = table.find(activeSounds, sound)
			if idx then table.remove(activeSounds, idx) end
			sound:Destroy()
		end)
	end

	sound:Play()
	table.insert(activeSounds, sound)

	return sound
end

local function stopChargeSound()
	if chargeSound and chargeSound.Parent then
		chargeSound:Stop()
		chargeSound:Destroy()
		local idx = table.find(activeSounds, chargeSound)
		if idx then table.remove(activeSounds, idx) end
	end
	chargeSound = nil
end

local function reparentChargeSoundToProjectile(projectilePart: Instance)
	if chargeSound and chargeSound.Parent then
		chargeSound.Parent = projectilePart
	end
end

local function cleanupSounds()
	for _, sound in ipairs(activeSounds) do
		if sound and sound.Parent then
			sound:Destroy()
		end
	end
	activeSounds = {}
	chargeSound = nil
end

-- Blue ability sounds
local blueIdleSound = nil

local function playBlueStartSound(parent: Instance?): Sound?
	local blueStartSound = script:FindFirstChild("blueStart")
	if not blueStartSound then return nil end
	
	local sound = blueStartSound:Clone()
	sound.Parent = parent or Workspace
	sound:Play()
	
	table.insert(activeSounds, sound)
	
	sound.Ended:Once(function()
		local idx = table.find(activeSounds, sound)
		if idx then table.remove(activeSounds, idx) end
		sound:Destroy()
	end)
	
	return sound
end

--local function playBlueIdleSound(hitboxPart: Instance): Sound?
--	local blueIdleSoundTemplate = script:FindFirstChild("blueIdle")
--	if not blueIdleSoundTemplate then return nil end
	
--	local sound = blueIdleSoundTemplate:Clone()
--	sound.Parent = hitboxPart
--	sound.Looped = true
--	sound:Play()
	
	
	
--	table.insert(activeSounds, sound)
--	blueIdleSound = sound
	
--	return sound
--end

local function fadeOutBlueIdleSound(fadeTime: number?)
	--local sound = blueIdleSound
	--if not sound or not sound.Parent then
	--	blueIdleSound = nil
	--	return
	--end
	
	--fadeTime = fadeTime or 0.5
	--local startVolume = sound.Volume
	--local startTime = os.clock()
	
	---- Fade out over time
	--task.spawn(function()
	--	while sound and sound.Parent do
	--		local elapsed = os.clock() - startTime
	--		local progress = math.min(1, elapsed / fadeTime)
	--		sound.Volume = startVolume * (1 - progress)
			
	--		if progress >= 1 then
	--			break
	--		end
	--		task.wait()
	--	end
		
	--	-- Clean up
	--	if sound and sound.Parent then
	--		sound:Stop()
	--		sound:Destroy()
	--	end
		
	--	local idx = table.find(activeSounds, sound)
	--	if idx then table.remove(activeSounds, idx) end
	--	blueIdleSound = nil
	--end)
end

--------------------------------------------------------------------------------
-- Debug Helpers
--------------------------------------------------------------------------------

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
	part.Transparency = 1
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

local function clearRedStateAttributes()
	LocalPlayer:SetAttribute(`red_charge`, nil)
	LocalPlayer:SetAttribute(`red_projectile_activeCFR`, nil)
	LocalPlayer:SetAttribute(`red_explosion_pivot`, nil)
end

local function setExternalMoveMult(multiplier)
	local value = tonumber(multiplier) or 1
	LocalPlayer:SetAttribute("ExternalMoveMult", math.clamp(value, 0.1, 1))
end

local function clearExternalMoveMult()
	LocalPlayer:SetAttribute("ExternalMoveMult", 1)
end

local function clearRedCrouchGate()
	LocalPlayer:SetAttribute("ForceUncrouch", nil)
	LocalPlayer:SetAttribute("BlockCrouchWhileAbility", nil)
end

local function setRedCrouchGate()
	LocalPlayer:SetAttribute("ForceUncrouch", true)
	LocalPlayer:SetAttribute("BlockCrouchWhileAbility", true)
end

local function getBlueDurabilitySnapshot(character: Model?, humanoid: Humanoid?): number?
	local health = LocalPlayer:GetAttribute("Health")
	local shield = LocalPlayer:GetAttribute("Shield")
	local overshield = LocalPlayer:GetAttribute("Overshield")

	if type(health) == "number" and type(shield) == "number" and type(overshield) == "number" then
		return health + shield + overshield
	end

	if type(health) == "number" then
		return health
	end

	local resolvedHumanoid = humanoid
	if not resolvedHumanoid and character then
		resolvedHumanoid = character:FindFirstChildWhichIsA("Humanoid")
	end
	if resolvedHumanoid then
		return resolvedHumanoid.Health
	end

	return nil
end

local function endBlue(state)
	if not state then return end
	state.hitboxActive = false
	LocalPlayer:SetAttribute("cleanupblueFX", os.clock())
	clearExternalMoveMult()

	if state.hitboxViz and state.hitboxViz.Parent then
		state.hitboxViz:Destroy()
	end
	state.hitboxViz = nil
end

local function endRed(state, preserveExplosionPivot)
	if not state then return end
	state.projectileActive = false
	clearExternalMoveMult()
	clearRedCrouchGate()

	if state.projectileViz and state.projectileViz.Parent then
		state.projectileViz:Destroy()
	end
	state.projectileViz = nil
	LocalPlayer:SetAttribute(`red_charge`, nil)
	LocalPlayer:SetAttribute(`red_projectile_activeCFR`, nil)
	if not preserveExplosionPivot then
		LocalPlayer:SetAttribute(`red_explosion_pivot`, nil)
	end
end

--------------------------------------------------------------------------------
-- Blue Ability - Moving Vacuum Hitbox (Pull)
-- Called from animation "open" event
--------------------------------------------------------------------------------

local function runBlueHitbox(state)
	local abilityRequest = state.abilityRequest
	local character = state.character
	
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
	else
		-- No surface - start 10 studs in front
		startPosition = defaultStart
	end
	
	local elapsed = 0
	local pullCount = 0
	local lastDestructionTime = 0 -- Throttle for continuous destruction
	
	-- CAPTURED TARGETS - once caught, they stay caught until ability ends
	local capturedTargets = {}
	
	-- CAPTURED DEBRIS - voxel rubble that orbits the sphere
	local capturedDebris = {}
	local capturedDebrisCount = 0
	
	-- Current hitbox position (will lerp smoothly)
	local currentPosition = startPosition
	local targetPosition = startPosition
	
	-- Create the visual hitbox sphere
	local hitboxViz = createDebugSphere(startPosition, BLUE_CONFIG.HITBOX_RADIUS, Color3.fromRGB(0, 100, 255))
	hitboxViz.Name = "BlueHitbox_Active"
	hitboxViz.Parent = getEffectsFolder()
	
	-- Play Blue start sound
	playBlueStartSound(hitboxViz)
	
	-- Play Blue idle sound (looped, on the hitbox)
	--playBlueIdleSound(hitboxViz)
	
	VFXRep:Fire("Me", { Module = "HonoredOne", Function = "User" }, {
		Character = character,
		forceAction = "blue_open",
		projectile = hitboxViz,
		lifetime = BLUE_CONFIG.LIFETIME,
	})
	abilityRequest.Send({
		action = "relayUserVfx",
		forceAction = "blue_open",
		lifetime = BLUE_CONFIG.LIFETIME,
		allowMultiple = true,
	})

	task.delay(.3, function()
		if state.cancelled then
			return
		end
		VFXRep:Fire("Me", { Module = "HonoredOne", Function = "User" }, {
			Character = character,
			forceAction = "blue_loop",
			projectile = hitboxViz,
			lifetime = BLUE_CONFIG.LIFETIME,
		})
		abilityRequest.Send({
			action = "relayUserVfx",
			forceAction = "blue_loop",
			lifetime = BLUE_CONFIG.LIFETIME,
			allowMultiple = true,
		})
	end)
	
	-- Store for cleanup on cancel
	state.hitboxViz = hitboxViz
	state.hitboxActive = true
	
	-- Main ability loop (runs for full LIFETIME, independent of animation)
	while elapsed < BLUE_CONFIG.LIFETIME do
		-- Only stop if hard cancelled (interrupt/weapon switch)
		if state.cancelled then
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
		local bluePivot = CFrame.new(currentPosition)
		if hitboxViz and hitboxViz.Parent then
			hitboxViz.CFrame = bluePivot
		end
		LocalPlayer:SetAttribute(`blue_projectile_activeCFR`, bluePivot)

		local now = os.clock()
		if (state.lastBlueReplicationAt or 0) + PROJECTILE_REPLICATION_INTERVAL <= now then
			state.lastBlueReplicationAt = now
			abilityRequest.Send({
				action = "blueProjectileUpdate",
				pivot = bluePivot,
				position = { X = currentPosition.X, Y = currentPosition.Y, Z = currentPosition.Z },
				radius = BLUE_CONFIG.HITBOX_RADIUS,
				allowMultiple = true,
			})
		end
		
		-- Continuous terrain destruction along the path
		if elapsed - lastDestructionTime >= BLUE_CONFIG.DESTRUCTION_INTERVAL then
			lastDestructionTime = elapsed
			-- Send to server for replication to all clients
			abilityRequest.Send({
				action = "blueDestruction",
				position = { X = currentPosition.X, Y = currentPosition.Y, Z = currentPosition.Z },
				radius = BLUE_CONFIG.DESTRUCTION_RADIUS,
				allowMultiple = true,
			})
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
				end
			else
				-- Target lost root, remove from captured
				capturedTargets[targetChar] = nil
			end
		end
		
		-- DEBRIS ORBIT: Capture nearby debris and swirl it around the sphere
		-- Capture new debris pieces
		if capturedDebrisCount < BLUE_CONFIG.DEBRIS_MAX_COUNT then
			for _, debrisPart in ipairs(CollectionService:GetTagged("Debris")) do
				if not capturedDebris[debrisPart] and debrisPart.Parent then
					local dist = (debrisPart.Position - currentPosition).Magnitude
					if dist <= BLUE_CONFIG.DEBRIS_CAPTURE_RADIUS then
						-- Prevent cleanup timer from destroying it mid-orbit
						debrisPart:SetAttribute("BreakableTimer", BLUE_CONFIG.DEBRIS_LIFETIME_OVERRIDE)
						debrisPart.Anchored = true
						
						capturedDebris[debrisPart] = {
							angle = math.atan2(
								debrisPart.Position.Z - currentPosition.Z,
								debrisPart.Position.X - currentPosition.X
							),
							radius = math.max(BLUE_CONFIG.DEBRIS_ORBIT_RADIUS_MIN, dist),
							height = debrisPart.Position.Y - currentPosition.Y,
							speed = BLUE_CONFIG.DEBRIS_ORBIT_SPEED_MIN
								+ math.random() * (BLUE_CONFIG.DEBRIS_ORBIT_SPEED_MAX - BLUE_CONFIG.DEBRIS_ORBIT_SPEED_MIN),
							dir = math.random() > 0.5 and 1 or -1,
							spinAxis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit,
						}
						capturedDebrisCount += 1
						
						if capturedDebrisCount >= BLUE_CONFIG.DEBRIS_MAX_COUNT then
							break
						end
					end
				end
			end
		end
		
		-- Orbit all captured debris around the center
		for debrisPart, data in pairs(capturedDebris) do
			if not debrisPart or not debrisPart.Parent then
				capturedDebris[debrisPart] = nil
				capturedDebrisCount -= 1
				continue
			end
			
			-- Advance orbit angle
			data.angle += data.speed * data.dir * dt
			
			-- Spiral inward gradually
			data.radius = math.max(
				BLUE_CONFIG.DEBRIS_ORBIT_RADIUS_MIN,
				data.radius - BLUE_CONFIG.DEBRIS_SPIRAL_RATE * dt
			)
			
			-- Dampen height toward center + slight bobbing
			data.height = data.height * 0.97 + math.sin(data.angle * 0.7) * 0.3
			
			-- Calculate orbit position
			local offsetX = math.cos(data.angle) * data.radius
			local offsetZ = math.sin(data.angle) * data.radius
			local targetPos = currentPosition + Vector3.new(offsetX, data.height, offsetZ)
			
			-- Smooth lerp so debris doesn't teleport
			local lerpedPos = debrisPart.Position:Lerp(targetPos, math.min(1, 10 * dt))
			
			-- Spin the piece itself for visual flair
			local spinAngle = data.angle * 2
			debrisPart.CFrame = CFrame.new(lerpedPos) * CFrame.fromAxisAngle(data.spinAxis, spinAngle)
		end
	end
	
	-- Helper: release all captured debris (drop or fling)
	local function releaseDebris(flingFrom)
		for debrisPart, data in pairs(capturedDebris) do
			if debrisPart and debrisPart.Parent then
				debrisPart.Anchored = false
				debrisPart:SetAttribute("BreakableTimer", 3) -- Resume normal cleanup
				
				if flingFrom then
					-- Fling outward from explosion center
					local awayDir = (debrisPart.Position - flingFrom)
					awayDir = awayDir.Magnitude > 0.1 and awayDir.Unit or Vector3.yAxis
					debrisPart.AssemblyLinearVelocity = awayDir * BLUE_CONFIG.EXPLOSION_OUTWARD
						+ Vector3.new(0, BLUE_CONFIG.EXPLOSION_UPWARD * 0.5, 0)
				else
					-- Preserve path momentum when releasing so debris doesn't just drop straight down.
					local radialDir = Vector3.new(math.cos(data.angle), 0, math.sin(data.angle))
					local tangent = Vector3.new(-radialDir.Z, 0, radialDir.X) * data.dir
					if tangent.Magnitude < 0.01 then
						tangent = Vector3.xAxis
					end
					tangent = tangent.Unit

					local orbitLinear = tangent * (data.speed * data.radius * 6)
					local inward = -radialDir * 4
					local verticalCarry = Vector3.new(0, math.clamp(data.height * 1.2, -6, 12), 0)
					debrisPart.AssemblyLinearVelocity = orbitLinear + inward + verticalCarry
				end
			end
		end
		capturedDebris = {}
		capturedDebrisCount = 0
	end
	
	-- Check if cancelled before explosion
	if state.cancelled then
		-- Drop all orbiting debris (no fling)
		releaseDebris(nil)
		
		-- Fire cleanup event
		LocalPlayer:SetAttribute(`blue_projectile_activeCFR`, nil)
		abilityRequest.Send({
			action = "blueProjectileUpdate",
			debris = true,
			allowMultiple = true,
		})
		
		endBlue(state)
		return
	end
	
	-- EXPLOSION at end (use current lerped position)
	local finalPosition = currentPosition
	
	-- Stop following and drop orbiting debris (no end fling)
	releaseDebris(nil)
	
	-- Update visual for explosion
	--if hitboxViz and hitboxViz.Parent then
	--	hitboxViz.CFrame = CFrame.new(finalPosition)
	--	hitboxViz.Color = Color3.fromRGB(255, 100, 0)
	--	hitboxViz.Size = Vector3.new(BLUE_CONFIG.HITBOX_RADIUS * 4, BLUE_CONFIG.HITBOX_RADIUS * 4, BLUE_CONFIG.HITBOX_RADIUS * 4)
	--	Debris:AddItem(hitboxViz, 0.5)
	--end

	-- Fade out the idle sound before cleanup
	fadeOutBlueIdleSound(1.5)

	-- Play "Then Erased" voice line
	Dialogue.generate("HonoredOne", "Ability", "BlueEnd", { override = true })

	VFXRep:Fire("Me", { Module = "HonoredOne", Function = "User" }, {
		Character = character,
		forceAction = "blue_close",
		pivot = CFrame.new(finalPosition),
		radius = BLUE_CONFIG.HITBOX_RADIUS,
	})
	abilityRequest.Send({
		action = "relayUserVfx",
		forceAction = "blue_close",
		pivot = CFrame.new(finalPosition),
		radius = BLUE_CONFIG.HITBOX_RADIUS,
		allowMultiple = true,
	})
	
	-- Cleanup blue VFX
	task.delay(0.1, function()
		LocalPlayer:SetAttribute(`blue_projectile_activeCFR`, nil)
		abilityRequest.Send({
			action = "blueProjectileUpdate",
			debris = true,
			allowMultiple = true,
		})
	end)

	-- Blue ability does NO damage - just knockback/CC (no fling at end)
	
	-- Send to server for cooldown + server-side destruction (replicated to all clients)
	abilityRequest.Send({
		action = "blueHit",
		explosionPosition = { X = finalPosition.X, Y = finalPosition.Y, Z = finalPosition.Z },
		allowMultiple = true,
	})
	
	-- Hitbox finished - clear state
	endBlue(state)
	if HonoredOne._abilityState == state then
		HonoredOne._abilityState = nil
	end
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

	-- Skip hits inside the Rigs template container
	local rigContainer = Workspace:FindFirstChild("Rigs")
	if rigContainer and hitInstance:IsDescendantOf(rigContainer) then
		return nil, nil, false
	end

	local isHeadshot = hitInstance.Name == "Head"
		or hitInstance.Name == "CrouchHead"
		or hitInstance.Name == "HitboxHead"

	-- Walk up to find a Collider with Hitbox/Standing or Hitbox/Crouching
	local current = hitInstance
	while current and current ~= Workspace do
		if current.Name == "Collider" then
			local hitboxFolder = current:FindFirstChild("Hitbox")
			if not hitboxFolder or not hitInstance:IsDescendantOf(hitboxFolder) then
				return nil, nil, false
			end

			local standingFolder = hitboxFolder:FindFirstChild("Standing")
			local crouchingFolder = hitboxFolder:FindFirstChild("Crouching")
			if standingFolder and hitInstance:IsDescendantOf(standingFolder) then
				-- valid
			elseif crouchingFolder and hitInstance:IsDescendantOf(crouchingFolder) then
				-- valid
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

			-- No OwnerUserId (dummy/entity with Collider) - check parent model
			local characterModel = current.Parent
			if characterModel and characterModel:IsA("Model") then
				local humanoid = characterModel:FindFirstChildWhichIsA("Humanoid", true)
				if humanoid then
					return nil, characterModel, isHeadshot
				end
			end

			return nil, nil, false
		end

		-- Reject hits on visual Rig models
		if current.Name == "Rig" and current:IsA("Model") then
			return nil, nil, false
		end

		current = current.Parent
	end

	return nil, nil, false
end

local function runRedProjectile(state)
	local abilityRequest = state.abilityRequest
	local character = state.character
	
	local knockbackController = ServiceRegistry:GetController("Knockback")
	if not knockbackController then
		warn("[HonoredOne] KnockbackController not found!")
	end
	
	local camera = Workspace.CurrentCamera
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
	if not hrp then return end
	
	-- Get fire direction and starting position
	local direction = camera.CFrame.LookVector
	local intendedStart = hrp.Position + (direction * 3) + Vector3.new(0, 1, 0)
	
	-- Raycast to prevent firing through walls
	local wallCheckParams = RaycastParams.new()
	wallCheckParams.FilterType = Enum.RaycastFilterType.Exclude
	local effectsFolderCheck = Workspace:FindFirstChild("Effects")
	wallCheckParams.FilterDescendantsInstances = effectsFolderCheck and { character, effectsFolderCheck } or { character }
	
	local wallCheck = Workspace:Raycast(hrp.Position + Vector3.new(0, 1, 0), direction * 3.5, wallCheckParams)
	
	local startPosition
	if wallCheck then
		-- Wall in the way - start projectile slightly in front of player (not through wall)
		startPosition = wallCheck.Position - (direction * 0.5)
	else
		-- No wall - use intended start position
		startPosition = intendedStart
	end
	
	-- Apply RECOIL knockback to player (push back in opposite direction of shot)
	if knockbackController then
		local recoilVelocity = -direction * RED_CONFIG.RECOIL_STRENGTH
		knockbackController:_sendKnockbackVelocity(character, recoilVelocity, 0)
	end
	
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
	projectileViz.Transparency = 1
	projectileViz.Material = Enum.Material.Neon
	projectileViz.Color = Color3.fromRGB(255, 50, 50)
	projectileViz.Parent = getEffectsFolder()
	
	state.projectileViz = projectileViz
	state.projectileActive = true
	
	-- Reparent charge sound to projectile and play shoot sound
	reparentChargeSoundToProjectile(projectileViz)
	playShootSound(projectileViz)
	
	-- Raycast params - must match WeaponProjectile exclusions so hits detect correctly
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { character }

	local rigContainer = Workspace:FindFirstChild("Rigs")
	if rigContainer then
		table.insert(filterList, rigContainer)
	end

	-- Exclude cosmetic Rig sub-models inside all characters so projectile
	-- only collides with Collider/Hitbox parts, not R6 visual rig parts.
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			local rig = player.Character:FindFirstChild("Rig")
			if rig then
				table.insert(filterList, rig)
			end
		end
	end

	local dummiesFolder = Workspace:FindFirstChild("Dummies")
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

	local effectsFolder = Workspace:FindFirstChild("Effects")
	if effectsFolder then table.insert(filterList, effectsFolder) end

	local voxelCache = Workspace:FindFirstChild("VoxelCache")
	if voxelCache then table.insert(filterList, voxelCache) end

	local destructionFolder = Workspace:FindFirstChild("__Destruction")
	if destructionFolder then table.insert(filterList, destructionFolder) end

	rayParams.FilterDescendantsInstances = filterList
	
	-- Track state
	local piercedTargets = {} -- { [userId or charName] = true }
	local hitList = {}
	local distanceTraveled = 0
	local exploded = false
	local explosionPivot = nil -- CFrame oriented to hit surface
	local destructionDistanceAccumulator = 0
	local DESTRUCTION_STEP = 8 -- Every 8 studs, destroy terrain
	
	-- Use Heartbeat for smooth physics
	local connection
	local started = false
	connection = RunService.Heartbeat:Connect(function(dt)
		-- Check for cancel
		if state.cancelled then
			connection:Disconnect()
			endRed(state)
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
		
		local piercedWall = false

		-- Check if hit something
		if hitResult then
			local hitPlayer, hitCharacter, isHeadshot = getPlayerFromHit(hitResult.Instance)
			
			if hitPlayer then
				-- Hit a player's Collider/Hitbox - pierce through
				local targetId = hitPlayer.UserId
				
				if not piercedTargets[targetId] then
					piercedTargets[targetId] = true
					
					local damage = isHeadshot and RED_CONFIG.HEADSHOT_DAMAGE or RED_CONFIG.BODY_DAMAGE
					
					-- Play hit voice line
					playHitVoice(projectileViz)
					
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
					
					-- Play hit voice line
					playHitVoice(projectileViz)
					
					-- No knockback on pierce (just damage)
					
					-- Add to hit list
					table.insert(hitList, {
						characterName = hitCharacter.Name,
						isDummy = true,
						isHeadshot = isHeadshot,
						damage = damage,
						hitPosition = { X = hitResult.Position.X, Y = hitResult.Position.Y, Z = hitResult.Position.Z },
					})
					
					-- Add to filter
					local filter = rayParams.FilterDescendantsInstances
					table.insert(filter, hitCharacter)
					rayParams.FilterDescendantsInstances = filter
				end
				
			else
				-- Hit world/environment - check if breakable
				local hitPart = hitResult.Instance
				local isBreakable = false
				if hitPart then
					if hitPart:HasTag("Breakable") or hitPart:HasTag("BreakablePiece") or hitPart:HasTag("Debris") then
						isBreakable = true
					elseif hitPart:FindFirstAncestorOfClass("Model") and (hitPart:FindFirstAncestorOfClass("Model"):HasTag("Breakable") or hitPart:FindFirstAncestorOfClass("Model"):HasTag("BreakablePiece")) then
						isBreakable = true
					end
				end

				if isBreakable then
					local hitPos = hitResult.Position
					
					-- Send to server for replication to all clients (like Blue)
					abilityRequest.Send({
						action = "redDestruction",
						position = { X = hitPos.X, Y = hitPos.Y, Z = hitPos.Z },
						radius = RED_CONFIG.DESTRUCTION_RADIUS,
						allowMultiple = true,
					})

					local filter = rayParams.FilterDescendantsInstances
					table.insert(filter, hitPart)
					rayParams.FilterDescendantsInstances = filter

					position = hitPos + velocity.Unit * 0.5
					piercedWall = true
				else
					position = hitResult.Position

					local hitNormal = hitResult.Normal
					explosionPivot = CFrame.lookAt(position, position + hitNormal)

					if projectileViz and projectileViz.Parent then
						projectileViz.CFrame = CFrame.new(position)
					end

					connection:Disconnect()
					exploded = true
					return
				end
			end
		end
		
		if not piercedWall then
			position = newPosition
		else
			-- Reset accumulator on pierce so we destroy immediately after pass-through
			destructionDistanceAccumulator = DESTRUCTION_STEP 
		end
		velocity = newVelocity

		-- Continuous destruction based on distance traveled (prevents gaps at high speed)
		destructionDistanceAccumulator += moveDistance
		if destructionDistanceAccumulator >= DESTRUCTION_STEP then
			destructionDistanceAccumulator = 0
			
			-- Send to server for replication to all clients (like Blue)
			abilityRequest.Send({
				action = "redDestruction",
				position = { X = position.X, Y = position.Y, Z = position.Z },
				radius = RED_CONFIG.DESTRUCTION_RADIUS,
				allowMultiple = true,
			})
		end
		
		-- Update visual
		local redPivot = CFrame.lookAt(position, position + velocity.Unit)
		if projectileViz and projectileViz.Parent then
			projectileViz.CFrame = redPivot
		end
		LocalPlayer:SetAttribute(`red_projectile_activeCFR`, redPivot)

		local now = os.clock()
		if (state.lastRedReplicationAt or 0) + PROJECTILE_REPLICATION_INTERVAL <= now then
			state.lastRedReplicationAt = now
			abilityRequest.Send({
				action = "redProjectileUpdate",
				pivot = redPivot,
				position = { X = position.X, Y = position.Y, Z = position.Z },
				direction = { X = velocity.Unit.X, Y = velocity.Unit.Y, Z = velocity.Unit.Z },
				allowMultiple = true,
			})
		end
		
		if not started then
			started = true

			VFXRep:Fire("Me", { Module = "HonoredOne", Function = "User" }, {
				Character = character,
				forceAction = "red_shootlolll",
			})
			abilityRequest.Send({
				action = "relayUserVfx",
				forceAction = "red_shootlolll",
				allowMultiple = true,
			})

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
		endRed(state)
		return
	end
	
	LocalPlayer:SetAttribute(`red_projectile_activeCFR`, nil)
	
	-- Store explosion pivot (CFrame oriented to hit surface) - nil if max range reached
	if not explosionPivot then
		-- Max range reached without hitting surface - use projectile direction as "surface"
		explosionPivot = CFrame.lookAt(position, position - direction)
	end
	LocalPlayer:SetAttribute(`red_explosion_pivot`, explosionPivot)

	-- Fire explosion VFX
	VFXRep:Fire("Me", { Module = "HonoredOne", Function = "User" }, {
		Character = character,
		pivot = explosionPivot,
		forceAction = "red_explode",
	})
	abilityRequest.Send({
		action = "relayUserVfx",
		forceAction = "red_explode",
		pivot = explosionPivot,
		allowMultiple = true,
	})

	-- Stop charge sound and play explosion sound at explosion position
	stopChargeSound()
	playExplosionSound(position)

	-- Explosion visual
	endRed(state, true)
	--if projectileViz and projectileViz.Parent then
	--	projectileViz.Color = Color3.fromRGB(255, 150, 50)
	--	projectileViz.Size = Vector3.new(RED_CONFIG.EXPLOSION_RADIUS * 2, RED_CONFIG.EXPLOSION_RADIUS * 2, RED_CONFIG.EXPLOSION_RADIUS * 2)
	--	projectileViz.Transparency = 0.6
	--	Debris:AddItem(projectileViz, 0.5)
	--end
	
	-- Find targets in explosion radius (DON'T exclude player - allows rocket jumping!)
	local explosionTargets = Hitbox.GetCharactersInSphere(position, RED_CONFIG.EXPLOSION_RADIUS, {})
	
	-- Also check if player is in explosion radius for self-knockback
	local playerInExplosion = false
	local playerRoot = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
	if playerRoot then
		local distToExplosion = (playerRoot.Position - position).Magnitude
		if distToExplosion <= RED_CONFIG.EXPLOSION_RADIUS then
			playerInExplosion = true
		end
	end
	
	-- Apply knockback to player if in range (rocket jump!)
	if playerInExplosion and playerRoot and knockbackController then
		local awayDir = (playerRoot.Position - position)
		awayDir = awayDir.Magnitude > 0.1 and awayDir.Unit or Vector3.yAxis
		
		local explosionVelocity = (awayDir * RED_CONFIG.EXPLOSION_OUTWARD) + Vector3.new(0, RED_CONFIG.EXPLOSION_UPWARD, 0)
		knockbackController:_sendKnockbackVelocity(character, explosionVelocity, 0)
	end
	
	for _, targetChar in ipairs(explosionTargets) do
		-- Skip self for damage (but knockback already applied above)
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		if targetPlayer == abilityRequest.player then
			continue
		end
		
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Root") or targetChar.PrimaryPart
		if targetRoot and knockbackController then
			-- Knockback away from explosion
			local awayDir = (targetRoot.Position - position)
			awayDir = awayDir.Magnitude > 0.1 and awayDir.Unit or direction
			
			local explosionVelocity = (awayDir * RED_CONFIG.EXPLOSION_OUTWARD) + Vector3.new(0, RED_CONFIG.EXPLOSION_UPWARD, 0)
			knockbackController:_sendKnockbackVelocity(targetChar, explosionVelocity, 0)
		end
		
		-- Add explosion damage if not already pierced
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
		abilityRequest.Send({
			action = "redHit",
			hits = hitList,
			explosionPosition = { X = position.X, Y = position.Y, Z = position.Z },
			pivot = explosionPivot,
			allowMultiple = true,
		})
	end

	-- Always request server-side red explosion destruction on impact.
	abilityRequest.Send({
		action = "redDestruction",
		position = { X = position.X, Y = position.Y, Z = position.Z },
		radius = RED_CONFIG.EXPLOSION_RADIUS,
		allowMultiple = true,
	})
	
	-- Cleanup pivot attribute after a short delay (let VFX read it first)
	task.delay(0.1, function()
		LocalPlayer:SetAttribute(`red_explosion_pivot`, nil)
		abilityRequest.Send({
			action = "redProjectileUpdate",
			debris = true,
			allowMultiple = true,
		})
		
	end)
	
	state.projectileActive = false
	state.projectileViz = nil
	if HonoredOne._abilityState == state then
		HonoredOne._abilityState = nil
	end
end

--------------------------------------------------------------------------------
-- Ability: E Press - DUALITY (Animation-Driven)
--------------------------------------------------------------------------------

function HonoredOne.Ability:OnStart(abilityRequest)
	local hrp = abilityRequest.humanoidRootPart
	local character = abilityRequest.character
	if not hrp or not character then return end

	local kitController = ServiceRegistry:GetController("Kit")
	local inputManager = ServiceRegistry:GetController("Input")

	if kitController:IsAbilityActive() then return end
	if abilityRequest.IsOnCooldown() then return end

	-- Check crouch state to determine Blue vs Red
	local isCrouching = false
	if inputManager and inputManager.IsCrouchHeld then
		isCrouching = inputManager:IsCrouchHeld()
	end

	-- Start ability
	local ctx = abilityRequest.StartAbility()
	
	-- DON'T lock weapon switch immediately - allow cancel by swapping weapons
	-- Will lock at "open" (Blue) or "shoot" (Red) when ability commits
	local weaponLocked = false
	local function lockWeaponNow()
		if not weaponLocked then
			weaponLocked = true
			kitController:LockWeaponSwitch()
		end
	end
	local function unlockWeaponNow()
		if weaponLocked then
			weaponLocked = false
			kitController:UnlockWeaponSwitch()
		end
	end

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
		kitController:_unholsterWeapon()
		return
	end

	-- State tracking
	local state = {
		active = true,           -- Animation is playing
		hitboxActive = false,    -- Blue hitbox is running
		projectileActive = false, -- Red projectile is running
		cancelled = false,       -- Hard cancel (interrupt)
		released = false,        -- Button released (for Red freeze/aim)
		committed = false,       -- Has ability committed (cooldown started)?
		isCrouching = isCrouching,
		animation = animation,
		lockWeapon = lockWeaponNow,
		unlockWeapon = unlockWeaponNow,
		abilityRequest = abilityRequest,
		character = character,
		viewmodelRig = viewmodelRig,
		connections = {},
		hitboxViz = nil,
		projectileViz = nil,
	}
	HonoredOne._abilityState = state

	-- Play start sound immediately for red ability (no delay)
	if isCrouching then
		playStartSound(viewmodelRig)
	end

	-- Listen for weapon slot changes to cancel if not yet committed
	local slotChangedConn
	slotChangedConn = LocalPlayer:GetAttributeChangedSignal("EquippedSlot"):Connect(function()
		if state.committed or state.cancelled then
			-- Already committed or cancelled, ignore
			return
		end
		
		-- Player swapped weapons before ability committed - cancel!
		state.cancelled = true
		state.active = false
		
		-- Stop animation
		if state.animation and state.animation.IsPlaying then
			state.animation:Stop(0.1)
		end
		
		-- Cleanup
		cleanupSounds()
		clearRedStateAttributes()
		endBlue(state)
		endRed(state)
		
		-- Disconnect all connections
		for _, conn in ipairs(state.connections or {}) do
			if typeof(conn) == "RBXScriptConnection" then
				conn:Disconnect()
			end
		end
		state.connections = {}
		
		-- Clear state
		if HonoredOne._abilityState == state then
			HonoredOne._abilityState = nil
		end
		
		-- Disconnect this listener
		if slotChangedConn then
			slotChangedConn:Disconnect()
		end
	end)
	table.insert(state.connections, slotChangedConn)

	-- Animation event handlers
	local Events = {
		["create"] = function()
			-- VFX/sounds on ability start (charging for Red)
			-- TODO: Add VFXRep call for start effects
			if isCrouching then
				setExternalMoveMult(0.45)
				setRedCrouchGate()
				VFXRep:Fire("Me", { Module = "HonoredOne", Function = "User" }, {
					ViewModel = viewmodelRig,
					forceAction = "red_create",
				})	
			end
		
		end,
		
		["start"] = function()
			-- VFX on ability start (charging for Red) - sound already played at ability start
			if isCrouching then
				LocalPlayer:SetAttribute(`red_charge`, true)

				VFXRep:Fire("Me", { Module = "HonoredOne", Function = "User" }, {
					ViewModel = viewmodelRig,
					forceAction = "red_charge",
				})
			end
		end,

		["freeze"] = function()
			-- RED ONLY: Pause animation while player aims
			if not isCrouching then return end
			if state.cancelled then return end
			if state.active and not state.released then
				state.animation:AdjustSpeed(0)
				
				-- Start max hold timer - auto-fire after MAX_HOLD_TIME seconds
				task.delay(RED_CONFIG.MAX_HOLD_TIME, function()
					-- Only auto-release if still frozen (not yet released or cancelled)
					if state.active and not state.released and not state.cancelled then
						state.released = true
						state.animation:AdjustSpeed(1)
					end
				end)
			end
		end,

		["open"] = function()
			-- BLUE ONLY: Spawn hitbox
			if isCrouching then return end
			if not state.active or state.cancelled then return end

			-- COMMIT: Lock weapon switch and start cooldown
			state.committed = true
			state.lockWeapon()
			setExternalMoveMult(0.5)
			abilityRequest.Send({ action = "startCooldown", allowMultiple = true })

			local function cancelBlue(reason)
				if state.cancelled or state.isCrouching or not state.committed then return end
				HonoredOne.Ability:OnInterrupt(nil, reason or "blue_cancel")
			end

			-- Cancel Blue instantly if we take damage
			local humanoid = character:FindFirstChildWhichIsA("Humanoid")
			local function onDurabilityChanged(newDurability)
				if type(newDurability) ~= "number" then
					return
				end

				if state.cancelled or state.isCrouching or not state.committed then
					state.blueLastDurability = newDurability
					return
				end

				local lastDurability = state.blueLastDurability or newDurability
				if newDurability < lastDurability then
					cancelBlue("blue_cancel_damage")
				end
				state.blueLastDurability = newDurability
			end

			state.blueLastDurability = getBlueDurabilitySnapshot(character, humanoid) or 0
			table.insert(state.connections, LocalPlayer:GetAttributeChangedSignal("Health"):Connect(function()
				local snapshot = getBlueDurabilitySnapshot(character, humanoid)
				onDurabilityChanged(snapshot)
			end))
			table.insert(state.connections, LocalPlayer:GetAttributeChangedSignal("Shield"):Connect(function()
				local snapshot = getBlueDurabilitySnapshot(character, humanoid)
				onDurabilityChanged(snapshot)
			end))
			table.insert(state.connections, LocalPlayer:GetAttributeChangedSignal("Overshield"):Connect(function()
				local snapshot = getBlueDurabilitySnapshot(character, humanoid)
				onDurabilityChanged(snapshot)
			end))

			-- Fallback for contexts that still use humanoid health directly.
			if humanoid then
				table.insert(state.connections, humanoid.HealthChanged:Connect(function(newHealth)
					if type(LocalPlayer:GetAttribute("Health")) == "number" then
						return
					end
					onDurabilityChanged(newHealth)
				end))
			end

			-- Cancel Blue instantly if local knockback is applied
			local knockbackController = ServiceRegistry:GetController("Knockback")
			if knockbackController and knockbackController.GetKnockbackSignal then
				table.insert(state.connections, knockbackController:GetKnockbackSignal():Connect(function()
					cancelBlue("blue_cancel_knockback")
				end))
			end

			-- Play "Pulled" voice line
			Dialogue.generate("HonoredOne", "Ability", "BlueStart", { override = true })

			task.spawn(runBlueHitbox, state)
		end,

		["shoot"] = function()
			-- RED ONLY: Fire projectile
			if not isCrouching then return end
			if not state.active or state.cancelled then return end
			
			-- COMMIT: Lock weapon switch and start cooldown
			state.committed = true
			state.lockWeapon()
			setExternalMoveMult(0.45)
			setRedCrouchGate()
			abilityRequest.Send({ action = "startCooldown", allowMultiple = true })
			
			task.spawn(runRedProjectile, state)

			VFXRep:Fire("Me", { Module = "HonoredOne", Function = "User" }, {
				ViewModel = viewmodelRig,
				forceAction = "red_fire",
			})
			LocalPlayer:SetAttribute(`red_charge`, nil)
		end,

		["_finish"] = function()
			if not state.active then return end
			
			state.active = false

			-- Cleanup animation connections
			for _, conn in ipairs(state.connections) do
				if typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				end
			end
			state.connections = {}

			-- Restore weapon (animation done, but hitbox/projectile continues)
			state.unlockWeapon()
			kitController:_unholsterWeapon()
			clearRedStateAttributes()

			-- If ability never committed, hard-clean everything here.
			-- If committed, Blue/Red runtime loops own their cleanup.
			if not state.committed then
				state.cancelled = true
				endBlue(state)
				endRed(state)
				if HonoredOne._abilityState == state then
					HonoredOne._abilityState = nil
				end
			end
		end,
	}

	-- Connect to animation events
	state.connections[#state.connections + 1] = animation:GetMarkerReachedSignal("Event"):Connect(function(eventName)
		if Events[eventName] then
			Events[eventName]()
		end
	end)

	-- Safety cleanup on animation end
	state.connections[#state.connections + 1] = animation.Stopped:Once(function()
		if state.active then
			Events["_finish"]()
		end
	end)

	state.connections[#state.connections + 1] = animation.Ended:Once(function()
		if state.active then
			Events["_finish"]()
		end
	end)
end

function HonoredOne.Ability:OnEnded(abilityRequest)
	local state = HonoredOne._abilityState
	if not state then return end
	if not state.active or state.cancelled then return end
	
	-- Mark as released
	state.released = true
	clearRedStateAttributes()
	
	-- Resume animation from freeze (Red ability)
	if state.isCrouching and state.animation and state.animation.IsPlaying then
		state.animation:AdjustSpeed(1)
	end
end

function HonoredOne.Ability:OnInterrupt(abilityRequest, reason)
	local state = HonoredOne._abilityState
	if not state then return end
	
	-- Already fully finished
	if not state.active and not state.hitboxActive and not state.projectileActive then return end
	
	-- Hard cancel - stops everything including hitbox/projectile
	state.cancelled = true
	state.active = false
	LocalPlayer:SetAttribute(`blue_projectile_activeCFR`, nil)
	local request = abilityRequest or state.abilityRequest
	if request and request.Send then
		request.Send({
			action = "blueProjectileUpdate",
			debris = true,
			allowMultiple = true,
		})
	end
	endBlue(state)
	endRed(state)
	HonoredOne._abilityState = nil

	-- Stop animation
	if state.animation and state.animation.IsPlaying then
		state.animation:Stop(0.1)
	end

	-- Cleanup connections
	for _, conn in ipairs(state.connections or {}) do
		if typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end

	-- Cleanup all sounds
	cleanupSounds()

	-- Restore weapon (if animation hadn't finished yet)
	if state.unlockWeapon then
		state.unlockWeapon()
	end
	ServiceRegistry:GetController("Kit"):_unholsterWeapon()
end

--------------------------------------------------------------------------------
-- Ultimate (placeholder)
--------------------------------------------------------------------------------

function HonoredOne.Ultimate:OnStart(abilityRequest)
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
	return self
end

function HonoredOne:OnEquip(ctx)
	self._ctx = ctx
end

function HonoredOne:OnUnequip(reason)
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
