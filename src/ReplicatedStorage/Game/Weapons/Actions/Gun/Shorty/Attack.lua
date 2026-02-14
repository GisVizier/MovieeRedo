local Players = game:GetService("Players")

local Inspect = require(script.Parent:WaitForChild("Inspect"))

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

local function applyShortyNormalKick()
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

	local downAmount = math.clamp(-look.Y, 0, 1)
	local backwardPower = 24
	local liftPower = 1.5 + (downAmount * 2.75)
	local launchVelocity = (backward * backwardPower) + Vector3.new(0, liftPower, 0)

	local mass = root.AssemblyMass > 0 and root.AssemblyMass or root:GetMass()
	root:ApplyImpulse(launchVelocity * mass)
	root.AssemblyLinearVelocity += launchVelocity * 0.15
end

local Attack = {}

function Attack.Execute(weaponInstance, currentTime)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	Inspect.Cancel()

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local now = currentTime or workspace:GetServerTimeNow()

	if state.Equipped == false then
		return false, "NotEquipped"
	end

	if state.IsReloading then
		return false, "Reloading"
	end

	if (state.CurrentAmmo or 0) <= 0 then
		return false, "NoAmmo"
	end

	local fireInterval = 60 / (config.fireRate or 600)
	if state.LastFireTime and now - state.LastFireTime < fireInterval then
		return false, "Cooldown"
	end

	state.LastFireTime = now
	state.CurrentAmmo = math.max((state.CurrentAmmo or 0) - 1, 0)

	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Fire", 0.05, true)
	end

	local projectileConfig = config.projectile
	local projectileService = getWeaponProjectile()
	if not projectileService then
		return false, "ServiceNotFound"
	end

	if not projectileService._initialized and weaponInstance.Net then
		projectileService:Init(weaponInstance.Net)
		projectileService._initialized = true
	end

	local pelletsPerShot = (projectileConfig and projectileConfig.pelletsPerShot) or config.pelletsPerShot or 8
	local projectileIds = projectileService:FirePellets(weaponInstance, {
		pelletsPerShot = pelletsPerShot,
	})

	if not projectileIds or #projectileIds == 0 then
		return false, "FireFailed"
	end

	if weaponInstance.PlayFireEffects then
		weaponInstance.PlayFireEffects({
			origin = workspace.CurrentCamera.CFrame.Position,
		})
	end

	applyShortyNormalKick()

	return true
end

return Attack
