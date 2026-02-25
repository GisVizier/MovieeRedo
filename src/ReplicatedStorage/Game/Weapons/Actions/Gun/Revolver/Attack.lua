--[[
	Attack.lua (Revolver)

	Client-side hitscan attack checks + ammo consumption.
	Semi-automatic fire mode.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inspect = require(script.Parent:WaitForChild("Inspect"))
local Visuals = require(script.Parent:WaitForChild("Visuals"))
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local HitPacketUtils = require(Locations.Shared.Util:WaitForChild("HitPacketUtils"))

local Attack = {}

local runtimeByWeapon = setmetatable({}, { __mode = "k" })

local STANDING_SPEED_THRESHOLD = 1.25
local STANDING_CHAIN_RESET_TIME = 0.45
local SPAM_CHAIN_RESET_TIME = 0.55
local SPAM_SPREAD_STEP = 0.24
local SPAM_RECOIL_STEP = 0.30
local SPAM_SPREAD_MAX = 2.6
local SPAM_RECOIL_MAX = 3.2

local function getRuntime(weaponInstance)
	local runtime = runtimeByWeapon[weaponInstance]
	if not runtime then
		runtime = {
			lastShotTime = 0,
			standingChainShots = 0,
			spamChainShots = 0,
		}
		runtimeByWeapon[weaponInstance] = runtime
	end
	return runtime
end

local function isStandingStillOnGround(player)
	local character = player and player.Character
	if not character then
		return false
	end

	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if horizontalSpeed > STANDING_SPEED_THRESHOLD then
		return false
	end

	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end

	return true
end

function Attack.Execute(weaponInstance, currentTime)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	Inspect.Cancel()

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local now = currentTime or workspace:GetServerTimeNow()
	local runtime = getRuntime(weaponInstance)

	if state.Equipped == false then
		return false, "NotEquipped"
	end

	if state.IsReloading then
		return false, "Reloading"
	end

	if (state.CurrentAmmo or 0) <= 0 then
		return false, "NoAmmo"
	end

	local configuredFireRate = tonumber(config.fireRate)
	if not configuredFireRate then
		local fireProfile = config.fireProfile
		if type(fireProfile) == "table" then
			configuredFireRate = tonumber(fireProfile.fireRate)
		end
	end
	if not configuredFireRate or configuredFireRate <= 0 then
		configuredFireRate = 421
	end
	local fireInterval = 60 / configuredFireRate
	if state.LastFireTime and now - state.LastFireTime < fireInterval then
		return false, "Cooldown"
	end

	state.LastFireTime = now
	if weaponInstance.DecrementAmmo then
		local ok = weaponInstance.DecrementAmmo()
		if not ok then
			return false, "NoAmmo"
		end
		if weaponInstance.GetCurrentAmmo then
			state.CurrentAmmo = weaponInstance.GetCurrentAmmo()
		end
	else
		state.CurrentAmmo = math.max((state.CurrentAmmo or 0) - 1, 0)
	end

	local player = weaponInstance.Player or Players.LocalPlayer
	local standingStill = isStandingStillOnGround(player)
	if now - runtime.lastShotTime > STANDING_CHAIN_RESET_TIME then
		runtime.standingChainShots = 0
	end
	if now - runtime.lastShotTime > SPAM_CHAIN_RESET_TIME then
		runtime.spamChainShots = 0
	end
	runtime.lastShotTime = now
	runtime.spamChainShots += 1
	if standingStill then
		runtime.standingChainShots += 1
	else
		runtime.standingChainShots = 0
	end

	local ignoreSpread = standingStill and runtime.standingChainShots <= 2
	local shotsAfterTwo = math.max(runtime.spamChainShots - 2, 0)
	local spamSpreadScale = 1 + math.min(shotsAfterTwo * SPAM_SPREAD_STEP, SPAM_SPREAD_MAX - 1)
	local spamRecoilScale = 1 + math.min(shotsAfterTwo * SPAM_RECOIL_STEP, SPAM_RECOIL_MAX - 1)
	local crosshairScale = ignoreSpread and 0.2 or spamSpreadScale
	state.ShotSpreadScale = spamSpreadScale
	state.ShotRecoilScale = spamRecoilScale
	state.CrosshairRecoilScale = crosshairScale

	if weaponInstance.ApplyState then
		weaponInstance.ApplyState(state)
	end

	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Fire", 0.05, true)
	end
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound("Fire")
	end

	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(ignoreSpread, spamSpreadScale)
	if hitData and weaponInstance.Net then
		hitData.timestamp = now
		local packet = HitPacketUtils:CreatePacket(hitData, weaponInstance.WeaponName)

		weaponInstance.Net:FireServer("WeaponFired", {
			packet = packet,
			weaponId = weaponInstance.WeaponName,
		})

		if weaponInstance.PlayFireEffects then
			weaponInstance.PlayFireEffects(hitData)
		end
	end

	Visuals.UpdateAmmoVisibility(weaponInstance, state.CurrentAmmo or 0, config.clipSize or 8)

	return true
end

function Attack.Cancel(weaponInstance)
	if not weaponInstance then
		return
	end
	local runtime = getRuntime(weaponInstance)
	runtime.standingChainShots = 0
	runtime.spamChainShots = 0
end

return Attack
