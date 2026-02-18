--[[
	Mob Client Kit
	
	Ability: WALL RISE
	
	Creates a protective wall from the ground that:
	- Sends players into the air with knockback on spawn
	- Blocks projectiles (invisible to bullets)
	- Breaks from destruction abilities (Blue, Red, etc.)
	- Wall stays active until:
	  - New wall is created (replaces old)
	  - Wall is destroyed by enemy ability
	  - Player pushes wall (after 3s, looking at it)
	
	Animation Markers (MobAbilityStart):
	- chargeaem: Arm VFX start
	- charge: Get target location, show charge VFX at pivot
	- start: Spawn wall on server
	- _finish: Cleanup animation, unholster weapon
	
	Second Use (TODO):
	- After 3s, if looking at wall and pressing ability → push wall forward
	- All pieces shoot forward with gravity, knockback + destruction on impact
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local Hitbox = require(Locations.Shared.Util:WaitForChild("Hitbox"))

-- VFX replication (for future VFX calls)
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local WALL_CONFIG = {
	-- Placement
	MAX_PLACEMENT_DISTANCE = 75,      -- Max distance to place wall
	RAYCAST_DOWN_DISTANCE = 100,      -- How far to raycast down to find floor
	
	-- Grace period - time after wall spawn before cooldown kicks in
	GRACE_PERIOD = 3,                 -- Seconds to use second ability before cooldown
	PUSH_CHECK_DISTANCE = 100,        -- Max distance to detect if looking at wall
	
	-- Knockback on spawn (applied by client)
	KNOCKBACK_RADIUS = 12.5,          -- Radius for knockback hitbox
	KNOCKBACK_UPWARD = 120,           -- Upward velocity
	KNOCKBACK_OUTWARD = 30,           -- Outward velocity from wall center
}

--------------------------------------------------------------------------------
-- Animation Configuration
--------------------------------------------------------------------------------

local ANIM_NAME = "MobAbilityStart"

--------------------------------------------------------------------------------
-- Knockback Helper
--------------------------------------------------------------------------------

local function applyWallKnockback(pivotPosition, casterPlayer)
	local knockbackController = ServiceRegistry:GetController("Knockback")
	if not knockbackController then return end
	
	-- Get all characters in knockback radius (including self)
	local targets = Hitbox.GetCharactersInSphere(pivotPosition, WALL_CONFIG.KNOCKBACK_RADIUS, {
		-- Don't exclude anyone - hit everyone including caster
	})
	
	for _, targetChar in ipairs(targets) do
		local targetRoot = targetChar:FindFirstChild("Root") 
			or targetChar:FindFirstChild("HumanoidRootPart")
			or targetChar.PrimaryPart
		
		if targetRoot then
			-- Calculate knockback direction (away from wall center)
			local awayDir = (targetRoot.Position - pivotPosition)
			awayDir = Vector3.new(awayDir.X, 0, awayDir.Z) -- Horizontal only
			if awayDir.Magnitude > 0.1 then
				awayDir = awayDir.Unit
			else
				awayDir = Vector3.new(1, 0, 0)
			end
			
			local knockbackVelocity = (awayDir * WALL_CONFIG.KNOCKBACK_OUTWARD) 
				+ Vector3.new(0, WALL_CONFIG.KNOCKBACK_UPWARD, 0)
			
			-- Apply knockback
			knockbackController:_sendKnockbackVelocity(targetChar, knockbackVelocity, 0)
		end
	end
end

--------------------------------------------------------------------------------
-- Sound Configuration
--------------------------------------------------------------------------------

local SOUND_CONFIG = {
	-- charge = { id = "rbxassetid://0", volume = 1 },
	-- spawn = { id = "rbxassetid://0", volume = 1 },
}

-- Preload sounds
local preloadItems = {}
for name, config in pairs(SOUND_CONFIG) do
	if config.id ~= "rbxassetid://0" and not script:FindFirstChild(name) then
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = config.id
		sound.Volume = config.volume
		sound.Parent = script
		table.insert(preloadItems, sound)
	end
end
if #preloadItems > 0 then
	ContentProvider:PreloadAsync(preloadItems)
end

--------------------------------------------------------------------------------
-- Raycast Helpers
--------------------------------------------------------------------------------

local function createMapOnlyParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	
	-- Exclude all players, characters, dummies, and effects
	local excludeList = {}
	
	-- Exclude all player characters
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excludeList, player.Character)
		end
	end
	
	-- Exclude effects folders (both locations)
	local effectsFolder = Workspace:FindFirstChild("Effects")
	if effectsFolder then
		table.insert(excludeList, effectsFolder)
	end
	local world = Workspace:FindFirstChild("World")
	if world then
		local mapFolder = world:FindFirstChild("Map")
		if mapFolder then
			local mapEffects = mapFolder:FindFirstChild("Effects")
			if mapEffects then
				table.insert(excludeList, mapEffects)
			end
		end
	end
	
	-- Exclude dummies
	world = world or Workspace:FindFirstChild("World")
	if world then
		local dummySpawns = world:FindFirstChild("DummySpawns")
		if dummySpawns then
			table.insert(excludeList, dummySpawns)
		end
	end
	
	-- Exclude Collider folder (hitboxes)
	local colliders = Workspace:FindFirstChild("Colliders")
	if colliders then
		table.insert(excludeList, colliders)
	end
	
	params.FilterDescendantsInstances = excludeList
	return params
end

--------------------------------------------------------------------------------
-- Placement Logic
--------------------------------------------------------------------------------

local function getWallPlacementCFrame(character)
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
	if not hrp then return nil end
	
	local mapParams = createMapOnlyParams()
	
	-- Raycast from camera in look direction
	local rayOrigin = camera.CFrame.Position
	local rayDirection = camera.CFrame.LookVector * WALL_CONFIG.MAX_PLACEMENT_DISTANCE
	
	local result = Workspace:Raycast(rayOrigin, rayDirection, mapParams)
	
	local hitPos
	if result then
		-- Hit a surface directly
		hitPos = result.Position
	else
		-- No hit - raycast down from max distance point to find floor
		local farPoint = rayOrigin + rayDirection
		local downResult = Workspace:Raycast(
			farPoint + Vector3.new(0, 5, 0), 
			Vector3.new(0, -WALL_CONFIG.RAYCAST_DOWN_DISTANCE, 0), 
			mapParams
		)
		
		if downResult then
			hitPos = downResult.Position
		else
			-- No floor found - cancel ability
			return nil
		end
	end
	
	-- Get camera Y rotation for wall orientation
	local _, yRotation = camera.CFrame:ToOrientation()
	
	-- Create CFrame at floor position, rotated to face camera direction
	local wallCFrame = CFrame.new(hitPos) * CFrame.Angles(0, yRotation, 0)
	
	return wallCFrame
end

--------------------------------------------------------------------------------
-- Wall Push Detection (for second use)
--------------------------------------------------------------------------------

local function getEffectsFolder()
	-- Check workspace.World.Map.Effects first
	local worldFolder = Workspace:FindFirstChild("World")
	local mapFolder = worldFolder and worldFolder:FindFirstChild("Map")
	if mapFolder then
		local effects = mapFolder:FindFirstChild("Effects")
		if effects then return effects end
	end
	-- Fallback to workspace.Effects
	return Workspace:FindFirstChild("Effects")
end

local function getOwnActiveWall()
	-- Check if player has an active wall attribute
	local wallId = LocalPlayer:GetAttribute("MobActiveWallId")
	if not wallId then return nil end
	
	-- Find the wall in effects folder
	local effectsFolder = getEffectsFolder()
	if not effectsFolder then return nil end
	
	local wall = effectsFolder:FindFirstChild("MobWall_" .. tostring(LocalPlayer.UserId))
	return wall
end

local function isInGracePeriod()
	local wall = getOwnActiveWall()
	if not wall then return false end
	
	local spawnTime = wall:GetAttribute("SpawnTime")
	if not spawnTime then return false end
	
	-- Grace period: can use second ability within GRACE_PERIOD seconds of spawn
	return (os.clock() - spawnTime) < WALL_CONFIG.GRACE_PERIOD
end

local function isLookingAtOwnWall()
	local camera = Workspace.CurrentCamera
	if not camera then return false, nil end
	
	local wall = getOwnActiveWall()
	if not wall then return false, nil end
	
	-- Raycast to check if looking at wall
	local rayOrigin = camera.CFrame.Position
	local rayDirection = camera.CFrame.LookVector * WALL_CONFIG.PUSH_CHECK_DISTANCE
	
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { wall }
	
	local result = Workspace:Raycast(rayOrigin, rayDirection, params)
	if result then
		return true, wall
	end
	
	-- Also check dot product for more forgiving detection
	local toWall = (wall.Position - rayOrigin)
	local distance = toWall.Magnitude
	if distance <= WALL_CONFIG.PUSH_CHECK_DISTANCE then
		local dotProduct = camera.CFrame.LookVector:Dot(toWall.Unit)
		if dotProduct > 0.6 then  -- Looking roughly toward wall
			return true, wall
		end
	end
	
	return false, nil
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local Mob = {}
Mob.__index = Mob

Mob.Ability = {}
Mob.Ultimate = {}

Mob._ctx = nil
Mob._connections = {}
Mob._abilityState = nil

--------------------------------------------------------------------------------
-- Ability: Wall Rise
--------------------------------------------------------------------------------

function Mob.Ability:OnStart(abilityRequest)
	local hrp = abilityRequest.humanoidRootPart
	local character = abilityRequest.character
	if not hrp or not character then return end
	
	local kitController = ServiceRegistry:GetController("Kit")
	
	if kitController:IsAbilityActive() then return end
	
	-- Check if there's an active wall we can push
	local activeWall = getOwnActiveWall()
	
	if activeWall then
		-- Wall exists - check if we're looking at it to push
		local canPush, wallToPush = isLookingAtOwnWall()
		if canPush and wallToPush then
			-- Looking at wall - push it!
			Mob.Ability:_pushWall(wallToPush, abilityRequest, kitController)
			return
		end
		
		-- Not looking at wall - check if in grace period
		if isInGracePeriod() then
			-- During grace period, can't create new wall if not looking at current one
			-- Just do nothing
			return
		end
		-- After grace period, fall through to create new wall (destroys old)
	end
	
	-- Normal ability: create wall
	if abilityRequest.IsOnCooldown() then return end
	
	-- Start ability (holster weapon)
	local ctx = abilityRequest.StartAbility()
	kitController:LockWeaponSwitch()
	
	local viewmodelAnimator = ctx.viewmodelAnimator
	local viewmodelController = abilityRequest.viewmodelController
	local viewmodelRig = viewmodelController and viewmodelController:GetActiveRig()
	
	-- Play animation
	local animation = viewmodelAnimator:PlayKitAnimation(ANIM_NAME, {
		priority = Enum.AnimationPriority.Action4,
		stopOthers = true,
	})
	
	if not animation then
		kitController:UnlockWeaponSwitch()
		kitController:_unholsterWeapon()
		return
	end
	
	-- State tracking
	local state = {
		active = true,
		cancelled = false,
		pivot = nil,           -- Wall placement CFrame (set at "charge" event)
		animation = animation,
		abilityRequest = abilityRequest,
		character = character,
		viewmodelRig = viewmodelRig,
		connections = {},
	}
	Mob._abilityState = state
	
	-- Animation event handlers
	local Events = {
		["chargeaem"] = function()
			if state.cancelled then return end

			VFXRep:Fire("Me", { Module = "MobAbility", Function = "Execute" }, {
				Character = character,
				ViewModel = viewmodelRig,
				forceAction = "arm",
			})

			abilityRequest.Send({
				action = "relayUserVfx",
				forceAction = "arm",
				allowMultiple = true,
			})
		end,
		
		["charge"] = function()
			if state.cancelled then return end
			
			-- Calculate wall placement
			state.pivot = getWallPlacementCFrame(character)
			
			if not state.pivot then
				-- No valid placement - cancel ability
				state.cancelled = true
				if animation and animation.IsPlaying then
					animation:Stop(0.1)
				end
				kitController:UnlockWeaponSwitch()
				kitController:_unholsterWeapon()
				Mob._abilityState = nil
				return
			end
			
			-- Fire charge VFX at pivot location
			VFXRep:Fire("All", { Module = "MobAbility", Function = "Execute" }, {
				Character = character,
				ViewModel = viewmodelRig,
				Pivot = state.pivot,
				forceAction = "charge",
			})

			abilityRequest.Send({
				action = "relayUserVfx",
				forceAction = "charge",
				pivot = state.pivot,
				allowMultiple = true,
			})
		end,
		
		["start"] = function()
			if state.cancelled then return end
			if not state.pivot then return end
			
			-- Apply knockback FIRST (before wall spawns) - client-side
			applyWallKnockback(state.pivot.Position, abilityRequest.player)
			
			-- Send spawn request to server with placement CFrame
			-- Server will start grace period timer (cooldown after 3s unless pushed)
			abilityRequest.Send({
				action = "spawnWall",
				pivot = state.pivot,
				allowMultiple = true,
			})
			
			-- Fire spawn VFX
			VFXRep:Fire("Me", { Module = "Mob", Function = "User" }, {
				Character = character,
				ViewModel = viewmodelRig,
				Pivot = state.pivot,
				forceAction = "start",
			})
			abilityRequest.Send({
				action = "relayUserVfx",
				forceAction = "start",
				pivot = state.pivot,
				allowMultiple = true,
			})
		end,
		
		["_finish"] = function()
			if not state.active then return end
			state.active = false
			
			-- Cleanup connections
			for _, conn in ipairs(state.connections) do
				if typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				end
			end
			state.connections = {}
			
			-- Restore weapon
			kitController:UnlockWeaponSwitch()
			kitController:_unholsterWeapon()
			
			if Mob._abilityState == state then
				Mob._abilityState = nil
			end
		end,
	}
	
	-- Connect to animation events
	table.insert(state.connections, animation:GetMarkerReachedSignal("Event"):Connect(function(eventName)
		if Events[eventName] then
			Events[eventName]()
		end
	end))
	
	-- Safety cleanup on animation end
	table.insert(state.connections, animation.Stopped:Once(function()
		if state.active then
			Events["_finish"]()
		end
	end))
	
	table.insert(state.connections, animation.Ended:Once(function()
		if state.active then
			Events["_finish"]()
		end
	end))
end

function Mob.Ability:OnEnded(abilityRequest)
	-- Not a hold ability, nothing to do
end

function Mob.Ability:OnInterrupt(abilityRequest, reason)
	local state = Mob._abilityState
	if not state then return end
	
	state.cancelled = true
	state.active = false
	
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
	
	-- Restore weapon
	local kitController = ServiceRegistry:GetController("Kit")
	kitController:UnlockWeaponSwitch()
	kitController:_unholsterWeapon()
	
	Mob._abilityState = nil
end

--------------------------------------------------------------------------------
-- Push Wall (Second Use)
--------------------------------------------------------------------------------

local PUSH_ANIM_NAME = "MobAbilitySecond"

function Mob.Ability:_pushWall(wall, abilityRequest, kitController)
	local character = abilityRequest.character
	local viewmodelController = abilityRequest.viewmodelController
	local viewmodelRig = viewmodelController and viewmodelController:GetActiveRig()
	
	-- Start ability (holster weapon)
	local ctx = abilityRequest.StartAbility()
	kitController:LockWeaponSwitch()
	
	local viewmodelAnimator = ctx.viewmodelAnimator
	
	-- Play push animation
	local animation = viewmodelAnimator:PlayKitAnimation(PUSH_ANIM_NAME, {
		priority = Enum.AnimationPriority.Action4,
		stopOthers = true,
	})
	
	if not animation then
		kitController:UnlockWeaponSwitch()
		kitController:_unholsterWeapon()
		return
	end

	-- State tracking
	local state = {
		active = true,
		cancelled = false,
		wall = wall,
		pivot = nil,
		wallId = wall:GetAttribute("WallId"),
		animation = animation,
		abilityRequest = abilityRequest,
		character = character,
		viewmodelRig = viewmodelRig,
		connections = {},
	}
	Mob._abilityState = state
	
	-- Animation event handlers for push
	local rayOrigin = wall.Position
	local rayDirection = Vector3.new(0, -25, 0)

	local mapParams = createMapOnlyParams()
	local result = Workspace:Raycast(rayOrigin, rayDirection, mapParams)

	local hitPos
	if result then
		hitPos = result.Position
	else
		hitPos = wall.Position
	end
	
	
	local Events = {
		["start"] = function()
			if state.cancelled then return end
			
			-- Tell server to cancel grace timer - push is happening
			abilityRequest.Send({
				action = "pushStarted",
				allowMultiple = true,
			})
			
			-- VFX: Start push visual
			VFXRep:Fire("All", { Module = "MobAbility", Function = "Execute" }, {
				Character = character,
				ViewModel = viewmodelRig,
				forceAction = "seewall",
				Pivot = CFrame.new(hitPos),
			})

			VFXRep:Fire("All", { Module = "MobAbility", Function = "Execute" }, {
				Character = character,
				ViewModel = viewmodelRig,
				Pivot = CFrame.new(hitPos),
				forceAction = "charge",
			})

			abilityRequest.Send({
				action = "relayUserVfx",
				forceAction = "pushStart",
				allowMultiple = true,
			})
		end,
		
		["charge"] = function()
			if state.cancelled then return end
			
			-- VFX: Charge visual
			VFXRep:Fire("Me", { Module = "Mob", Function = "User" }, {
				Character = character,
				ViewModel = viewmodelRig,
				forceAction = "pushCharge",
			})
			
			abilityRequest.Send({
				action = "relayUserVfx",
				forceAction = "pushCharge",
				allowMultiple = true,
			})
			
			VFXRep:Fire("Me", { Module = "MobAbility", Function = "Execute" }, {
				Character = character,
				ViewModel = viewmodelRig,
				forceAction = "arm",
			})
		end,
		
		["push"] = function()
			if state.cancelled then return end
			
			-- Get camera direction for push
			local camera = Workspace.CurrentCamera
			local pushDirection = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
			
			-- Send push request to server
			abilityRequest.Send({
				action = "pushWall",
				wallId = state.wallId,
				direction = pushDirection,
				allowMultiple = true,
			})
			
			-- VFX: Push visual
			VFXRep:Fire("Me", { Module = "Mob", Function = "User" }, {
				Character = character,
				ViewModel = viewmodelRig,
				forceAction = "push",
			})
			
			abilityRequest.Send({
				action = "relayUserVfx",
				forceAction = "push",
				allowMultiple = true,
			})
		end,
		
		["_finish"] = function()
			if not state.active then return end
			state.active = false
			
			-- Cleanup connections
			for _, conn in ipairs(state.connections) do
				if typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				end
			end
			state.connections = {}
			
			-- Restore weapon
			kitController:UnlockWeaponSwitch()
			kitController:_unholsterWeapon()
			
			if Mob._abilityState == state then
				Mob._abilityState = nil
			end
		end,
	}
	
	-- Connect to animation events
	table.insert(state.connections, animation:GetMarkerReachedSignal("Event"):Connect(function(eventName)
		if Events[eventName] then
			Events[eventName]()
		end
	end))
	
	-- Safety cleanup on animation end
	table.insert(state.connections, animation.Stopped:Once(function()
		if state.active then
			Events["_finish"]()
		end
	end))
	
	table.insert(state.connections, animation.Ended:Once(function()
		if state.active then
			Events["_finish"]()
		end
	end))
end

--------------------------------------------------------------------------------
-- Ultimate (placeholder)
--------------------------------------------------------------------------------

function Mob.Ultimate:OnStart(abilityRequest)
	abilityRequest.Send()
end

function Mob.Ultimate:OnEnded(abilityRequest)
end

function Mob.Ultimate:OnInterrupt(abilityRequest, reason)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Mob.new(ctx)
	local self = setmetatable({}, Mob)
	self._ctx = ctx
	self._connections = {}
	self.Ability = Mob.Ability
	self.Ultimate = Mob.Ultimate
	return self
end

function Mob:OnEquip(ctx)
	self._ctx = ctx
end

function Mob:OnUnequip(reason)
	for _, conn in pairs(self._connections) do
		if typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end
	self._connections = {}
	
	-- Cancel active ability
	if Mob._abilityState and Mob._abilityState.active then
		Mob.Ability:OnInterrupt(nil, "unequip")
	end
end

function Mob:Destroy()
	self:OnUnequip("Destroy")
end

return Mob
