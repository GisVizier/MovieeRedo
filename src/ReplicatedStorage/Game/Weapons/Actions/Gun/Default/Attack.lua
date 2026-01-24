--[[
	Attack.lua (Default)

	Default client-side attack implementation for guns.
	Uses buffer-based hit packets for efficient networking.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local HitPacketUtils = require(Locations.Shared.Util:WaitForChild("HitPacketUtils"))

local Attack = {}

function Attack.Execute(weaponInstance, currentTime)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local now = currentTime or workspace:GetServerTimeNow()

	if state.Equipped == false then
		return false, "NotEquipped"
	end

	if state.IsReloading then
		if (state.CurrentAmmo or 0) > 0 and weaponInstance.CancelReload then
			weaponInstance.CancelReload()
		else
			return false, "Reloading"
		end
	end

	if (state.CurrentAmmo or 0) <= 0 then
		return false, "NoAmmo"
	end

	local fireInterval = 60 / (config.fireRate or 600)
	if state.LastFireTime and now - state.LastFireTime < fireInterval then
		return false, "Cooldown"
	end

	state.LastFireTime = now

	if weaponInstance.DecrementAmmo then
		weaponInstance.DecrementAmmo()
	end
	if weaponInstance.GetCurrentAmmo then
		state.CurrentAmmo = weaponInstance.GetCurrentAmmo()
	else
		state.CurrentAmmo = math.max((state.CurrentAmmo or 0) - 1, 0)
	end

	local fireProfile = weaponInstance.FireProfile or {}
	local pelletDirections = nil
	if fireProfile.mode == "Shotgun" and (fireProfile.pelletsPerShot or 0) > 1 then
		if weaponInstance.GeneratePelletDirections then
			pelletDirections = weaponInstance.GeneratePelletDirections({
				pelletsPerShot = fireProfile.pelletsPerShot,
				spread = fireProfile.spread or 0.15,
			})
		end
	end

	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(pelletDirections ~= nil)
	if hitData then
		-- Add timestamp for packet creation
		hitData.timestamp = now
		
		-- Create buffer packet
		local packet = HitPacketUtils:CreatePacket(hitData, weaponInstance.WeaponName)
		
		if weaponInstance.Net then
			weaponInstance.Net:FireServer("WeaponFired", {
				packet = packet,
				pelletDirections = pelletDirections,
				weaponId = weaponInstance.WeaponName,
			})
		end
		
		if weaponInstance.PlayFireEffects then
			weaponInstance.PlayFireEffects(hitData)
		end
	end

	return true
end

return Attack
