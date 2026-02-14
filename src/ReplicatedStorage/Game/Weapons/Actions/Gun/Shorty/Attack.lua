local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

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

	local launchVelocity = backward * 24
	local movementController = ServiceRegistry:GetController("Movement")
		or ServiceRegistry:GetController("MovementController")
	if movementController and movementController.BeginExternalLaunch then
		movementController:BeginExternalLaunch(launchVelocity, 0.12)
	else
		root.AssemblyLinearVelocity += launchVelocity
	end
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
