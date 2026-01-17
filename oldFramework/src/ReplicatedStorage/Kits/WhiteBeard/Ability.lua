local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ActiveAbility = require(Locations.Modules.Systems.Kits.ActiveAbility)

local module = {}

function module.new(kitConfig)
	local config = kitConfig.Ability

	local ability = ActiveAbility.new({
		Name = config.Name,
		Cooldown = 1,
		Duration = 0,

		OnStart = function(self, data)
			if data then
				print("Server received data:", data.TargetPosition)
				-- Server Validation & Damage Logic would go here
				-- VFX is handled by Client!
			end
			self:End()
		end,

		OnEnd = function(self)
		end,

		OnInterrupt = function(self)
		end,
	})

	return ability
end

return module
