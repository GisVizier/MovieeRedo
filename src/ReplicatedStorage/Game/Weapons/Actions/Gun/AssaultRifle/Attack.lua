--[[
	Attack.lua (AssaultRifle)

	Client-side attack checks + ammo consumption.
	Handles automatic fire mode.
	Uses buffer-based hit packets for efficient networking.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inspect = require(script.Parent:WaitForChild("Inspect"))
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local HitPacketUtils = require(Locations.Shared.Util:WaitForChild("HitPacketUtils"))

local Attack = {}

function Attack.Execute(weaponInstance, currentTime)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	-- Cancel any active inspect
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

	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(false)
	if hitData and weaponInstance.Net then
		-- Add timestamp for packet creation
		hitData.timestamp = now
		
		-- Create buffer packet for efficient networking
		local packet = HitPacketUtils:CreatePacket(hitData, weaponInstance.WeaponName)
		
		weaponInstance.Net:FireServer("WeaponFired", {
			packet = packet,
			weaponId = weaponInstance.WeaponName,
		})

		if weaponInstance.PlayFireEffects then
			weaponInstance.PlayFireEffects(hitData)
		end
	end

	return true
end

return Attack
