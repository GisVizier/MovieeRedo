--[[
	Aki Client Kit
	
	Ability: Kon - Summon devil that rushes to target location and bites
	
	Flow:
	1. Press E → Play animation → Freezes at "freeze" marker
	2. Hold → Animation frozen, player can aim
	3. Release E → Animation continues, events trigger ability
	
	Animation Events:
	- freeze: Pause animation (Speed = 0)
	- spawn: Spawn Kon via VFXRep
	- bite: Hitbox + knockback + send to server
	- _finish: Cleanup and restore weapon
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
-- Constants
--------------------------------------------------------------------------------

local MAX_RANGE = 125
local BITE_RADIUS = 12
local BITE_KNOCKBACK_PRESET = "Fling"
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

-- Active ability state
Aki._abilityState = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getTargetLocation(character: Model, maxDistance: number): (CFrame?, Vector3?)
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not root then return nil, nil end

	local filterList = { character }
	local effectsFolder = Workspace:FindFirstChild("Effects")
	if effectsFolder then
		table.insert(filterList, effectsFolder)
	end
	TargetParams.FilterDescendantsInstances = filterList

	local camCF = Workspace.CurrentCamera.CFrame
	local result = Workspace:Raycast(camCF.Position, camCF.LookVector * maxDistance, TargetParams)

	if result and result.Instance and result.Instance.Transparency ~= 1 then
		local hitPosition = result.Position
		local normal = result.Normal
		
		if normal.Y > 0.5 then
			-- Floor: Kon stands upright, faces direction from camera
			local camPos = Vector3.new(camCF.Position.X, hitPosition.Y, camCF.Position.Z)
			local dirRelToCam = CFrame.lookAt(camPos, hitPosition).LookVector
			return CFrame.lookAt(hitPosition, hitPosition + dirRelToCam), normal
		else
			-- Wall/ceiling: Kon faces outward from surface
			return CFrame.new(hitPosition, hitPosition + normal), normal
		end
	else
		local hitPos = camCF.Position + camCF.LookVector * maxDistance
		result = Workspace:Raycast(hitPos + Vector3.new(0, 5, 0), Vector3.yAxis * -100, TargetParams)
		if result then
			return CFrame.lookAt(result.Position, result.Position + camCF.LookVector), result.Normal
		end
	end

	return nil, nil
end

--------------------------------------------------------------------------------
-- Ability: Kon
--------------------------------------------------------------------------------

function Aki.Ability:OnStart(abilityRequest)
	local hrp = abilityRequest.humanoidRootPart
	local character = abilityRequest.character
	if not hrp or not character then return end

	local kitController = ServiceRegistry:GetController("Kit")

	if kitController:IsAbilityActive() then return end
	if abilityRequest.IsOnCooldown() then return end

	-- Start ability
	local ctx = abilityRequest.StartAbility()
	local unlock = kitController:LockWeaponSwitch()

	-- Play viewmodel animation
	local viewmodelAnimator = ctx.viewmodelAnimator
	local viewmodelController = abilityRequest.viewmodelController
	local viewmodelRig = viewmodelController and viewmodelController:GetActiveRig()
	
	local animation = viewmodelAnimator:PlayKitAnimation(VM_ANIM_NAME, {
		priority = Enum.AnimationPriority.Action4,
		stopOthers = true,
	})

	if not animation then
		unlock()
		kitController:_unholsterWeapon()
		return
	end

	-- State tracking
	local state = {
		active = true,
		released = false,
		cancelled = false,
		animation = animation,
		unlock = unlock,
		abilityRequest = abilityRequest,
		character = character,
		viewmodelRig = viewmodelRig,
		connections = {},
	}
	Aki._abilityState = state

	-- Animation event handlers
	local Events = {
		["freeze"] = function()
			-- Pause animation until released
			if state.active and not state.released then
				animation:AdjustSpeed(0)
			end
		end,

		["shake"] = function()
			-- Caster viewmodel effects
			VFXRep:Fire("Me", { Module = "Kon", Function = "User" }, {
				ViewModel = viewmodelRig,
				forceAction = "start",
			})
		end,

		["place"] = function()
			if not state.active or state.cancelled then return end
			if viewmodelController:GetActiveSlot() ~= "Fists" then return end

			-- Get target location at moment of spawn
			local targetCFrame, surfaceNormal = getTargetLocation(character, MAX_RANGE)
			if not targetCFrame then return end
			
			surfaceNormal = surfaceNormal or Vector3.yAxis

			state.targetCFrame = targetCFrame

			-- Send to server for validation
			abilityRequest.Send({
				action = "requestKonSpawn",
				targetPosition = { X = targetCFrame.Position.X, Y = targetCFrame.Position.Y, Z = targetCFrame.Position.Z },
				targetLookVector = { X = targetCFrame.LookVector.X, Y = targetCFrame.LookVector.Y, Z = targetCFrame.LookVector.Z },
			})

			-- Spawn Kon for ALL clients via VFXRep
			VFXRep:Fire("All", { Module = "Kon", Function = "createKon" }, {
				position = { X = targetCFrame.Position.X, Y = targetCFrame.Position.Y, Z = targetCFrame.Position.Z },
				lookVector = { X = targetCFrame.LookVector.X, Y = targetCFrame.LookVector.Y, Z = targetCFrame.LookVector.Z },
				surfaceNormal = { X = surfaceNormal.X, Y = surfaceNormal.Y, Z = surfaceNormal.Z },
			})
			

			local targets = Hitbox.GetCharactersInSphere(targetCFrame.Position, BITE_RADIUS, {
				Exclude = abilityRequest.player,
			})

			-- Knockback
			local knockbackController = ServiceRegistry:GetController("Knockback")
			local hitList = {}
			for _, targetChar in ipairs(targets) do
				if knockbackController then
					knockbackController:ApplyKnockback(targetChar, {
						upwardVelocity = 100,
						outwardVelocity = 30,
						preserveMomentum = -1.0,
					}, targetCFrame.Position)

				end

				local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
				table.insert(hitList, {
					characterName = targetChar.Name,
					playerId = targetPlayer and targetPlayer.UserId or nil,
					isDummy = targetPlayer == nil,
				})
			end
			
			task.spawn(function()
				task.wait(.6)
				
				if not state.active or state.cancelled then return end
				if viewmodelController:GetActiveSlot() ~= "Fists" then return end
				if not state.targetCFrame then return end

				local bitePosition = state.targetCFrame.Position

				-- Hitbox
				local targets = Hitbox.GetCharactersInSphere(bitePosition, BITE_RADIUS, {
					Exclude = abilityRequest.player,
				})

				-- Knockback
				local knockbackController = ServiceRegistry:GetController("Knockback")
				local hitList = {}

				for _, targetChar in ipairs(targets) do
					if knockbackController then
						knockbackController:ApplyKnockback(targetChar, {
							upwardVelocity = 150,       -- Good lift (slightly less than jump pad)
							outwardVelocity = 180,     -- Strong horizontal push away
							preserveMomentum = 0.25,
						}, targetCFrame.Position)

						--knockbackController:ApplyKnockbackPreset(targetChar, `FlingHuge`, bitePosition)
					end

					local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
					table.insert(hitList, {
						characterName = targetChar.Name,
						playerId = targetPlayer and targetPlayer.UserId or nil,
						isDummy = targetPlayer == nil,
					})
				end

				-- Send hits to server
				abilityRequest.Send({
					action = "konBite",
					hits = hitList,
					bitePosition = { X = bitePosition.X, Y = bitePosition.Y, Z = bitePosition.Z },
				})

				-- Caster bite effects
				VFXRep:Fire("Me", { Module = "Kon", Function = "User" }, {
					ViewModel = viewmodelRig,
					forceAction = "bite",
				})
			end)

		end,

		["_finish"] = function()
			if not state.active then return end
			
			state.active = false
			Aki._abilityState = nil

			-- Cleanup connections
			for _, conn in ipairs(state.connections) do
				if typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				end
			end

			-- Restore weapon
			state.unlock()
			kitController:_unholsterWeapon()
		end,
	}

	-- Connect to animation events
	state.connections[#state.connections + 1] = animation:GetMarkerReachedSignal("Event"):Connect(function(event)
		if Events[event] then
			Events[event]()
		end
	end)

	-- Handle animation end (safety cleanup)
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

function Aki.Ability:OnEnded(abilityRequest)
	local state = Aki._abilityState
	if not state or not state.active then return end

	-- Mark as released
	state.released = true

	-- Resume animation from freeze
	if state.animation and state.animation.IsPlaying then
		state.animation:AdjustSpeed(1)
	end
end

function Aki.Ability:OnInterrupt(abilityRequest, reason)
	local state = Aki._abilityState
	if not state or not state.active then return end

	state.cancelled = true
	state.active = false
	Aki._abilityState = nil

	-- Stop animation
	if state.animation and state.animation.IsPlaying then
		state.animation:Stop(0.1)
	end

	-- Destroy Kon if spawned
	VFXRep:Fire("All", { Module = "Kon", Function = "destroyKon" }, {})

	-- Cleanup connections
	for _, conn in ipairs(state.connections) do
		if typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end

	-- Restore weapon
	state.unlock()
	ServiceRegistry:GetController("Kit"):_unholsterWeapon()
end

--------------------------------------------------------------------------------
-- Ultimate (placeholder)
--------------------------------------------------------------------------------

function Aki.Ultimate:OnStart(abilityRequest)
	abilityRequest.Send()
end

function Aki.Ultimate:OnEnded(abilityRequest)
end

function Aki.Ultimate:OnInterrupt(abilityRequest, reason)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Aki.new(ctx)
	local self = setmetatable({}, Aki)
	self._ctx = ctx
	self._connections = {}
	self.Ability = Aki.Ability
	self.Ultimate = Aki.Ultimate
	return self
end

function Aki:OnEquip(ctx)
	self._ctx = ctx
end

function Aki:OnUnequip(reason)
	for _, conn in pairs(self._connections) do
		if typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end
	self._connections = {}

	-- Cancel active ability
	if Aki._abilityState and Aki._abilityState.active then
		Aki.Ability:OnInterrupt(nil, "unequip")
	end
end

function Aki:Destroy()
	self:OnUnequip("Destroy")
end

return Aki
