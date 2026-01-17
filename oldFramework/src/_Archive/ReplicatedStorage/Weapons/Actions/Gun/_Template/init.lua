--[[
	_Template/init.lua - WEAPON MODULE TEMPLATE

	============================================================================
	HOW TO USE THIS TEMPLATE
	============================================================================

	1. Copy the entire "_Template" folder
	2. Rename it to your weapon name (e.g., "SMG", "Pistol", "LMG")
	3. Update the weapon name references throughout the files
	4. Customize the behavior as needed

	============================================================================
	ARCHITECTURE OVERVIEW
	============================================================================

	Your weapon module consists of:

	FOLDER STRUCTURE:
	├── YourWeapon/
	│   ├── init.lua       - Main module (this file) - Initialization & shared logic
	│   ├── Attack.lua     - Firing logic
	│   ├── Equip.lua      - Equipping logic
	│   ├── Unequip.lua    - Unequipping logic
	│   ├── Reload.lua     - Reloading logic
	│   └── Inspect.lua    - Inspect animation logic

	FLOW:
	1. WeaponController receives input (fire/reload/etc)
	2. WeaponController calls WeaponManager
	3. WeaponManager loads and executes your action modules
	4. Your action modules perform weapon-specific logic

	============================================================================
	ACCESSING VIEWMODEL ANIMATIONS
	============================================================================

	There are TWO ways to play viewmodel animations:

	METHOD 1: Via ServiceRegistry (Recommended for action modules)
	------------------------------------------------------------
	local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
	local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")

	if ViewmodelController then
		ViewmodelController:PlayAnimation("Fire")    -- Play fire animation
		ViewmodelController:PlayAnimation("Reload")  -- Play reload animation
		ViewmodelController:PlayAnimation("Inspect") -- Play inspect animation
		ViewmodelController:StopAnimation("ADS")     -- Stop ADS animation
	end

	METHOD 2: Via WeaponController reference
	-----------------------------------------
	-- If you have access to weaponInstance:
	local weaponController = ServiceRegistry:GetController("WeaponController")
	if weaponController and weaponController.ViewmodelController then
		weaponController.ViewmodelController:PlayAnimation("Fire")
	end

	============================================================================
	AVAILABLE ANIMATION NAMES
	============================================================================

	Standard animations (defined in ViewmodelConfig.Weapons.YourWeapon.Animations):
	- "Idle"     - Default idle loop
	- "Walk"     - Walking loop
	- "Run"      - Running/sprinting loop
	- "Fire"     - Single shot animation
	- "Reload"   - Reload animation
	- "Equip"    - Equip/draw animation
	- "Inspect"  - Weapon inspection animation
	- "ADS"      - Aim down sights hold animation
	- "Attack"   - Melee attack animation (for melee weapons)

	============================================================================
	VIEWMODEL API REFERENCE
	============================================================================

	ViewmodelController Methods:

	:PlayAnimation(animationName)
		Plays the specified animation
		Fire/Attack/Reload restart from beginning each call

	:StopAnimation(animationName)
		Stops the specified animation

	:GetCurrentConfig()
		Returns the current weapon's ViewmodelConfig

	:GetCurrentWeight()
		Returns weapon weight (affects sway/bob speed)

	:IsViewmodelActive()
		Returns true if a viewmodel is currently active

	:GetADSAlpha()
		Returns 0-1 value of ADS transition (0 = hip, 1 = fully ADS)

	ViewmodelAnimator Methods (accessed via ViewmodelController.ViewmodelAnimator):

	:IsPlaying(animationName)
		Returns true if the animation is currently playing

	:GetTrack(animationName)
		Returns the AnimationTrack for the specified animation
		Useful for connecting to track.Stopped or track.KeyframeReached

	============================================================================
	VIEWMODEL EFFECTS REFERENCE
	============================================================================

	ViewmodelEffects (accessed via ViewmodelController.ViewmodelEffects):

	:ApplyRecoil(pitchAmount, yawAmount)
		Apply recoil impulse to viewmodel
		pitchAmount: vertical kick (positive = up)
		yawAmount: horizontal kick (positive = right)

	:GetCombinedOffset(deltaTime, adsAlpha, config)
		Returns the combined CFrame offset from all effects
		(sway, bob, recoil, sprint tuck, slide tilt, etc.)

	============================================================================
	WEAPON INSTANCE STRUCTURE
	============================================================================

	Your weaponInstance table contains:

	weaponInstance = {
		Player = Player,          -- The player who owns this weapon
		WeaponType = "Gun",       -- "Gun" or "Melee"
		WeaponName = "MyWeapon",  -- The weapon name

		Config = {                -- From WeaponConfig
			FireRate = { FireMode = "Auto", RPM = 600 },
			Damage = { Base = 25, Headshot = 75, MaxRange = 500 },
			Ammo = { MagSize = 30, ReloadTime = 2.0, AutoReload = true },
			-- etc.
		},

		State = {                 -- Mutable weapon state
			Equipped = false,
			CurrentAmmo = 30,
			ReserveAmmo = 90,
			IsReloading = false,
			IsAttacking = false,
			LastFireTime = 0,
		},
	}

	============================================================================
]]

local TemplateWeapon = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseGun = require(Locations.Modules.Weapons.Actions.Gun.BaseGun)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

--[[
	============================================================================
	INITIALIZATION
	============================================================================
	Called when the weapon is first created for a player.
	Use this to set up any weapon-specific state.
]]
function TemplateWeapon.Initialize(weaponInstance)
	-- Initialize weapon-specific state
	weaponInstance.State.LastFireTime = 0

	-- Example: Custom state for this weapon type
	-- weaponInstance.State.ChargeLevel = 0
	-- weaponInstance.State.OverheatedLevel = 0

	Log:Info("WEAPON", "[TemplateWeapon] Initialized for player: " .. weaponInstance.Player.Name)
end

--[[
	============================================================================
	CAN FIRE CHECK
	============================================================================
	Override this to add weapon-specific firing conditions.
]]
function TemplateWeapon.CanFire(weaponInstance)
	-- Use base gun logic (checks ammo, reload state, etc.)
	if not BaseGun.CanFire(weaponInstance) then
		return false
	end

	-- Add custom conditions here
	-- Example: Check if weapon is overheated
	-- if weaponInstance.State.OverheatedLevel >= 100 then
	--     return false
	-- end

	return true
end

--[[
	============================================================================
	DAMAGE CALCULATION
	============================================================================
	Override to customize damage behavior.
]]
function TemplateWeapon.CalculateDamage(weaponInstance, distance, isHeadshot)
	-- Use base gun damage calculation
	return BaseGun.CalculateDamage(weaponInstance, distance, isHeadshot)
end

--[[
	============================================================================
	HELPER: GET VIEWMODEL CONTROLLER
	============================================================================
	Utility function to safely get the ViewmodelController
]]
function TemplateWeapon.GetViewmodelController()
	return ServiceRegistry:GetController("ViewmodelController")
end

--[[
	============================================================================
	EXAMPLE: PLAY CUSTOM ANIMATION
	============================================================================
	Shows how to play a viewmodel animation from within the weapon module
]]
function TemplateWeapon.PlayCustomAnimation(animationName)
	local ViewmodelController = TemplateWeapon.GetViewmodelController()
	if ViewmodelController then
		ViewmodelController:PlayAnimation(animationName)
		return true
	end
	return false
end

--[[
	============================================================================
	EXAMPLE: APPLY CUSTOM RECOIL
	============================================================================
	Shows how to apply recoil to the viewmodel
]]
function TemplateWeapon.ApplyCustomRecoil(pitchAmount, yawAmount)
	local ViewmodelController = TemplateWeapon.GetViewmodelController()
	if ViewmodelController and ViewmodelController.ViewmodelEffects then
		ViewmodelController.ViewmodelEffects:ApplyRecoil(pitchAmount, yawAmount)
		return true
	end
	return false
end

--[[
	============================================================================
	EXAMPLE: WAIT FOR ANIMATION TO FINISH
	============================================================================
	Shows how to wait for an animation to complete
]]
function TemplateWeapon.WaitForAnimation(animationName)
	local ViewmodelController = TemplateWeapon.GetViewmodelController()
	if not ViewmodelController then
		return false
	end

	local ViewmodelAnimator = ViewmodelController.ViewmodelAnimator
	if not ViewmodelAnimator then
		return false
	end

	local track = ViewmodelAnimator:GetTrack(animationName)
	if not track then
		Log:Warn("WEAPON", "Animation track not found: " .. animationName)
		return false
	end

	-- Wait for animation to complete
	if track.IsPlaying then
		track.Stopped:Wait()
	end

	return true
end

--[[
	============================================================================
	EXAMPLE: CONNECT TO ANIMATION KEYFRAMES
	============================================================================
	Shows how to react to specific keyframes in animations
	(e.g., play sound when magazine is inserted during reload)
]]
function TemplateWeapon.ConnectToKeyframe(animationName, keyframeName, callback)
	local ViewmodelController = TemplateWeapon.GetViewmodelController()
	if not ViewmodelController then
		return nil
	end

	local ViewmodelAnimator = ViewmodelController.ViewmodelAnimator
	if not ViewmodelAnimator then
		return nil
	end

	local track = ViewmodelAnimator:GetTrack(animationName)
	if not track then
		return nil
	end

	-- Connect to keyframe event
	local connection = track:GetMarkerReachedSignal(keyframeName):Connect(callback)
	return connection
end

return TemplateWeapon
