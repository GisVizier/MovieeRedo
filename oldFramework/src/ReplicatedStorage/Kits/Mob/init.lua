local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local BaseKit = require(Locations.Modules.Systems.Kits.BaseKit)

local module = {}

module.Config = {
	Settings = {
		Name = "Mob",
		Description = "A quiet student with sealed psychic power who avoids conflict.",
	},

	Ability = {
		Name = "Aegis Wall",
		Cooldown = 10,
		Damage = 32.5,
		DamageType = "AOE",
	},

	Ultimate = {
		Name = "???",
		RequiredCharge = 100,
		DamageType = "Grab",
	},
}

function module.new()
	local Ability = require(script.Ability)
	local Ultimate = require(script.Ultimate)

	local kit = BaseKit.new({
		Name = module.Config.Settings.Name,
		Description = module.Config.Settings.Description,
		Ability = Ability.new(module.Config),
		Ultimate = Ultimate.new(module.Config),
	})

	return kit
end

return module
