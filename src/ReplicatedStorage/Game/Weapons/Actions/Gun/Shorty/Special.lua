local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))
local Inspect = require(script.Parent:WaitForChild("Inspect"))

local Special = {}
Special._isADS = false
Special._originalFOV = nil

local WeaponProjectile
local function getWeaponProjectile()
	if not WeaponProjectile then
		local Controllers = Players.LocalPlayer
			:WaitForChild("PlayerScripts")
			:WaitForChild("Initializer")
			:WaitForChild("Controllers")
		local WeaponServices = Controllers:WaitForChild("Weapon"):WaitForChild("Services")
		WeaponProjectile = require(WeaponServices:WaitForChild("WeaponProjectile"))
	end
	return WeaponProjectile
end

local function applySpecialBlastRecoil(weaponInstance)
	local weaponController = ServiceRegistry:GetController("Weapon")
		or ServiceRegistry:GetController("WeaponController")
	if not weaponController then
		return
	end

	local bursts = 2
	local config = weaponInstance and weaponInstance.Config
	if config and type(config.specialRecoilBursts) == "number" then
		bursts = math.clamp(math.floor(config.specialRecoilBursts), 1, 4)
	end

	if type(weaponController._applyCameraRecoil) == "function" then
		for _ = 1, bursts do
			weaponController:_applyCameraRecoil()
		end
	end

	if type(weaponController._applyCrosshairRecoil) == "function" then
		weaponController:_applyCrosshairRecoil()
	end
end

function Special.Execute(weaponInstance, isPressed)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	if weaponInstance.State.IsReloading then
		if Special._isADS then
			Special.Cancel()
		end
		return false, "Reloading"
	end

	if isPressed then
		Inspect.Cancel()
	end

	local ammo = weaponInstance.State.CurrentAmmo or 0

	-- 1 ammo (or 0): keep normal ADS behavior.
	if ammo < 2 then
		Special._isADS = isPressed
		if Special._isADS then
			Special:_enterADS(weaponInstance)
		else
			Special:_exitADS(weaponInstance)
		end
		return true
	end

	-- 2+ ammo: special is a press action (rocket jump + blast), not hold ADS.
	if not isPressed then
		return true
	end

	Special._isADS = false
	Special:_exitADS(weaponInstance)

	return Special:_executeRocketJumpBlast(weaponInstance)
end

function Special:_executeRocketJumpBlast(weaponInstance)
	local state = weaponInstance.State
	local config = weaponInstance.Config

	if state.IsReloading then
		return false, "Reloading"
	end

	if (state.CurrentAmmo or 0) < 2 then
		return false, "NoAmmo"
	end

	-- Consume both shells.
	state.CurrentAmmo = math.max((state.CurrentAmmo or 0) - 2, 0)
	state.LastFireTime = workspace:GetServerTimeNow()

	if weaponInstance.ApplyState then
		weaponInstance.ApplyState(state)
	end

	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Fire", 0.05, true)
	end
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound("Special")
	end

	local projectileService = getWeaponProjectile()
	if not projectileService then
		return false, "ServiceNotFound"
	end

	if not projectileService._initialized and weaponInstance.Net then
		projectileService:Init(weaponInstance.Net)
		projectileService._initialized = true
	end

	-- Special blast: 16 pellets, flagged for max-damage treatment server-side.
	local projectileIds = projectileService:FirePellets(weaponInstance, {
		pelletsPerShot = 16,
		isRocketSpecial = true,
	})
	if not projectileIds or #projectileIds == 0 then
		return false, "FireFailed"
	end

	if weaponInstance.PlayFireEffects then
		weaponInstance.PlayFireEffects({
			origin = workspace.CurrentCamera.CFrame.Position,
		})
	end

	applySpecialBlastRecoil(weaponInstance)
	Special:_applyRocketJumpVelocity()
	return true
end

function Special:_applyRocketJumpVelocity()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return
	end

	local look = camera.CFrame.LookVector
	local backward = -look
	if backward.Magnitude < 0.001 then
		backward = -root.CFrame.LookVector
	end
	backward = backward.Unit

	root.AssemblyLinearVelocity *= Vector3.new(1, 0, 1)

	local movementController = ServiceRegistry:GetController("Movement")
		or ServiceRegistry:GetController("MovementController")
	local currentVelocity = root.AssemblyLinearVelocity
	local isGrounded = movementController and movementController.IsCharacterGrounded and movementController:IsCharacterGrounded()
		or false
	local downAimFactor = math.clamp(-look.Y, 0, 1)

	local launchVelocity = backward * 78

	-- Looking downward should trade some backward push for more vertical lift.
	local horizontalScale = 1 - (0.5 * downAimFactor)
	launchVelocity = Vector3.new(launchVelocity.X * horizontalScale, launchVelocity.Y, launchVelocity.Z * horizontalScale)

	-- If grounded or not rising, reduce backward push so it doesn't throw you too far back.
	if isGrounded or currentVelocity.Y <= 0 then
		launchVelocity = Vector3.new(launchVelocity.X * 0.72, launchVelocity.Y, launchVelocity.Z * 0.72)
	end

	-- Downward aim curve: even angled-down gives solid lift; straight-down gives max height.
	local downLiftCurve = downAimFactor ^ 0.7
	local upBonus = isGrounded and (22 + 18 * downLiftCurve) or (28 + 24 * downLiftCurve)
	local upCap = isGrounded and 58 or 150
	launchVelocity = Vector3.new(launchVelocity.X, math.min(launchVelocity.Y + upBonus, upCap), launchVelocity.Z)

	-- Clear existing movement so special launch always starts from a clean velocity state.
	-- root.AssemblyLinearVelocity = Vector3.zero

	if movementController and movementController.BeginExternalLaunch then
		movementController:BeginExternalLaunch(launchVelocity, 0.28)
	else
		root.AssemblyLinearVelocity = launchVelocity
	end

end

function Special:_enterADS(weaponInstance)
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return
	end

	local config = weaponInstance.Config
	local adsFOV = config and config.adsFOV
	local adsTransitionSpeed = config and config.adsTransitionSpeed or 0.12
	local adsEffectsMultiplier = config and config.adsEffectsMultiplier or 0.25

	viewmodelController:SetADS(true, adsTransitionSpeed, adsEffectsMultiplier)

	if adsFOV then
		Special._originalFOV = FOVController.BaseFOV
		FOVController:SetBaseFOV(adsFOV)
	end

	local adsSpeedMult = config and config.adsSpeedMultiplier or 0.7
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(adsSpeedMult)
	end

	if weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack("ADS", 0.15)
	end
end

function Special:_exitADS(weaponInstance)
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if viewmodelController then
		viewmodelController:SetADS(false)
	end

	if Special._originalFOV then
		FOVController:SetBaseFOV(Special._originalFOV)
		Special._originalFOV = nil
	end

	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(1.0)
	end

	if weaponInstance and weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack("Hip", 0.15)
	end
end

function Special.Cancel()
	local shouldExitADS = Special._isADS or Special._originalFOV ~= nil
	if not shouldExitADS then
		return
	end

	Special._isADS = false
	Special:_exitADS(nil)
end

function Special.IsActive()
	return Special._isADS
end

return Special
