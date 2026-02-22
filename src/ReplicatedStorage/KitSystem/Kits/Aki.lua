--[[
	Aki Server Kit
	
	Ability: KON - Two variants:
	
	TRAP VARIANT (E while crouching/sliding):
	- Places a hidden Kon trap at player's feet
	- Triggers when enemy enters 9.5 stud radius
	- Deals 75 damage + KonSlow (30% speed, sprint disabled, 5s)
	- 1 per match, no cooldown on placement
	- Self-launch: Aki can reactivate near trap to launch away (no damage)
	- Trap destroyed when kit is destroyed
	
	MAIN VARIANT (E while standing - placeholder for future implementation):
	- Existing Kon behavior remains for now
	
	Server responsibilities:
	1. Validate trap placement position
	2. Manage trap state (_trapPlaced, _trapPosition, _trapActive)
	3. Run proximity detection loop for trap trigger
	4. Apply damage + KonSlow on trap trigger
	5. Handle self-launch request
	6. Destroy trap on kit destroy
	7. Validate konBite hits for main variant
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local VoxManager = require(ReplicatedStorage.Shared.Modules.VoxManager)
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Hitbox = require(Locations.Shared.Util:WaitForChild("Hitbox"))

-- HitDetectionAPI for authoritative position data
local HitDetectionAPI = nil
local function getHitDetectionAPI()
	if HitDetectionAPI then
		return HitDetectionAPI
	end
	
	local antiCheat = ServerScriptService:FindFirstChild("Server")
		and ServerScriptService.Server:FindFirstChild("Services")
		and ServerScriptService.Server.Services:FindFirstChild("AntiCheat")
	
	if antiCheat then
		local apiModule = antiCheat:FindFirstChild("HitDetectionAPI")
		if apiModule then
			local ok, api = pcall(require, apiModule)
			if ok then
				HitDetectionAPI = api
				return HitDetectionAPI
			end
		end
	end
	
	return nil
end

-- Service registry helpers (same pattern as HonoredOne)
local function getKitRegistry(self)
	local service = self._ctx and self._ctx.service
	return service and service._registry or nil
end

local function getCombatService(self)
	local registry = getKitRegistry(self)
	return registry and registry:TryGet("CombatService") or nil
end

local function getWeaponService(self)
	local registry = getKitRegistry(self)
	return registry and registry:TryGet("WeaponService") or nil
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_RANGE = 150
local BITE_RADIUS = 12
local BITE_DAMAGE = 35
local MAX_HITS_PER_BITE = 5

-- Trap variant constants
local TRAP_DAMAGE = 75
local TRAP_TRIGGER_RADIUS = 9.5
local TRAP_SELF_LAUNCH_RADIUS = 9.5  -- Same radius for self-launch auto-detect
local TRAP_PLACEMENT_MAX_DIST = 40   -- Max distance from player for placement validation (35 stud aim range + tolerance)
local KONSLOW_DURATION = 5
local KONSLOW_SPEED_MULT = 0.7       -- 30% reduction

-- Self-launch force
local SELF_LAUNCH_VELOCITY = 120     -- Strong upward + outward force

-- Trap trigger upward launch force (applied to targets on bite)
local TRAP_LAUNCH_UPWARD = 180       -- Strong upward velocity on trap bite

-- Trap bite timing (must match VFX BITE_DELAY so damage aligns with visual bite)
local TRAP_BITE_DELAY = 0.6

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local Kit = {}
Kit.__index = Kit

function Kit.new(ctx)
	local self = setmetatable({}, Kit)
	self._ctx = ctx
	self._pendingSpawn = nil
	
	-- Trap state
	self._trapPlaced = false       -- Has the trap been placed this match?
	self._trapActive = false       -- Is there an active trap in the world?
	self._trapPosition = nil       -- Vector3 position of the trap
	self._trapProximityConn = nil  -- Heartbeat connection for proximity detection
	self._trapOwnerUserId = ctx.player.UserId
	
	return self
end

function Kit:SetCharacter(character)
	self._ctx.character = character
end

function Kit:Destroy()
	self._pendingSpawn = nil
	self:_destroyTrap("kitDestroyed")
end

function Kit:OnEquipped()
end

function Kit:OnUnequipped()
	self._pendingSpawn = nil
	self:_destroyTrap("unequipped")
end

--------------------------------------------------------------------------------
-- Damage Helpers
--------------------------------------------------------------------------------

local function applyDamage(self, targetCharacter, damage, weaponId)
	local player = self._ctx.player
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	
	local weaponService = getWeaponService(self)
	if weaponService then
		local root = self._ctx.character and self._ctx.character.PrimaryPart
		local sourcePos = root and root.Position or nil
		local hitPos = targetCharacter.PrimaryPart and targetCharacter.PrimaryPart.Position or nil
		
		weaponService:ApplyDamageToCharacter(
			targetCharacter,
			damage,
			player,
			false, -- not headshot
			weaponId or "Aki_Kon",
			sourcePos,
			hitPos
		)
		return
	end
	
	-- Fallback: direct humanoid damage
	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(damage)
		if targetCharacter then
			targetCharacter:SetAttribute("LastDamageDealer", player.UserId)
		end
	end
end

local function applyKonSlow(self, targetCharacter)
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if not targetPlayer then return end
	
	local combatService = getCombatService(self)
	if combatService then
		combatService:ApplyStatusEffect(targetPlayer, "KonSlow", {
			duration = KONSLOW_DURATION,
			source = self._ctx.player,
		})
	end
end

--------------------------------------------------------------------------------
-- Trap Logic
--------------------------------------------------------------------------------

function Kit:_destroyTrap(reason)
	-- Stop proximity detection
	if self._trapProximityConn then
		self._trapProximityConn:Disconnect()
		self._trapProximityConn = nil
	end
	
	self._trapActive = false
	self._trapPosition = nil
	self._trapPlaced = false  -- Allow trap to be placed again
	
	-- Broadcast trap destruction VFX to all clients
	local service = self._ctx.service
	if service then
		service:BroadcastVFX(self._ctx.player, "All", "Kon", {}, "destroyTrap")
	end
end

function Kit:_startTrapProximityLoop()
	if self._trapProximityConn then
		self._trapProximityConn:Disconnect()
	end
	
	local player = self._ctx.player
	local trapPos = self._trapPosition
	if not trapPos then return end
	
	self._trapProximityConn = RunService.Heartbeat:Connect(function()
		if not self._trapActive or not self._trapPosition then
			if self._trapProximityConn then
				self._trapProximityConn:Disconnect()
				self._trapProximityConn = nil
			end
			return
		end
		
		-- Check for characters in range (server-authoritative)
		local targets = Hitbox.GetCharactersInRadius(self._trapPosition, TRAP_TRIGGER_RADIUS, player)
		
		for _, targetCharacter in ipairs(targets) do
			-- Skip the Aki player's own character
			local character = self._ctx.character or player.Character
			if targetCharacter == character then continue end
			
			local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid and humanoid.Health > 0 then
				-- TRAP TRIGGERED! Apply damage and slow
				self:_triggerTrap(targetCharacter)
				return -- Only triggers once
			end
		end
		
		-- Also check if Aki is close for self-launch auto-detect
		-- (handled client-side via proximity check, server just validates the action)
	end)
end

function Kit:_triggerTrap(triggerCharacter)
	if not self._trapActive then return end
	
	local trapPos = self._trapPosition
	if not trapPos then return end
	
	local player = self._ctx.player
	local service = self._ctx.service
	
	-- Stop proximity loop
	if self._trapProximityConn then
		self._trapProximityConn:Disconnect()
		self._trapProximityConn = nil
	end
	
	self._trapActive = false
	
	-- Determine look direction for triggered Kon VFX (face toward trigger character)
	local lookDir = Vector3.new(0, 0, 1)
	if triggerCharacter and triggerCharacter.PrimaryPart then
		local dirToTarget = (triggerCharacter.PrimaryPart.Position - trapPos)
		dirToTarget = Vector3.new(dirToTarget.X, 0, dirToTarget.Z) -- Flatten Y
		if dirToTarget.Magnitude > 0.1 then
			lookDir = dirToTarget.Unit
		end
	end
	
	-- Destroy the trap marker on all clients
	if service then
		service:BroadcastVFX(player, "All", "Kon", {}, "destroyTrap")
	end

	-- Spawn Kon at trap position (same proven createKon visual as normal ability)
	if service then
		service:BroadcastVFX(player, "All", "Kon", {
			position = { X = trapPos.X, Y = trapPos.Y, Z = trapPos.Z },
			lookVector = { X = lookDir.X, Y = lookDir.Y, Z = lookDir.Z },
			surfaceNormal = { X = 0, Y = 1, Z = 0 },
		}, "createKon")
	end
	
	-- Terrain destruction at trap location
	local kitData = KitConfig.getKit("Aki")
	local destructionLevel = kitData and kitData.Ability and kitData.Ability.Destruction
	if destructionLevel then
		local radiusMap = {
			Small = 6,
			Big = 10,
			Huge = 15,
			Mega = 22,
		}
		local radius = radiusMap[destructionLevel] or 10
		
		task.spawn(function()
			VoxManager:explode(trapPos, radius, {
				voxelSize = 2,
				debris = true,
				debrisAmount = 8,
			})
		end)
	end
	
	-- BITE: delayed to match Kon bite animation timing
	-- Only targets still in radius at bite time get hit
	task.delay(TRAP_BITE_DELAY, function()
		local character = self._ctx.character or (player and player.Character)
		local biteTargets = Hitbox.GetCharactersInRadius(trapPos, TRAP_TRIGGER_RADIUS, player)
		
		for _, targetChar in ipairs(biteTargets) do
			if targetChar == character then continue end -- Skip Aki
			
			local humanoid = targetChar:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid and humanoid.Health > 0 then
				-- Apply trap damage on bite
				applyDamage(self, targetChar, TRAP_DAMAGE, "Aki_KonTrap")
				
				-- Apply KonSlow status effect
				applyKonSlow(self, targetChar)
				
				-- Fling target upward on bite
				local root = targetChar.PrimaryPart
					or targetChar:FindFirstChild("HumanoidRootPart")
					or targetChar:FindFirstChild("Root")
				if root then
					root.AssemblyLinearVelocity = Vector3.new(
						root.AssemblyLinearVelocity.X * 0.2,
						0,
						root.AssemblyLinearVelocity.Z * 0.2
					)
					root.AssemblyLinearVelocity += Vector3.new(0, TRAP_LAUNCH_UPWARD, 0)
				end
			end
		end
	end)
	
	-- Reset trap state (trap is consumed — can be placed again)
	self._trapPosition = nil
	self._trapPlaced = false
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

local function validateTargetPosition(player, character, targetPos)
	if not character then
		return false, "NoCharacter"
	end

	local playerPos = nil
	
	local api = getHitDetectionAPI()
	if api then
		local currentTime = workspace:GetServerTimeNow()
		playerPos = api:GetPositionAtTime(player, currentTime)
	end
	
	if not playerPos then
		local root = character.PrimaryPart 
			or character:FindFirstChild("Root") 
			or character:FindFirstChild("HumanoidRootPart")
		if root then
			playerPos = root.Position
		end
	end
	
	if not playerPos then
		return false, "NoPosition"
	end

	local distance = (targetPos - playerPos).Magnitude
	if distance > MAX_RANGE then
		return false, "OutOfRange"
	end

	return true, nil
end

local function validateHitList(hits)
	if type(hits) ~= "table" then
		return false, "InvalidHits"
	end

	if #hits > MAX_HITS_PER_BITE then
		return false, "TooManyHits"
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- Ability: Kon
--------------------------------------------------------------------------------

function Kit:OnAbility(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end

	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	local service = self._ctx.service

	if not character then
		return false
	end

	clientData = clientData or {}
	local action = clientData.action

	------------------------------------------------------------------------
	-- TRAP VARIANT ACTIONS
	------------------------------------------------------------------------

	-- Place Trap
	if action == "placeTrap" then
		-- Validate: can only place one trap per match
		if self._trapPlaced then
			return false
		end
		
		local posData = clientData.position
		if not posData then return false end
		
		local trapPos = Vector3.new(
			posData.X or 0,
			posData.Y or 0,
			posData.Z or 0
		)
		
		-- Validate placement position (must be near player)
		local root = character.PrimaryPart
			or character:FindFirstChild("Root")
			or character:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		
		local distFromPlayer = (trapPos - root.Position).Magnitude
		if distFromPlayer > TRAP_PLACEMENT_MAX_DIST then
			return false
		end
		
		-- Place the trap (no cooldown!)
		self._trapPlaced = true
		self._trapActive = true
		self._trapPosition = trapPos
		
		-- VFX is handled client-side via VFXRep:Fire("All") for responsiveness.
		-- Server only manages state and proximity detection.
		
		-- Immediately check if any enemy is already in range
		local character = self._ctx.character or player.Character
		local immediateTargets = Hitbox.GetCharactersInRadius(trapPos, TRAP_TRIGGER_RADIUS, player)
		for _, targetChar in ipairs(immediateTargets) do
			if targetChar == character then continue end
			local humanoid = targetChar:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid and humanoid.Health > 0 then
				-- Enemy already in range — trigger the trap now
				self:_triggerTrap(targetChar)
				return false
			end
		end
		
		-- No enemy in range — start proximity detection loop
		self:_startTrapProximityLoop()
		
		return false -- Don't end ability, no cooldown
	end

	-- Self-Launch from trap
	if action == "selfLaunch" then
		if not self._trapActive or not self._trapPosition then
			return false
		end
		
		-- Validate Aki is near the trap
		local root = character.PrimaryPart
			or character:FindFirstChild("Root")
			or character:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		
		local distToTrap = (root.Position - self._trapPosition).Magnitude
		if distToTrap > TRAP_SELF_LAUNCH_RADIUS * 1.5 then -- Allow some buffer
			return false
		end
		
		-- Clean up trap state (no damage to Aki, VFX handled client-side)
		if self._trapProximityConn then
			self._trapProximityConn:Disconnect()
			self._trapProximityConn = nil
		end
		self._trapActive = false
		self._trapPosition = nil
		self._trapPlaced = false
		
		-- Don't start cooldown for self-launch
		return false
	end

	------------------------------------------------------------------------
	-- MAIN VARIANT ACTIONS (existing Kon behavior)
	------------------------------------------------------------------------

	-- Request Kon Spawn
	if action == "requestKonSpawn" then
		local targetPosData = clientData.targetPosition
		if not targetPosData then
			return false
		end

		local targetPos = Vector3.new(
			targetPosData.X or 0,
			targetPosData.Y or 0,
			targetPosData.Z or 0
		)

		local valid, reason = validateTargetPosition(player, character, targetPos)
		if not valid then
			return false
		end

		-- Start cooldown
		if service then
			service:StartCooldown(player)
		end

		-- Store for bite validation
		self._pendingSpawn = {
			position = targetPos,
			time = os.clock(),
		}

		return false
	end

	-- Kon Bite
	if action == "konBite" then
		local hits = clientData.hits
		local bitePosData = clientData.bitePosition

		if not bitePosData then
			return true
		end

		local bitePos = Vector3.new(
			bitePosData.X or 0,
			bitePosData.Y or 0,
			bitePosData.Z or 0
		)

		if hits ~= nil then
			local valid = validateHitList(hits)
			if not valid then
				return true
			end
		end

		-- Validate bite position
		if self._pendingSpawn then
			local spawnDist = (bitePos - self._pendingSpawn.position).Magnitude
			if spawnDist > 20 then
				-- Position mismatch, but don't reject
			end
		end

		-- Server-authoritative damage check at bite position.
		local targets = Hitbox.GetCharactersInRadius(bitePos, BITE_RADIUS, player)
		local appliedHits = 0
		for _, targetCharacter in ipairs(targets) do
			if appliedHits >= MAX_HITS_PER_BITE then
				break
			end

			if targetCharacter and targetCharacter ~= character then
				local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid", true)
				if humanoid and humanoid.Health > 0 then
					humanoid:TakeDamage(BITE_DAMAGE)
					appliedHits += 1
				end
			end
		end

		-- Terrain destruction at bite location
		local kitData = KitConfig.getKit("Aki")
		local destructionLevel = kitData and kitData.Ability and kitData.Ability.Destruction
		
		if destructionLevel then
			local radiusMap = {
				Small = 6,
				Big = 10,
				Huge = 15,
				Mega = 22,
			}
			local radius = radiusMap[destructionLevel] or 10
			
			task.spawn(function()
				local success = VoxManager:explode(bitePos, radius, {
					voxelSize = 2,
					debris = true,
					debrisAmount = 8,
				})
			end)
		end

		self._pendingSpawn = nil
		return true
	end

	-- Unknown action
	if service then
		service:StartCooldown(player)
	end

	return true
end

--------------------------------------------------------------------------------
-- Ultimate
--------------------------------------------------------------------------------

function Kit:OnUltimate(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	return true
end

return Kit
