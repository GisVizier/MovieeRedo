local EmoteConfig = {}

-- Rarity definitions with colors
EmoteConfig.Rarities = {
	Common = {
		Name = "Common",
		Color = Color3.fromRGB(180, 180, 180),
		Order = 1,
	},
	Rare = {
		Name = "Rare",
		Color = Color3.fromRGB(30, 144, 255),
		Order = 2,
	},
	Epic = {
		Name = "Epic",
		Color = Color3.fromRGB(163, 53, 238),
		Order = 3,
	},
	Legendary = {
		Name = "Legendary",
		Color = Color3.fromRGB(255, 165, 0),
		Order = 4,
	},
	Mythic = {
		Name = "Mythic",
		Color = Color3.fromRGB(255, 0, 85),
		Order = 5,
	},
}

-- Default emote settings
EmoteConfig.Defaults = {
	Loopable = false,
	AllowMove = true,
	Speed = 1,
	FadeInTime = 0.2,
	FadeOutTime = 0.2,
	Priority = Enum.AnimationPriority.Action,
}

-- Cooldown settings
EmoteConfig.Cooldown = {
	Enabled = true,
	Duration = 0.5, -- seconds between emotes
}

-- Get rarity color by name
function EmoteConfig.getRarityColor(rarity: string): Color3
	local rarityData = EmoteConfig.Rarities[rarity]
	if rarityData then
		return rarityData.Color
	end
	return EmoteConfig.Rarities.Common.Color
end

-- Get rarity info by name
function EmoteConfig.getRarityInfo(rarity: string): { Name: string, Color: Color3, Order: number }?
	return EmoteConfig.Rarities[rarity]
end

-- Validate emote ID format
function EmoteConfig.isValidEmoteId(emoteId: any): boolean
	return type(emoteId) == "string" and emoteId ~= ""
end

-- Get all rarity names sorted by order
function EmoteConfig.getRaritiesSorted(): { string }
	local sorted = {}
	for name, _ in EmoteConfig.Rarities do
		table.insert(sorted, name)
	end
	table.sort(sorted, function(a, b)
		return EmoteConfig.Rarities[a].Order < EmoteConfig.Rarities[b].Order
	end)
	return sorted
end

return EmoteConfig
