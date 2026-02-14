local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))

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

function Special.Execute(weaponInstance, isPressed)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
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

	Special:_applyRocketJumpVelocity()
	return true
end

function Special:_applyRocketJumpVelocity()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return
	end

	local look = camera.CFrame.LookVector
	local backward = Vector3.new(-look.X, 0, -look.Z)
	if backward.Magnitude < 0.001 then
		backward = Vector3.new(-root.CFrame.LookVector.X, 0, -root.CFrame.LookVector.Z)
	end
	backward = backward.Unit

	local boostBack = 95
	local boostUp = 60
	local launchVelocity = (backward * boostBack) + Vector3.new(0, boostUp, 0)

	-- Impulse is more reliable than direct velocity writes with this movement controller.
	local mass = root.AssemblyMass > 0 and root.AssemblyMass or root:GetMass()
	root:ApplyImpulse(launchVelocity * mass)

	-- Small fallback nudge to help if constraints damp the impulse quickly.
	root.AssemblyLinearVelocity *= Vector3.yAxis * 200
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
	if not Special._isADS then
		return
	end

	Special._isADS = false
	Special:_exitADS(nil)
end

function Special.IsActive()
	return Special._isADS
end

return Special
