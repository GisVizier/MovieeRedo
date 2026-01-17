local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local PassiveAbility = require(Locations.Modules.Systems.Kits.PassiveAbility)

local module = {}

function module.new(kitConfig)
	local ability = PassiveAbility.new({
		Name = "Passive",

		OnStart = function(self)
		end,

		OnInterrupt = function(self)
		end,

		OnKill = function(self, victim)
		end,
	})

	return ability
end

return module
