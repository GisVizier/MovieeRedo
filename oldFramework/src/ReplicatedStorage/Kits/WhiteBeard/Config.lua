return {
	Settings = {
		Name = "WhiteBeard",
		Description = "A colossal warrior whose titan-hammer cracks the earth, creating earthquakes and disasters.",
	},

	Ability = {
		Name = "Quake Ball",
		Cooldown = 8,
		Damage = 45,
		DamageType = "Projectile",
		Animations = {
			Charge = "rbxassetid://117704637566986",
			Release = "rbxassetid://122490395544502",
		},
	},

	Ultimate = {
		Name = "Gura Gura No Mi",
		RequiredCharge = 100,
		Damage = 120,
		DamageType = "AOE",
		Animations = {
			Activate = "rbxassetid://116014965112574",
		},
	},

	Animations = {
		Viewmodel = {
			AbilityCharge = "rbxassetid://117704637566986",
			AbilityRelease = "rbxassetid://122490395544502",
			Ultimate = "rbxassetid://116014965112574",
		},
		Character = {
		},
	},
}
