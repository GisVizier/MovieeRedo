--[[
	Special.lua (ExecutionerBlade)

	Executioner's Blade special ability - devastating execution strike.
	Long cooldown, high damage potential.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local Inspect = require(script.Parent:WaitForChild("Inspect"))

local Special = {}
Special._isActive = false
Special._isCharging = false

function Special.Execute(weaponInstance, isPressed)
	if not weaponInstance then
		return false, "InvalidInstance"
	end

	local config = weaponInstance.Config
	local cooldownService = weaponInstance.Cooldown

	-- Check cooldown
	if cooldownService and cooldownService:IsOnCooldown("ExecutionerSpecial") then
		return false, "Cooldown"
	end

	if isPressed then
		-- Start charging/windup
		Special._isCharging = true
		Special._isActive = true

		-- Cancel inspect
		Inspect.Cancel()

		-- Play charge animation
		if weaponInstance.PlayAnimation then
			weaponInstance.PlayAnimation("SpecialCharge", 0.1, true)
		end

		-- Optional: Add viewmodel offset during charge
		local viewmodelController = ServiceRegistry:GetController("Viewmodel")
		if viewmodelController then
			Special._resetOffset = viewmodelController:SetOffset(
				CFrame.new(-0.1, 0.1, 0) * CFrame.Angles(math.rad(-10), 0, math.rad(-5))
			)
		end
	else
		-- Release - execute the strike
		if Special._isCharging then
			Special._isCharging = false

			-- Reset viewmodel offset
			if Special._resetOffset then
				Special._resetOffset()
				Special._resetOffset = nil
			end

			-- Play execution animation
			if weaponInstance.PlayAnimation then
				weaponInstance.PlayAnimation("SpecialRelease", 0.05, true)
			end

			-- Start cooldown
			local specialCooldown = config and config.specialCooldown or 5.0
			if cooldownService then
				cooldownService:StartCooldown("ExecutionerSpecial", specialCooldown)
			end

			-- Perform special attack raycast with extended range
			local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(true)
			if hitData and weaponInstance.Net then
				weaponInstance.Net:FireServer("MeleeSpecial", {
					weaponId = weaponInstance.WeaponName,
					timestamp = os.clock(),
					origin = hitData.origin,
					direction = hitData.direction,
					hitPart = hitData.hitPart,
					hitPosition = hitData.hitPosition,
					hitPlayer = hitData.hitPlayer,
					hitCharacter = hitData.hitCharacter,
					isExecution = true,
				})
			end

			-- Reset active state after animation
			task.delay(0.5, function()
				Special._isActive = false
			end)
		end
	end

	return true
end

function Special.Cancel()
	if Special._isCharging then
		Special._isCharging = false
		
		-- Reset viewmodel offset
		if Special._resetOffset then
			Special._resetOffset()
			Special._resetOffset = nil
		end
	end
	
	Special._isActive = false
end

function Special.IsActive()
	return Special._isActive
end

return Special
