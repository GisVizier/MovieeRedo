local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local BaseKit = require(Locations.Modules.Systems.Kits.BaseKit)

local module = {}

module.Config = {
	Settings = {
		Name = "ChainsawMan",
		Description = "A feral fighter fused with a chainsaw engine spirit, sprouting blades as his heart revs.",
	},

	Passive = {
		Name = "Blood Fuel",
		PassiveType = "Heal",
	},

	Ability = {
		Name = "Overdrive Guard",
		Cooldown = 6,
		Damage = 32.5,
		DamageType = "AOE",
	},

	Ultimate = {
		Name = "Devil Trigger",
		RequiredCharge = 100,
		Damage = 80,
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
