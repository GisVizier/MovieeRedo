--[[
	Airborne Kit - Client Module
	
	The client kit handles:
	- Input processing (OnStart, OnEnded, OnInterrupt)
	- Physics (velocity applied CLIENT-SIDE for responsiveness)
	- Viewmodel animations (via ctx.viewmodelAnimator:PlayKitAnimation)
	- Character animations (via AnimationController - replicates to other players)
	- VFX (via VFXRep modules)
	
	abilityRequest contains:
	- player, character, humanoidRootPart
	- IsOnCooldown() - check if ability is on cooldown
	- GetCooldownRemaining() - get seconds remaining
	- StartAbility() - holsters weapon, returns { viewmodelAnimator }
	- Send(extraData) - notify server for cooldown/validation
	
	Flow:
	1. OnStart is called with abilityRequest
	2. Check cooldown with abilityRequest.IsOnCooldown() - return early if on cooldown
	3. Call abilityRequest.StartAbility() to holster weapon and get viewmodel
	4. Apply physics, play animations, fire VFX
	5. Call abilityRequest.Send() to notify server
	6. Server broadcasts AbilityEnded → KitController auto-restores weapon
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))

local Airborne = {}
Airborne.__index = Airborne

-- =============================================================================
-- CONFIG
-- =============================================================================
local CLOUDSKIP_SPEED = 80
local CLOUDSKIP_LIFT = 15

-- Viewmodel animation names (from Assets.Animations.ViewModel.Kits.Airborne)
local VM_ANIMS = {
	Updraft = "Updraft",               -- or "Airborne/Updraft" for full path
	CloudskipDash = "CloudskipDash",
	HurricaneStart = "HurricaneStart",
}

-- Character animation names (from Assets.Animations.Character.Kits.Airborne)
-- These replicate to other players
local CHAR_ANIMS = {
	CloudskipDash = "CloudskipDash",
	HurricaneStart = "HurricaneStart",
}

-- =============================================================================
-- ABILITY: CLOUDSKIP
-- Wind boost for fast repositioning.
-- =============================================================================
Airborne.Ability = {}

function Airborne.Ability:OnStart(abilityRequest)
	local hrp = abilityRequest.humanoidRootPart
	if not hrp then return end
	
	-- Check cooldown BEFORE doing anything
	if abilityRequest.IsOnCooldown() then
		return -- Don't start ability, don't switch viewmodel
	end
	
	-- Start the ability (holsters weapon, switches to fists, returns viewmodel context)
	local ctx = abilityRequest.StartAbility()
	
	-- Get direction from camera
	local camera = workspace.CurrentCamera
	local direction = Vector3.new(0, 0, -1)
	if camera then
		local lookVector = camera.CFrame.LookVector
		direction = Vector3.new(lookVector.X, 0, lookVector.Z)
		if direction.Magnitude > 0.1 then
			direction = direction.Unit
		end
	end
	
	-- TODO: Add viewmodel animation when ready
	-- local viewmodelAnimator = ctx.viewmodelAnimator
	-- if viewmodelAnimator and viewmodelAnimator.PlayKitAnimation then
	-- 	viewmodelAnimator:PlayKitAnimation(VM_ANIMS.CloudskipDash, {
	-- 		fadeTime = 0.05,
	-- 		speed = 1,
	-- 		priority = Enum.AnimationPriority.Action4,
	-- 		stopOthers = true,
	-- 	})
	-- end
	
	-- TODO: Add character animation when ready
	-- local animController = ServiceRegistry:GetController("AnimationController")
	-- if animController and animController.PlayAnimation then
	-- 	animController:PlayAnimation(CHAR_ANIMS.CloudskipDash, {...})
	-- end
	
	-- Apply velocity on CLIENT (instant, responsive)
	hrp.AssemblyLinearVelocity = direction * CLOUDSKIP_SPEED + Vector3.new(0, CLOUDSKIP_LIFT, 0)
	
	-- Fire VFX for MYSELF only (instant, no latency)
	VFXRep:Fire("Me", { Module = "Cloudskip", Function = "User" }, {
		position = hrp.Position,
		direction = direction,
	})
	
	-- Tell server to start cooldown, broadcast VFX to others, and end ability
	abilityRequest.Send({
		direction = direction,
	})
end

function Airborne.Ability:OnEnded(_abilityRequest)
	-- OnEnded is called when the input button is released
	-- For instant abilities like Cloudskip, we don't need to do anything here
	-- The server already received Send() in OnStart
end

function Airborne.Ability:OnInterrupt(_abilityRequest, _reason)
	-- TODO: Stop animations when they're added
end

-- =============================================================================
-- ULTIMATE: HURRICANE
-- Tornado that pulls enemies in and launches them.
-- =============================================================================
Airborne.Ultimate = {}

function Airborne.Ultimate:OnStart(abilityRequest)
	local hrp = abilityRequest.humanoidRootPart
	if not hrp then return end
	
	-- Ultimate doesn't have cooldown, but has energy cost (checked by server)
	-- Start the ability (holsters weapon, switches to fists)
	local ctx = abilityRequest.StartAbility()
	
	-- TODO: Add viewmodel animation when ready
	-- local viewmodelAnimator = ctx.viewmodelAnimator
	-- if viewmodelAnimator and viewmodelAnimator.PlayKitAnimation then
	-- 	viewmodelAnimator:PlayKitAnimation(VM_ANIMS.HurricaneStart, {...})
	-- end
	
	-- TODO: Add character animation when ready
	
	-- Fire VFX for MYSELF only (instant, no latency)
	VFXRep:Fire("Me", { Module = "Hurricane", Function = "User" }, {
		position = hrp.Position,
	})
	
	-- Tell server to process ultimate and broadcast VFX to others
	abilityRequest.Send({
		origin = hrp.Position,
	})
end

function Airborne.Ultimate:OnEnded(_abilityRequest)
	-- Ultimate may have a hold mechanic; for now we do nothing on release
end

function Airborne.Ultimate:OnInterrupt(_abilityRequest, _reason)
	-- TODO: Stop animations when they're added
end

-- =============================================================================
-- CONSTRUCTOR
-- =============================================================================
function Airborne.new(ctx)
	local self = setmetatable({}, Airborne)
	self._ctx = ctx
	self.Ability = Airborne.Ability
	self.Ultimate = Airborne.Ultimate
	return self
end

function Airborne:Destroy()
end

return Airborne
