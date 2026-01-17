--[[
	Attack.lua (_Template)

	============================================================================
	ATTACK ACTION TEMPLATE
	============================================================================

	This module handles the firing/attacking logic for your weapon.
	Called when the player presses the fire button.

	KEY POINTS:
	- WeaponController already plays "Fire" animation automatically
	- You can add custom animations, sounds, effects here
	- Recoil is applied via ViewmodelEffects
	- Hit detection uses HitscanSystem

	============================================================================
	ANIMATION FLOW
	============================================================================

	When player fires:
	1. WeaponController:FireWeapon() is called
	2. WeaponManager:AttackWeapon() calls this Attack.Execute()
	3. WeaponController plays "Fire" animation automatically

	If you need CUSTOM animation control:
	- Stop the auto-play in WeaponController
	- Or play additional animations here

	============================================================================
]]

local Attack = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseGun = require(Locations.Modules.Weapons.Actions.Gun.BaseGun)
local HitscanSystem = require(Locations.Modules.Weapons.Systems.HitscanSystem)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

local localPlayer = Players.LocalPlayer

--[[
	============================================================================
	MAIN ATTACK EXECUTION
	============================================================================
]]
function Attack.Execute(weaponInstance)
	local player = weaponInstance.Player
	local config = weaponInstance.Config
	local state = weaponInstance.State

	-- Check if can fire using base gun logic
	if not BaseGun.CanFire(weaponInstance) then
		Log:Debug("WEAPON", "[Template] Cannot fire - conditions not met")

		-- Play dry fire sound/animation if out of ammo
		if state.CurrentAmmo <= 0 then
			Attack.OnDryFire(weaponInstance)
		end
		return
	end

	-- Check fire rate cooldown
	local currentTime = tick()
	local cooldown = BaseGun.GetFireCooldown(weaponInstance)

	if currentTime - state.LastFireTime < cooldown then
		return
	end

	Log:Debug("WEAPON", "[Template] Firing weapon")

	-- Update state
	state.IsAttacking = true
	state.LastFireTime = currentTime

	-- Consume ammo
	BaseGun.ConsumeAmmo(weaponInstance, 1)

	-- =========================================================================
	-- VIEWMODEL ANIMATION & EFFECTS
	-- =========================================================================
	--
	-- NOTE: WeaponController already calls ViewmodelController:PlayAnimation("Fire")
	-- So you typically DON'T need to call it again here.
	--
	-- However, if you want CUSTOM behavior, here's how:

	local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")

	if ViewmodelController then
		-- Example: Apply custom recoil
		-- ViewmodelController.ViewmodelEffects:ApplyRecoil(0.02, 0.01)

		-- Example: Play a custom animation instead of "Fire"
		-- ViewmodelController:PlayAnimation("FireAlt")

		-- Example: Check if ADS for different behavior
		local isADS = ViewmodelController:GetADSAlpha() > 0.5
		if isADS then
			-- Different behavior when aiming
			Log:Debug("WEAPON", "[Template] Firing while ADS")
		end
	end

	-- =========================================================================
	-- PERFORM HITSCAN RAYCAST
	-- =========================================================================

	local camera = workspace.CurrentCamera
	if not camera then
		Log:Warn("WEAPON", "[Template] No camera found")
		return
	end

	local character = player.Character
	if not character then
		Log:Warn("WEAPON", "[Template] No character found")
		return
	end

	-- Raycast from camera
	local origin = camera.CFrame.Position
	local maxRange = config.Damage.MaxRange or 500
	local direction = camera.CFrame.LookVector * maxRange

	-- Perform raycast
	local raycastResult = HitscanSystem:PerformRaycast(origin, direction, character, tostring(player.UserId))

	-- =========================================================================
	-- PROCESS HIT RESULT
	-- =========================================================================

	local hitData = {
		WeaponType = weaponInstance.WeaponType,
		WeaponName = weaponInstance.WeaponName,
		Origin = origin,
		Direction = direction,
		Timestamp = os.clock(),
		Hits = {},
	}

	if raycastResult then
		local hitInfo = {
			HitPosition = raycastResult.Position,
			HitPartName = raycastResult.Instance.Name,
			Distance = raycastResult.Distance,
		}

		-- Check if we hit a player's hitbox
		local isHitboxHit = HitscanSystem:IsHitboxPart(raycastResult.Instance)

		if isHitboxHit then
			hitInfo.IsHeadshot = HitscanSystem:IsHeadshot(raycastResult.Instance)
			hitInfo.TargetPlayer = HitscanSystem:GetPlayerFromHit(raycastResult.Instance)

			Log:Info("WEAPON", "[Template] Hit player", {
				Target = hitInfo.TargetPlayer and hitInfo.TargetPlayer.Name or "Unknown",
				Headshot = hitInfo.IsHeadshot,
			})

			-- Play hit marker sound/effect here
			Attack.OnHitPlayer(weaponInstance, hitInfo)
		end

		table.insert(hitData.Hits, hitInfo)
	else
		Log:Debug("WEAPON", "[Template] Shot missed")
	end

	-- Send hit data to server for validation
	RemoteEvents:FireServer("WeaponFired", hitData)

	-- =========================================================================
	-- PLAY EFFECTS
	-- =========================================================================

	-- Muzzle flash, tracer, etc.
	Attack.PlayFireEffects(weaponInstance, origin, direction)

	-- =========================================================================
	-- CLEANUP
	-- =========================================================================

	-- Release attacking state after brief delay
	task.wait(0.1)
	state.IsAttacking = false

	-- Auto reload if empty and enabled
	if state.CurrentAmmo <= 0 and config.Ammo.AutoReload and state.ReserveAmmo > 0 then
		local WeaponManager = require(Locations.Modules.Weapons.Managers.WeaponManager)
		WeaponManager:ReloadWeapon(player, weaponInstance)
	end
end

--[[
	============================================================================
	HELPER FUNCTIONS - CUSTOMIZE THESE
	============================================================================
]]

-- Called when firing with no ammo
function Attack.OnDryFire(weaponInstance)
	Log:Debug("WEAPON", "[Template] Dry fire - out of ammo")

	-- Play dry fire sound
	-- SoundManager:PlaySound("DryFire")

	-- Play dry fire animation (optional)
	-- local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")
	-- if ViewmodelController then
	--     ViewmodelController:PlayAnimation("DryFire")
	-- end
end

-- Called when hitting a player
function Attack.OnHitPlayer(weaponInstance, hitInfo)
	-- Play hit marker sound
	-- SoundManager:PlaySound("HitMarker")

	-- Play headshot sound if headshot
	if hitInfo.IsHeadshot then
		-- SoundManager:PlaySound("HeadshotMarker")
	end
end

-- Play muzzle flash, tracer, etc.
function Attack.PlayFireEffects(weaponInstance, origin, direction)
	-- Muzzle flash
	-- local muzzleFlash = ...

	-- Tracer
	-- local tracer = ...

	-- Shell ejection
	-- local shell = ...
end

return Attack
