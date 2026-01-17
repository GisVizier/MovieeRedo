local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local BaseKit = require(Locations.Modules.Systems.Kits.BaseKit)

local module = {}

module.Config = {
	Settings = {
		Name = "Aki",
		Description = "A disciplined fighter who makes binding deals with spirits and devils, gaining power at the cost of pain.",
	},

	Passive = {
		Name = "Teleport",
		PassiveType = "Movement",
	},

	Ability = {
		Name = "Kon",
		Cooldown = 7,
		Damage = 32.5,
		DamageType = "AOE",
	},

	Ultimate = {
		Name = "Fate",
		RequiredCharge = 100,
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
