local KitConfig = {}

KitConfig.Global = {
	DefaultUltChargeRate = 1,
	RespawnResetsCooldowns = true,
	RespawnResetsUltCharge = false,
	DeathInterruptsAbilities = true,
}

KitConfig.Input = {
	AbilityKey = Enum.KeyCode.E,
	UltimateKey = Enum.KeyCode.Q,
	AbilityButton = Enum.UserInputType.MouseButton2,
}

KitConfig.Debugging = {
	LogAbilityActivations = true,
	LogCooldowns = false,
	LogChargeUpdates = false,
}

KitConfig.Kits = {
	WhiteBeard = "Kits.WhiteBeard",
	Mob = "Kits.Mob",
	ChainsawMan = "Kits.ChainsawMan",
	Genji = "Kits.Genji",
	Aki = "Kits.Aki",
}

return KitConfig
