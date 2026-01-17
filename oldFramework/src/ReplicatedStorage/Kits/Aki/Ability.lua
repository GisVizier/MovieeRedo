local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ActiveAbility = require(Locations.Modules.Systems.Kits.ActiveAbility)

local module = {}

function module.new(kitConfig)
	local config = kitConfig.Ability

	local ability = ActiveAbility.new({
		Name = config.Name,
		Cooldown = config.Cooldown,
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
