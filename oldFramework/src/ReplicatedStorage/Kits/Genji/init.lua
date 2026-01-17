local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local BaseKit = require(Locations.Modules.Systems.Kits.BaseKit)

local module = {}

module.Config = {
	Settings = {
		Name = "Genji",
		Description = "A fallen soul rebuilt with experimental robotics, moving with silent precision and impossible speed.",
	},

	Passive = {
		Name = "Cyber-Agility",
		PassiveType = "Movement",
	},

	Ability = {
		Name = "Deflect",
		Cooldown = 8,
	},

	Ultimate = {
		Name = "Dragonblade",
		RequiredCharge = 100,
		Damage = 65,
		DamageType = "Melee",
	},
}

function module.new()
	local Passive = require(script.Passive)
	local Ability = require(script.Ability)
	local Ultimate = require(script.Ultimate)

	local kit = BaseKit.new({
		Name = module.Config.Settings.Name,
		Description = module.Config.Settings.Description,
		Passive = Passive.new(module.Config),
		Ability = Ability.new(module.Config),
		Ultimate = Ultimate.new(module.Config),
	})

	return kit
end

return module
