--[[
	Attack.lua (Shotgun)

	Client-side attack checks + ammo consumption.
	Handles client networking for Shotgun fire.
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

	local fireProfile = weaponInstance.FireProfile or {}
	local pelletDirections = nil
	local pelletsPerShot = fireProfile.pelletsPerShot or config.pelletsPerShot
	if pelletsPerShot and pelletsPerShot > 1 then
		if weaponInstance.GeneratePelletDirections then
			pelletDirections = weaponInstance.GeneratePelletDirections({
				pelletsPerShot = pelletsPerShot,
				spread = fireProfile.spread or 0.15,
			})
		end
	end

	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(pelletDirections ~= nil)
	if hitData and weaponInstance.Net then
		-- Add timestamp to hitData for packet creation
		hitData.timestamp = now
		
		-- For shotgun, we still send pelletDirections for server-side pellet processing
		-- But we also include the buffer packet data for validation
		local packet = HitPacketUtils:CreatePacket(hitData, weaponInstance.WeaponName)
		
		weaponInstance.Net:FireServer("WeaponFired", {
			packet = packet, -- Buffer-based hit packet (35 bytes)
			pelletDirections = pelletDirections, -- For server-side pellet raycasting
			weaponId = weaponInstance.WeaponName, -- Fallback for legacy support
		})

		if weaponInstance.PlayFireEffects then
			weaponInstance.PlayFireEffects(hitData)
		end

		if weaponInstance.RenderTracer then
			if pelletDirections and hitData and hitData.origin then
				local range = (weaponInstance.Config and weaponInstance.Config.range) or 50
				for _, dir in ipairs(pelletDirections) do
					weaponInstance.RenderTracer({
						origin = hitData.origin,
						hitPosition = hitData.origin + dir.Unit * range,
						weaponId = weaponInstance.WeaponName,
					})
				end
			else
				weaponInstance.RenderTracer(hitData)
			end
		end
	end

	return true
end

return Attack
