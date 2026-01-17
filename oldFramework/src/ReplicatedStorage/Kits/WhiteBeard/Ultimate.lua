local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local UltimateAbility = require(Locations.Modules.Systems.Kits.UltimateAbility)

local module = {}

function module.new(kitConfig)
	local config = kitConfig.Ultimate

	local ability = UltimateAbility.new({
		Name = config.Name,
		RequiredCharge = config.RequiredCharge,
		Duration = 0,

		OnStart = function(self)
		end,

		OnEnd = function(self)
		end,

		OnInterrupt = function(self)
		end,
	})

	return ability
end

return module
