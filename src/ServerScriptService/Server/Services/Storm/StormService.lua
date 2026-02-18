--[[
	StormService.lua
	Server-side service for managing the storm system in competitive matches.
	
	When the round timer expires, the storm phase begins:
	- Picks a random safe zone point on the map using raycasting
	- Spawns the storm model (mesh) at 1.5x the map hitbox size
	- Shrinks the storm over time toward the safe zone center
	- Players outside the safe zone take damage over time
	- Broadcasts storm state to clients for UI and visual effects
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local StormService = {}

-- Storm configuration
local STORM_INITIAL_SCALE_MULTIPLIER = 1.5 -- Start at 1.5x the hitbox size
local STORM_FINAL_RADIUS = 0 -- Shrink all the way to zero
local STORM_SHRINK_DURATION = 90 -- Seconds to fully shrink (slower)
local STORM_DPS = 8 -- Damage per second while in storm
local STORM_DAMAGE_TICK_RATE = 0.5 -- How often to apply damage (seconds)
local STORM_UPDATE_RATE = 0.1 -- How often to update storm state (seconds)
local STORM_FADE_IN_TIME = 2 -- Seconds to fade in the storm mesh
local STORM_Y_OFFSET = -200 -- Offset storm mesh down by 200 studs

StormService._registry = nil
StormService._net = nil
StormService._activeStorms = {} -- [matchId] = stormData

function StormService:Init(registry, net)
	self._registry = registry
	self._net = net
end

function StormService:Start()
	-- Cleanup on player leaving
	Players.PlayerRemoving:Connect(function(player)
		-- Remove player from any active storm tracking
		for _, stormData in self._activeStorms do
			if stormData.playersInStorm then
				stormData.playersInStorm[player] = nil
			end
		end
	end)
end

--[[
	Starts the storm phase for a match.
	Called by MatchManager when round timer expires.
	@param match The match object from MatchManager
]]
function StormService:StartStorm(match)
	if not match or not match.mapInstance then
		warn("[STORMSERVICE] Cannot start storm - invalid match or no map instance")
		return
	end
	
	-- Find the map hitbox to determine storm size
	local hitbox = match.mapInstance:FindFirstChild("Hitbox")
	if not hitbox then
		warn("[STORMSERVICE] No Hitbox part found in map - using default size")
		hitbox = {
			Size = Vector3.new(200, 100, 200),
			Position = Vector3.new(0, 50, 0),
		}
	end
	
	local hitboxSize = hitbox.Size
	local hitboxPos = hitbox.Position
	
	-- Calculate initial radius (1.5x the largest horizontal dimension)
	local initialRadius = math.max(hitboxSize.X, hitboxSize.Z) * STORM_INITIAL_SCALE_MULTIPLIER / 2
	
	-- Pick random safe zone center point
	local safeZoneCenter = self:_pickRandomSafeZonePoint(hitbox, match.mapInstance)
	
	-- NOTE: Storm mesh is now CLIENT-SIDE ONLY to prevent cross-match visibility
	-- Server only tracks position/radius for damage calculation
	
	-- Calculate shrink rate
	local shrinkRate = (initialRadius - STORM_FINAL_RADIUS) / STORM_SHRINK_DURATION
	
	-- Store storm data (no model - client creates their own local mesh)
	local stormData = {
		model = nil, -- Client-side only now
		center = safeZoneCenter,
		initialRadius = initialRadius,
		currentRadius = initialRadius,
		targetRadius = STORM_FINAL_RADIUS,
		shrinkRate = shrinkRate,
		damagePerTick = STORM_DPS * STORM_DAMAGE_TICK_RATE,
		playersInStorm = {},
		lastDamageTick = 0,
		matchId = match.id,
	}
	
	self._activeStorms[match.id] = stormData
	match.storm = stormData
	
	-- Fire storm start to all match clients
	local matchManager = self._registry:TryGet("MatchManager")
	if matchManager then
		for _, player in matchManager:_getMatchPlayers(match) do
			self._net:FireClient("StormStart", player, {
				matchId = match.id,
				center = safeZoneCenter,
				initialRadius = initialRadius,
				targetRadius = STORM_FINAL_RADIUS,
				shrinkDuration = STORM_SHRINK_DURATION,
			})
		end
	end
	
	-- Play storm forming sound
	self:_fireMatchSound(match, "stormforming")
	
	-- Start storm update loop
	self:_startStormLoop(match)
	
	print("[STORMSERVICE] Storm started for match", match.id, "- Center:", safeZoneCenter, "Initial radius:", initialRadius)
end

--[[
	Picks a random point on the map for the safe zone center.
	Uses raycasting from the hitbox to find valid ground.
	Only accepts hits on parts that are descendants of the "Map" model.
]]
function StormService:_pickRandomSafeZonePoint(hitbox, mapInstance)
	local size = hitbox.Size
	local pos = hitbox.Position
	
	-- Get the Map model (the actual geometry we want to hit)
	local mapModel = mapInstance:FindFirstChild("Map")
	if not mapModel then
		warn("[STORMSERVICE] Map model not found under", mapInstance.Name)
		return Vector3.new(pos.X, pos.Y - size.Y / 2, pos.Z)
	end
	
	print("[STORM RAYCAST] Hitbox size:", size, "Hitbox pos:", pos)
	print("[STORM RAYCAST] MapModel:", mapModel.Name, "under", mapInstance.Name)
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { mapModel } -- Only hit Map descendants
	
	-- Try up to 30 times to find a valid point
	for i = 1, 30 do
		local randomX = pos.X + (math.random() - 0.5) * size.X * 0.8
		local randomZ = pos.Z + (math.random() - 0.5) * size.Z * 0.8
		local rayOrigin = Vector3.new(randomX, pos.Y + size.Y / 2, randomZ)
		local rayDir = Vector3.new(0, -size.Y * 2, 0)
		
		local rayResult = workspace:Raycast(rayOrigin, rayDir, rayParams)
		if rayResult then
			-- Verify it's a descendant of Map (should always be true with Include filter)
			if rayResult.Instance:IsDescendantOf(mapModel) then
				print("[STORM RAYCAST] Hit on attempt", i, "- Part:", rayResult.Instance.Name, "Position:", rayResult.Position)
				return rayResult.Position
			else
				print("[STORM RAYCAST] Hit non-Map part:", rayResult.Instance:GetFullName(), "- skipping")
			end
		else
			if i <= 3 then -- Only log first 3 misses
				print("[STORM RAYCAST] Miss #" .. i .. " - Origin:", rayOrigin)
			end
		end
	end
	
	-- Fallback to hitbox center at ground level
	warn("[STORMSERVICE] Could not find valid safe zone point after 30 attempts, using hitbox center")
	local fallback = Vector3.new(pos.X, pos.Y - size.Y / 2, pos.Z)
	print("[STORM RAYCAST] Using fallback position:", fallback)
	return fallback
end

--[[
	Spawns the storm model at the given center point with initial radius.
	Structure: Strom (Model) -> Root (Part at ground), Storm (MeshPart above Root)
]]
function StormService:_spawnStormModel(mapInstance, centerPoint, initialRadius)
	-- Find storm asset in ReplicatedStorage
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[STORMSERVICE] ReplicatedStorage.Assets not found")
		return nil
	end
	
	local stormFolder = assets:FindFirstChild("Strom") or assets:FindFirstChild("Storm")
	if not stormFolder then
		warn("[STORMSERVICE] Storm folder not found in Assets")
		return nil
	end
	
	-- Clone the entire storm model
	local stormClone = stormFolder:Clone()
	
	-- Find the Root and Storm parts
	local rootPart = stormClone:FindFirstChild("Root")
	local stormMesh = stormClone:FindFirstChild("Storm")
	
	if not stormMesh or not stormMesh:IsA("BasePart") then
		warn("[STORMSERVICE] Storm MeshPart not found in storm model")
		stormClone:Destroy()
		return nil
	end
	
	-- Get the original size of the Storm mesh (908x887x908)
	local originalSize = stormMesh.Size
	print("[STORMSERVICE] Storm mesh original size:", originalSize, "Target radius:", initialRadius)
	
	-- Calculate scale: target diameter = initialRadius * 2
	local originalDiameter = math.max(originalSize.X, originalSize.Z) -- 908
	local targetDiameter = initialRadius * 2
	local scaleFactor = targetDiameter / originalDiameter
	
	print("[STORMSERVICE] Scale factor:", scaleFactor, "Original diameter:", originalDiameter, "Target diameter:", targetDiameter)
	
	-- Position Root at center point (ground level)
	if rootPart then
		rootPart.Position = centerPoint
		rootPart.Anchored = true
		rootPart.CanCollide = false
	end
	
	-- Scale X and Z, keep Y height the same
	stormMesh.Size = Vector3.new(
		originalSize.X * scaleFactor,
		originalSize.Y, -- Keep height unchanged
		originalSize.Z * scaleFactor
	)
	
	-- Position Storm so its BOTTOM is at ground level + offset, centered on X/Z
	-- Mesh center Y = groundY + offset + (meshHeight / 2)
	local meshHeight = stormMesh.Size.Y
	stormMesh.Position = Vector3.new(
		centerPoint.X,
		centerPoint.Y + STORM_Y_OFFSET + (meshHeight / 2), -- Offset down, then center at half height
		centerPoint.Z
	)
	stormMesh.Anchored = true
	stormMesh.CanCollide = false
	
	-- Start invisible, will fade in
	local originalTransparency = stormMesh.Transparency -- Should be 0.3
	stormMesh.Transparency = 1
	
	-- Store attributes for shrinking
	stormMesh:SetAttribute("OriginalSizeX", originalSize.X)
	stormMesh:SetAttribute("OriginalSizeZ", originalSize.Z)
	stormMesh:SetAttribute("ScaleFactor", scaleFactor)
	stormMesh:SetAttribute("InitialRadius", initialRadius)
	stormMesh:SetAttribute("CenterX", centerPoint.X)
	stormMesh:SetAttribute("CenterZ", centerPoint.Z)
	stormMesh:SetAttribute("OriginalTransparency", originalTransparency)
	
	-- Parent to map instance
	stormClone.Name = "ActiveStorm"
	stormClone.Parent = mapInstance
	
	-- Fade in the storm mesh
	local fadeInfo = TweenInfo.new(STORM_FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTween = TweenService:Create(stormMesh, fadeInfo, { Transparency = originalTransparency })
	fadeTween:Play()
	
	print("[STORMSERVICE] Storm spawned - Center at", centerPoint, "Storm size:", stormMesh.Size, "Mesh Y:", stormMesh.Position.Y)
	
	return stormClone
end

--[[
	Starts the storm update loop for a match.
]]
function StormService:_startStormLoop(match)
	local stormData = self._activeStorms[match.id]
	if not stormData then return end
	
	stormData.loopThread = task.spawn(function()
		local lastUpdate = os.clock()
		
		while stormData and self._activeStorms[match.id] and match.state == "storm" do
			local now = os.clock()
			local deltaTime = now - lastUpdate
			lastUpdate = now
			
			self:_updateStorm(match, deltaTime)
			
			task.wait(STORM_UPDATE_RATE)
		end
	end)
end

--[[
	Updates storm state each tick.
]]
function StormService:_updateStorm(match, deltaTime)
	local stormData = self._activeStorms[match.id]
	if not stormData then return end
	
	-- Shrink the safe zone radius
	if stormData.currentRadius > stormData.targetRadius then
		stormData.currentRadius = math.max(
			stormData.targetRadius,
			stormData.currentRadius - (stormData.shrinkRate * deltaTime)
		)
		
		-- Update storm model scale
		self:_updateStormModelScale(stormData)
	end
	
	-- Check each player's position
	local matchManager = self._registry:TryGet("MatchManager")
	if not matchManager then return end
	
	local combatService = self._registry:TryGet("CombatService")
	local now = os.clock()
	
	for _, player in matchManager:_getMatchPlayers(match) do
		-- Get accurate client-replicated position
		local playerPos = self:_getPlayerPosition(player)
		if playerPos then
			local dist = self:_getHorizontalDistance(playerPos, stormData.center)
			
			local wasInStorm = stormData.playersInStorm[player] ~= nil
			-- Player is "in storm" if they are OUTSIDE the safe radius
			local isInStorm = dist > stormData.currentRadius
			
			-- Debug logging (every 2 seconds)
			if not stormData._lastDebug or now - stormData._lastDebug > 2 then
				stormData._lastDebug = now
				print(string.format("[STORM] Player %s - dist: %.1f, radius: %.1f, inStorm: %s", 
					player.Name, dist, stormData.currentRadius, tostring(isInStorm)))
			end
			
			-- Player entered storm
			if isInStorm and not wasInStorm then
				print("[STORM] Player", player.Name, "ENTERED storm - dist:", dist, "radius:", stormData.currentRadius)
				stormData.playersInStorm[player] = {
					enteredAt = now,
					lastDamage = now,
				}
				self._net:FireClient("StormEnter", player, { matchId = match.id })
			-- Player left storm (entered safe zone)
			elseif not isInStorm and wasInStorm then
				print("[STORM] Player", player.Name, "LEFT storm (safe) - dist:", dist, "radius:", stormData.currentRadius)
				stormData.playersInStorm[player] = nil
				self._net:FireClient("StormLeave", player, { matchId = match.id })
			end
			
			-- Apply damage if in storm
			if isInStorm and stormData.playersInStorm[player] then
				local playerStormData = stormData.playersInStorm[player]
				if now - playerStormData.lastDamage >= STORM_DAMAGE_TICK_RATE then
					playerStormData.lastDamage = now
					
						-- Apply storm damage through CombatService
						if combatService then
							combatService:ApplyDamage(player, stormData.damagePerTick, {
								damageType = "Storm",
								isTrueDamage = true, -- Storm damage ignores shields/armor
							})
						end
				end
			end
		end
	end
	
	-- Broadcast storm update to all match clients (less frequently)
	if not stormData.lastBroadcast or now - stormData.lastBroadcast > 0.5 then
		stormData.lastBroadcast = now
		for _, player in matchManager:_getMatchPlayers(match) do
			self._net:FireClient("StormUpdate", player, {
				matchId = match.id,
				currentRadius = stormData.currentRadius,
			})
		end
	end
end

--[[
	Updates the storm mesh's X and Z size to match current radius.
	NOTE: Storm mesh is now client-side only - server doesn't need to update visuals
	Clients receive StormUpdate events and update their own local storm mesh
]]
function StormService:_updateStormModelScale(stormData)
	-- No-op: storm mesh is client-side only now
end

--[[
	Calculates horizontal distance (ignoring Y) between two points.
]]
function StormService:_getHorizontalDistance(pos1, pos2)
	local dx = pos1.X - pos2.X
	local dz = pos1.Z - pos2.Z
	return math.sqrt(dx * dx + dz * dz)
end

--[[
	Gets accurate player position using ReplicationService (client-replicated position).
	Falls back to character root if ReplicationService data unavailable.
]]
function StormService:_getPlayerPosition(player)
	-- Try ReplicationService first (accurate client-replicated position)
	local replicationService = self._registry:TryGet("ReplicationService")
	if replicationService and replicationService.PlayerStates then
		local state = replicationService.PlayerStates[player]
		if state and state.LastState and state.LastState.Position then
			return state.LastState.Position
		end
	end
	
	-- Fallback to character Root
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			return root.Position
		end
	end
	
	return nil
end

--[[
	Fires a sound event to all players in a match.
]]
function StormService:_fireMatchSound(match, soundName)
	local matchManager = self._registry:TryGet("MatchManager")
	if not matchManager then return end
	
	for _, player in matchManager:_getMatchPlayers(match) do
		self._net:FireClient("StormSound", player, {
			matchId = match.id,
			sound = soundName,
		})
	end
end

--[[
	Stops the storm for a match (called when match ends or round resets).
]]
function StormService:StopStorm(matchId)
	local stormData = self._activeStorms[matchId]
	if not stormData then return end
	
	-- Cancel the update loop
	if stormData.loopThread then
		pcall(task.cancel, stormData.loopThread)
		stormData.loopThread = nil
	end
	
	-- Notify all players in storm that they're leaving
	for player, _ in stormData.playersInStorm do
		if player and player.Parent then
			self._net:FireClient("StormLeave", player, { matchId = matchId })
		end
	end
	
	-- Destroy the storm model
	if stormData.model and stormData.model.Parent then
		stormData.model:Destroy()
	end
	
	self._activeStorms[matchId] = nil
	
	print("[STORMSERVICE] Storm stopped for match", matchId)
end

--[[
	Checks if a player is currently in the storm.
]]
function StormService:IsPlayerInStorm(player, matchId)
	local stormData = self._activeStorms[matchId]
	if not stormData then return false end
	
	return stormData.playersInStorm[player] ~= nil
end

--[[
	Gets the current storm data for a match.
]]
function StormService:GetStormData(matchId)
	return self._activeStorms[matchId]
end

return StormService
