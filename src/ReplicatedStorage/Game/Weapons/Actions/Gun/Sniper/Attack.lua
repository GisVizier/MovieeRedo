--[[
	Attack.lua (Sniper)

	Client-side attack checks + ammo consumption.
	Semi-automatic fire mode.
	Uses buffer-based hit packets for efficient networking.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inspect = require(script.Parent:WaitForChild("Inspect"))
local Special = require(script.Parent:WaitForChild("Special"))
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local HitPacketUtils = require(Locations.Shared.Util:WaitForChild("HitPacketUtils"))

local Attack = {}
local adsRevealToken = 0

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

	local configuredFireRate = tonumber(config.fireRate)
	if not configuredFireRate then
		local fireProfile = config.fireProfile
		if type(fireProfile) == "table" then
			configuredFireRate = tonumber(fireProfile.fireRate)
		end
	end
	if not configuredFireRate or configuredFireRate <= 0 then
		configuredFireRate = 60
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
	if weaponInstance.ApplyState then
		weaponInstance.ApplyState(state)
	end

	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Fire", 0.05, true)
	end
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound("Fire")
	end

	local isADS = Special.IsActive and Special.IsActive() or false
	if isADS and weaponInstance.GetViewmodelController then
		local vm = weaponInstance.GetViewmodelController()
		if vm and vm.SetViewmodelHidden then
			adsRevealToken += 1
			local token = adsRevealToken
			vm:SetViewmodelHidden(false)
			task.delay(0.08, function()
				if token ~= adsRevealToken then
					return
				end
				if Special.IsActive and Special.IsActive() then
					vm:SetViewmodelHidden(true)
				end
			end)
		end
	end
	local ignoreSpread = isADS
	local extraSpreadMultiplier = isADS and 0.2 or 3.4
	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(ignoreSpread, extraSpreadMultiplier)
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
