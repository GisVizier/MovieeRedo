--[[
	Aki Server Kit
	
	Ability: KON - Two variants:
	
	TRAP VARIANT (E while crouching/sliding):
	- Places a hidden Kon trap at aimed position (35 stud range)
	- Triggers when ANY character enters 9.5 stud radius (enemies, dummies, or Aki)
	- Unified _triggerTrap handles everything:
	  • Broadcasts createKon VFX for all clients
	  • If Aki is in range → broadcasts selfLaunch VFX to Aki (uncrouch + launch up)
	  • After bite delay → damages enemies + KonSlow (Aki NOT damaged)
	- 1 per kit equip, no cooldown on placement
	- Trap destroyed when kit is destroyed/unequipped
	
	MAIN VARIANT (E while standing):
	- Existing Kon behavior (requestKonSpawn → konBite)
	
	Server responsibilities:
	1. Validate trap placement position
	2. Manage trap state (_trapPlaced, _trapPosition, _trapActive)
	3. Run proximity detection loop (includes Aki)
	4. Unified _triggerTrap: VFX + self-launch + damage + KonSlow + VoxelDestruction
	5. Destroy trap on kit destroy/unequip
	6. Validate konBite hits for main variant
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local VoxelDestruction = require(ReplicatedStorage.Shared.Modules.VoxelDestruction)
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
local TRAP_PLACEMENT_MAX_DIST = 40   -- Max distance from player for placement validation (35 stud aim range + tolerance)
local KONSLOW_DURATION = 5

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
	-- Reset trap state so the ability is available again on re-equip / area transition
	self._trapPlaced = false
	self._trapActive = false
	self._trapPosition = nil
	if self._trapProximityConn then
		self._trapProximityConn:Disconnect()
		self._trapProximityConn = nil
	end
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
	
	-- Always use WeaponService:ApplyDamageToCharacter — it handles both players
	-- AND dummies via CombatService:GetPlayerByCharacter internally.
	local weaponService = getWeaponService(self)
	if weaponService then
		local root = self._ctx.character and self._ctx.character.PrimaryPart
		local sourcePos = root and root.Position or nil
		local hitPos = (targetCharacter.PrimaryPart and targetCharacter.PrimaryPart.Position)
			or (targetCharacter:FindFirstChild("Root") and targetCharacter.Root.Position)
			or nil
		
		weaponService:ApplyDamageToCharacter(
			targetCharacter,
			damage,
			player,
			false, -- not headshot
			weaponId or "Aki_Kon",
			sourcePos,
			hitPos
		)
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
		
		-- Detect ALL characters in radius — including Aki (no exclusion)
		local radiusTargets = Hitbox.GetCharactersInRadius(self._trapPosition, TRAP_TRIGGER_RADIUS)
		local sphereTargets = Hitbox.GetCharactersInSphere(self._trapPosition, TRAP_TRIGGER_RADIUS, {})
		
		-- Union both results
		local seen = {}
		local targets = {}
		for _, t in ipairs(radiusTargets) do
			if not seen[t] then seen[t] = true; table.insert(targets, t) end
		end
		for _, t in ipairs(sphereTargets) do
			if not seen[t] then seen[t] = true; table.insert(targets, t) end
		end
		
		for _, targetCharacter in ipairs(targets) do
			local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid and humanoid.Health > 0 then
				self:_triggerTrap()
				return -- Only triggers once
			end
		end
	end)
end

--[[ Unified trap trigger — handles BOTH enemy damage AND Aki self-launch.
     Called by the proximity loop when ANY character enters the trap radius.
     - Broadcasts createKon VFX for all clients
     - If Aki is in radius → broadcasts selfLaunch VFX to Aki's client
     - After bite delay → damages enemies + KonSlow (Aki is NOT damaged)
     - VoxelDestruction at trap position ]]
function Kit:_triggerTrap()
	if not self._trapActive then return end
	
	local trapPos = self._trapPosition
	if not trapPos then return end
	
	local player = self._ctx.player
	local myChar = self._ctx.character or player.Character
	local service = self._ctx.service
	
	-- Stop proximity loop
	if self._trapProximityConn then
		self._trapProximityConn:Disconnect()
		self._trapProximityConn = nil
	end
	
	self._trapActive = false
	
	-- Find ALL characters in radius (including Aki) for look direction + self-launch check
	local allInRange = Hitbox.GetCharactersInRadius(trapPos, TRAP_TRIGGER_RADIUS)
	local sphereInRange = Hitbox.GetCharactersInSphere(trapPos, TRAP_TRIGGER_RADIUS, {})
	local seen = {}
	local targets = {}
	for _, t in ipairs(allInRange) do
		if not seen[t] then seen[t] = true; table.insert(targets, t) end
	end
	for _, t in ipairs(sphereInRange) do
		if not seen[t] then seen[t] = true; table.insert(targets, t) end
	end
	
	-- Determine look direction (face toward first non-Aki target, fallback to Aki direction)
	local lookDir = Vector3.new(0, 0, 1)
	local akiInRange = false
	for _, char in ipairs(targets) do
		if char == myChar then
			akiInRange = true
		elseif char.PrimaryPart or char:FindFirstChild("Root") then
			local part = char.PrimaryPart or char:FindFirstChild("Root")
			local dirToTarget = (part.Position - trapPos)
			dirToTarget = Vector3.new(dirToTarget.X, 0, dirToTarget.Z)
			if dirToTarget.Magnitude > 0.1 then
				lookDir = dirToTarget.Unit
			end
		end
	end
	
	-- Also check Aki via direct distance (in case hitbox missed due to timing)
	if not akiInRange and myChar then
		local akiRoot = myChar.PrimaryPart or myChar:FindFirstChild("Root") or myChar:FindFirstChild("HumanoidRootPart")
		if akiRoot and (akiRoot.Position - trapPos).Magnitude <= TRAP_TRIGGER_RADIUS * 1.5 then
			akiInRange = true
		end
	end
	
	-- Broadcast VFX: destroy trap marker + spawn Kon
	if service then
		service:BroadcastVFX(player, "All", "Kon", {}, "destroyTrap")
		service:BroadcastVFX(player, "All", "Kon", {
			position = { X = trapPos.X, Y = trapPos.Y, Z = trapPos.Z },
			lookVector = { X = lookDir.X, Y = lookDir.Y, Z = lookDir.Z },
			surfaceNormal = { X = 0, Y = 1, Z = 0 },
		}, "createKon")
	end
	
	-- Self-launch Aki IMMEDIATELY if in range (no delay — launch happens on trigger)
	if akiInRange and service then
		service:BroadcastVFX(player, "Me", "Kon", {
			position = { X = trapPos.X, Y = trapPos.Y, Z = trapPos.Z },
		}, "selfLaunch")
	end
	
	-- Terrain destruction at trap location (server-authoritative VoxelDestruction)
	task.spawn(function()
		local hitbox = Instance.new("Part")
		hitbox.Size = Vector3.new(10, 10, 10) -- 5 stud radius
		hitbox.Position = trapPos
		hitbox.Shape = Enum.PartType.Ball
		hitbox.Anchored = true
		hitbox.CanCollide = false
		hitbox.CanQuery = false
		hitbox.Transparency = 1
		hitbox.Parent = workspace

		VoxelDestruction.Destroy(hitbox, nil, 4, 4, nil)

		task.delay(2, function()
			if hitbox and hitbox.Parent then
				hitbox:Destroy()
			end
		end)
	end)
	
	-- BITE: delayed to match Kon bite animation timing
	-- Damage enemies only (Aki gets self-launched, not damaged)
	task.delay(TRAP_BITE_DELAY, function()
		-- Exclude Aki from damage detection
		local radiusBite = Hitbox.GetCharactersInRadius(trapPos, TRAP_TRIGGER_RADIUS, player)
		local sphereBite = Hitbox.GetCharactersInSphere(trapPos, TRAP_TRIGGER_RADIUS, {
			Exclude = player,
		})
		
		local bSeen = {}
		local biteTargets = {}
		for _, t in ipairs(radiusBite) do
			if not bSeen[t] then bSeen[t] = true; table.insert(biteTargets, t) end
		end
		for _, t in ipairs(sphereBite) do
			if not bSeen[t] then bSeen[t] = true; table.insert(biteTargets, t) end
		end
		
		local character = self._ctx.character or (player and player.Character)
		for _, targetChar in ipairs(biteTargets) do
			if targetChar == character then continue end -- Skip Aki (no self-damage)
			
			local humanoid = targetChar:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid and humanoid.Health > 0 then
				applyDamage(self, targetChar, TRAP_DAMAGE, "Aki_KonTrap")
				applyKonSlow(self, targetChar)
				
				-- Force uncrouch/unslide hit players
				local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
				if targetPlayer then
					targetPlayer:SetAttribute("ForceUncrouch", true)
					targetPlayer:SetAttribute("BlockCrouchWhileAbility", true)
					targetPlayer:SetAttribute("BlockSlideWhileAbility", true)
					task.delay(1.5, function()
						if targetPlayer and targetPlayer.Parent then
							targetPlayer:SetAttribute("ForceUncrouch", nil)
							targetPlayer:SetAttribute("BlockCrouchWhileAbility", nil)
							targetPlayer:SetAttribute("BlockSlideWhileAbility", nil)
						end
					end)
				end
			end
		end
	end)
	
	-- Reset trap state (trap consumed — stays used, cannot re-place until kit reset)
	self._trapPosition = nil
	-- NOTE: _trapPlaced stays TRUE — one-time ability per kit equip
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
		-- Validate: can only place one trap per kit equip
		if self._trapPlaced then return false end
		
		local posData = clientData.position
		if not posData then return false end
		
		local trapPos = Vector3.new(
			posData.X or 0,
			posData.Y or 0,
			posData.Z or 0
		)
		
		-- Validate placement position (must be near player)
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
		if not playerPos then return false end
		
		local distFromPlayer = (trapPos - playerPos).Magnitude
		if distFromPlayer > TRAP_PLACEMENT_MAX_DIST then return false end
		
		-- Place the trap
		self._trapPlaced = true
		self._trapActive = true
		self._trapPosition = trapPos
		
		-- Immediate detection: check ALL characters including Aki (no exclusion)
		local radiusTargets = Hitbox.GetCharactersInRadius(trapPos, TRAP_TRIGGER_RADIUS)
		local sphereTargets = Hitbox.GetCharactersInSphere(trapPos, TRAP_TRIGGER_RADIUS, {})
		
		local seen = {}
		local immediateTargets = {}
		for _, t in ipairs(radiusTargets) do
			if not seen[t] then seen[t] = true; table.insert(immediateTargets, t) end
		end
		for _, t in ipairs(sphereTargets) do
			if not seen[t] then seen[t] = true; table.insert(immediateTargets, t) end
		end
		
		for _, targetChar in ipairs(immediateTargets) do
			local humanoid = targetChar:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid and humanoid.Health > 0 then
				-- Someone is already in range — trigger immediately
				self:_triggerTrap()
				return false
			end
		end
		
		-- No one in range — start proximity detection loop
		self:_startTrapProximityLoop()
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
					applyDamage(self, targetCharacter, BITE_DAMAGE, "Aki_Kon")
					appliedHits += 1
				end
			end
		end

		-- Terrain destruction at bite location (server-authoritative VoxelDestruction)
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
				local hitbox = Instance.new("Part")
				hitbox.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
				hitbox.Position = bitePos
				hitbox.Shape = Enum.PartType.Ball
				hitbox.Anchored = true
				hitbox.CanCollide = false
				hitbox.CanQuery = false
				hitbox.Transparency = 1
				hitbox.Parent = workspace

				VoxelDestruction.Destroy(hitbox, nil, 2, 8, nil)

				task.delay(2, function()
					if hitbox and hitbox.Parent then
						hitbox:Destroy()
					end
				end)
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
