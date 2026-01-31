--[[
	Aki Client Kit
	
	Ability: Kon - Summon devil that rushes to target location and bites
	
	Flow:
	1. Player presses E
	2. Client raycasts for target location
	3. Client plays viewmodel animation + VFXRep for caster effects
	4. Client sends location to server for validation
	5. Server validates, starts cooldown
	6. Client fires VFXRep to spawn Kon for ALL clients
	7. On bite timing: Caster does hitbox, applies knockback, sends hits to server
	8. Server applies damage
	9. Cleanup
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local Hitbox = require(Locations.Shared.Util:WaitForChild("Hitbox"))
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Debug Logging
--------------------------------------------------------------------------------

local DEBUG = true

local function log(...)
	if DEBUG then
		print("[Aki Client]", ...)
	end
end

local function logTable(label, tbl)
	if not DEBUG then return end
	print("[Aki Client]", label, ":")
	if type(tbl) ~= "table" then
		print("  (not a table):", tbl)
		return
	end
	for k, v in pairs(tbl) do
		if typeof(v) == "Vector3" then
			print(string.format("  %s = Vector3(%.2f, %.2f, %.2f)", tostring(k), v.X, v.Y, v.Z))
		elseif typeof(v) == "CFrame" then
			print(string.format("  %s = CFrame at (%.2f, %.2f, %.2f)", tostring(k), v.Position.X, v.Position.Y, v.Position.Z))
		elseif typeof(v) == "Instance" then
			print(string.format("  %s = %s (%s)", tostring(k), v.Name, v.ClassName))
		else
			print(string.format("  %s = %s", tostring(k), tostring(v)))
		end
	end
end

--------------------------------------------------------------------------------
-- TIMING CONSTANTS (Adjust these to match your animations)
--------------------------------------------------------------------------------

local TIMING = {
	-- Time from ability start until Kon spawns at target location
	KON_SPAWN_DELAY = 0.5,
	
	-- Time from Kon spawn until bite hitbox activates
	BITE_DELAY = 0.8,
	
	-- Time to keep Kon visible after bite before starting despawn
	LINGER_AFTER_BITE = 0.5,
	
	-- Total time before cleanup and weapon restore
	TOTAL_ABILITY_DURATION = 2.5,
}

--------------------------------------------------------------------------------
-- ABILITY CONSTANTS
--------------------------------------------------------------------------------

local MAX_RANGE = 125
local BITE_RADIUS = 12
local BITE_KNOCKBACK_PRESET = "Blast"

-- Viewmodel animation name
local VM_ANIM_NAME = "Kon"

--------------------------------------------------------------------------------
-- Raycast Setup
--------------------------------------------------------------------------------

local TargetParams = RaycastParams.new()
TargetParams.FilterType = Enum.RaycastFilterType.Exclude

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local Aki = {}
Aki.__index = Aki

Aki.Ability = {}
Aki.Ultimate = {}

Aki._ctx = nil
Aki._connections = {}
Aki._activeAbility = nil  -- Track active ability for cancellation

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getCameraCF()
	return Workspace.CurrentCamera.CFrame
end

--[[
	Raycast from camera to find target location for Kon spawn
	Returns CFrame oriented to surface normal, or nil if no valid target
]]
local function getTargetLocation(character: Model, maxDistance: number): CFrame?
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not root then 
		log("getTargetLocation: No root part found")
		return nil 
	end

	-- Update raycast filter to exclude character and effects
	local filterList = { character }
	local effectsFolder = Workspace:FindFirstChild("Effects")
	if effectsFolder then
		table.insert(filterList, effectsFolder)
	end
	TargetParams.FilterDescendantsInstances = filterList

	local camCF = getCameraCF()
	local rayOrigin = camCF.Position
	local rayDirection = camCF.LookVector * maxDistance

	log(string.format("Raycasting from (%.1f, %.1f, %.1f) direction (%.2f, %.2f, %.2f) range %d",
		rayOrigin.X, rayOrigin.Y, rayOrigin.Z,
		camCF.LookVector.X, camCF.LookVector.Y, camCF.LookVector.Z,
		maxDistance))

	local result = Workspace:Raycast(rayOrigin, rayDirection, TargetParams)
	local hitPos

	if result and result.Instance and result.Instance.Transparency ~= 1 then
		hitPos = result.Position
		log("Direct hit on:", result.Instance.Name, "at", hitPos)
	else
		-- No direct hit - try to find ground below max range point
		hitPos = camCF.Position + camCF.LookVector * maxDistance
		log("No direct hit, checking ground at max range:", hitPos)

		result = Workspace:Raycast(hitPos + Vector3.new(0, 5, 0), Vector3.yAxis * -100, TargetParams)
		if result then
			hitPos = result.Position
			log("Found ground at:", hitPos)
		else
			log("No valid target location found")
			return nil
		end
	end

	-- Build CFrame oriented to surface
	if result then
		local hitPosition = result.Position
		local normal = result.Normal
		local isGround = normal.Y > 0.5

		log(string.format("Surface normal: (%.2f, %.2f, %.2f) isGround: %s", 
			normal.X, normal.Y, normal.Z, tostring(isGround)))

		if isGround then
			-- Ground hit: Orient Kon facing away from camera
			local camPos = Vector3.new(camCF.Position.X, hitPosition.Y, camCF.Position.Z)
			local dirRelToCam = CFrame.lookAt(camPos, hitPosition).LookVector
			local finalCF = CFrame.lookAt(hitPosition, hitPosition + dirRelToCam)
			log("Ground spawn CFrame:", finalCF.Position)
			return finalCF
		else
			-- Wall hit: Orient Kon facing out from wall
			local finalCF = CFrame.new(hitPosition, hitPosition + normal)
			log("Wall spawn CFrame:", finalCF.Position)
			return finalCF
		end
	end

	return CFrame.new(hitPos)
end

--------------------------------------------------------------------------------
-- Ability State Management
--------------------------------------------------------------------------------

local function createAbilityState()
	return {
		active = true,
		cancelled = false,
		konSpawned = false,
		biteExecuted = false,
		targetCFrame = nil,
		startTime = os.clock(),
	}
end

--------------------------------------------------------------------------------
-- Ability: Kon
--------------------------------------------------------------------------------

function Aki.Ability:OnStart(abilityRequest)
	log("========== ABILITY START ==========")
	logTable("abilityRequest", {
		kitId = abilityRequest.kitId,
		abilityType = abilityRequest.abilityType,
		player = abilityRequest.player,
		character = abilityRequest.character,
		humanoidRootPart = abilityRequest.humanoidRootPart,
		timestamp = abilityRequest.timestamp,
	})

	local hrp = abilityRequest.humanoidRootPart
	local character = abilityRequest.character
	if not hrp or not character then 
		warn("[Aki Client] No HRP or character!")
		return 
	end

	local kitController = ServiceRegistry:GetController("Kit")

	-- Check if already using ability
	if kitController:IsAbilityActive() then
		log("Ability already active, ignoring")
		return
	end

	-- Check cooldown
	local cooldownRemaining = abilityRequest.GetCooldownRemaining()
	log("Cooldown check - IsOnCooldown:", abilityRequest.IsOnCooldown(), "remaining:", cooldownRemaining)
	if abilityRequest.IsOnCooldown() then
		log("BLOCKED - Ability on cooldown, remaining:", cooldownRemaining)
		return
	end
	log("Cooldown check PASSED")

	-- Get target location via raycast
	local targetCFrame = getTargetLocation(character, MAX_RANGE)
	if not targetCFrame then
		warn("[Aki Client] Could not find valid target location!")
		return
	end

	log("Target location found:", targetCFrame.Position)

	-- Start ability (holsters weapon, switches to fists viewmodel)
	local ctx = abilityRequest.StartAbility()
	local unlock = kitController:LockWeaponSwitch()

	log("Ability started, weapon holstered")

	-- Create ability state for tracking
	local abilityState = createAbilityState()
	abilityState.targetCFrame = targetCFrame
	Aki._activeAbility = abilityState

	-- Play viewmodel animation
	local viewmodelAnimator = ctx.viewmodelAnimator
	local viewmodelController = abilityRequest.viewmodelController
	local Viewmodelrig = viewmodelController and viewmodelController:GetActiveRig()
	local vmAnimation = nil
	
	if viewmodelAnimator then
		vmAnimation = viewmodelAnimator:PlayKitAnimation(VM_ANIM_NAME, {
			priority = Enum.AnimationPriority.Action4,
			stopOthers = true,
		})
		if vmAnimation then
			log("Viewmodel animation started:", VM_ANIM_NAME)
		else
			log("Viewmodel animation not found:", VM_ANIM_NAME)
		end
	end

	-- Fire VFXRep for caster viewmodel effects
	VFXRep:Fire("Me", { Module = "Kon", Function = "User" }, {
		ViewModel = Viewmodelrig,
		forceAction = "start",
	})

	-- Send target location to server for validation
	log("Sending to server for validation...")
	logTable("Sending data", {
		action = "requestKonSpawn",
		targetPosition = targetCFrame.Position,
		targetLookVector = targetCFrame.LookVector,
	})

	abilityRequest.Send({
		action = "requestKonSpawn",
		targetPosition = { X = targetCFrame.Position.X, Y = targetCFrame.Position.Y, Z = targetCFrame.Position.Z },
		targetLookVector = { X = targetCFrame.LookVector.X, Y = targetCFrame.LookVector.Y, Z = targetCFrame.LookVector.Z },
	})

	-- Main ability sequence using task.delay
	task.spawn(function()
		local startTime = os.clock()
		
		----------------------------------------------------------------
		-- Phase 1: Wait for Kon spawn timing
		----------------------------------------------------------------
		task.wait(TIMING.KON_SPAWN_DELAY)
		
		if not abilityState.active or abilityState.cancelled then
			log("Ability was cancelled before Kon spawn")
			unlock()
			return
		end

		log("========== KON SPAWN ==========")
		log("Spawning Kon at:", targetCFrame.Position)
		abilityState.konSpawned = true
		
		-- Fire VFXRep to spawn Kon for ALL clients
		VFXRep:Fire("All", { Module = "Kon", Function = "createKon" }, {
			position = { X = targetCFrame.Position.X, Y = targetCFrame.Position.Y, Z = targetCFrame.Position.Z },
			lookVector = { X = targetCFrame.LookVector.X, Y = targetCFrame.LookVector.Y, Z = targetCFrame.LookVector.Z },
		})

		----------------------------------------------------------------
		-- Phase 2: Wait for bite timing
		----------------------------------------------------------------
		task.wait(TIMING.BITE_DELAY)
		
		if not abilityState.active or abilityState.cancelled then
			log("Ability was cancelled before bite")
			-- Destroy Kon early
			VFXRep:Fire("All", { Module = "Kon", Function = "destroyKon" }, {})
			unlock()
			return
		end

		log("========== BITE EXECUTION ==========")
		abilityState.biteExecuted = true

		-- Fire VFXRep for caster bite screen effects
		VFXRep:Fire("Me", { Module = "Kon", Function = "User" }, {
			ViewModel = Viewmodelrig,
			forceAction = "bite",
		})

		-- Get hitbox at Kon's position (CASTER ONLY)
		local bitePosition = targetCFrame.Position
		log(string.format("Performing hitbox at (%.1f, %.1f, %.1f) radius %d",
			bitePosition.X, bitePosition.Y, bitePosition.Z, BITE_RADIUS))

		local targets = Hitbox.GetCharactersInSphere(bitePosition, BITE_RADIUS, {
			Exclude = abilityRequest.player,
			Visualize = DEBUG,
			VisualizeDuration = 1.0,
			VisualizeColor = Color3.fromRGB(255, 50, 50),
		})

		log("Hitbox found", #targets, "targets:")
		for i, char in ipairs(targets) do
			log(string.format("  [%d] %s", i, char.Name))
		end

		-- Apply knockback to each target (CASTER ONLY)
		local knockbackController = ServiceRegistry:GetController("Knockback")
		local hitList = {}

		for _, targetChar in ipairs(targets) do
			log("Applying knockback to:", targetChar.Name, "preset:", BITE_KNOCKBACK_PRESET)
			
			if knockbackController then
				knockbackController:ApplyKnockbackPreset(targetChar, BITE_KNOCKBACK_PRESET, bitePosition)
			else
				warn("[Aki Client] KnockbackController not found!")
			end

			-- Build hit list for server
			local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
			table.insert(hitList, {
				characterName = targetChar.Name,
				playerId = targetPlayer and targetPlayer.UserId or nil,
				isDummy = targetPlayer == nil,
			})
		end

		logTable("Hit list for server", hitList)

		-- Send hits to server for damage
		log("Sending", #hitList, "hits to server for damage validation")
		abilityRequest.Send({
			action = "konBite",
			hits = hitList,
			bitePosition = { X = bitePosition.X, Y = bitePosition.Y, Z = bitePosition.Z },
		})

		----------------------------------------------------------------
		-- Phase 3: Wait for total duration, then cleanup
		----------------------------------------------------------------
		local elapsedTime = os.clock() - startTime
		local remainingTime = TIMING.TOTAL_ABILITY_DURATION - elapsedTime
		
		if remainingTime > 0 then
			task.wait(remainingTime)
		end

		log("========== CLEANUP ==========")
		
		-- Fire VFXRep for caster stop effects
		VFXRep:Fire("Me", { Module = "Kon", Function = "User" }, {
			ViewModel = Viewmodelrig,
			forceAction = "stop",
		})
		
		abilityState.active = false
		Aki._activeAbility = nil

		-- Stop viewmodel animation if still playing
		if vmAnimation and vmAnimation.IsPlaying then
			vmAnimation:Stop(0.2)
		end

		-- Unlock weapon switch and restore weapon
		unlock()
		kitController:_unholsterWeapon()
		
		log("Ability complete, weapon restored")
		log("========== ABILITY END ==========")
	end)
end

function Aki.Ability:OnEnded(abilityRequest)
	log("Ability:OnEnded called")
end

function Aki.Ability:OnInterrupt(abilityRequest, reason)
	log("Ability:OnInterrupt called, reason:", reason)
	
	if Aki._activeAbility then
		Aki._activeAbility.cancelled = true
		Aki._activeAbility.active = false
		
		-- Destroy Kon via VFXRep
		VFXRep:Fire("All", { Module = "Kon", Function = "destroyKon" }, {})
		
		Aki._activeAbility = nil
		log("Active ability cancelled and cleaned up")
	end
end

--------------------------------------------------------------------------------
-- Ultimate (placeholder)
--------------------------------------------------------------------------------

function Aki.Ultimate:OnStart(abilityRequest)
	log("Ultimate:OnStart called (not implemented)")
	abilityRequest.Send()
end

function Aki.Ultimate:OnEnded(abilityRequest)
	log("Ultimate:OnEnded called")
end

function Aki.Ultimate:OnInterrupt(abilityRequest, reason)
	log("Ultimate:OnInterrupt called, reason:", reason)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Aki.new(ctx)
	log("Aki.new() called")
	logTable("Context", ctx)
	
	local self = setmetatable({}, Aki)
	self._ctx = ctx
	self._connections = {}
	self.Ability = Aki.Ability
	self.Ultimate = Aki.Ultimate
	return self
end

function Aki:OnEquip(ctx)
	log("OnEquip called")
	self._ctx = ctx
end

function Aki:OnUnequip(reason)
	log("OnUnequip called, reason:", reason)
	
	-- Disconnect all connections
	for key, conn in pairs(self._connections) do
		if typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
		self._connections[key] = nil
	end
	
	-- Cancel any active ability
	if Aki._activeAbility then
		Aki._activeAbility.cancelled = true
		Aki._activeAbility.active = false
		
		-- Destroy Kon via VFXRep
		VFXRep:Fire("All", { Module = "Kon", Function = "destroyKon" }, {})
		
		Aki._activeAbility = nil
	end
end

function Aki:Destroy()
	log("Destroy called")
	self:OnUnequip("Destroy")
end

return Aki
