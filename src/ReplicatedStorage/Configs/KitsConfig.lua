local KitsConfig = {}

-- Type definition for kit card template (in Hud ScrollingFrame)
export type ItemHolder = Frame & {
	UIScale: UIScale,

	Holder: Frame & {
		UIStroke: UIStroke,
		Button: ImageButton,
		itemFrame: Frame & {
			HolderStuff: Frame & {
				icon: ImageLabel,
				KitText: TextLabel,

				Rarity: CanvasGroup & {
					UICorner: UICorner,
					UIStroke: UIStroke & {
						UIGradient: UIGradient,
					},

					RarityText: TextLabel & {
						UIGradient: UIGradient,
					},
				},
			},

			BG: CanvasGroup & {
				UIGradient: UIGradient,
			},

			Select: Frame & {
				UIGradient: UIGradient,
			},

			LowBar: CanvasGroup & {
				KitIcon: ImageLabel,
			},
		},
	},
}

-- Type definitions for kit data structure
export type AbilityData = {
	Name: string,
	Description: string,
	Video: string?,
	Damage: number?,
	DamageType: string?,
	Destruction: string?,
}

export type PassiveData = {
	Name: string,
	Description: string,
	Video: string?,
	PassiveType: string?,
}

export type UltimateData = {
	Name: string,
	Description: string,
	Video: string?,
	Damage: number?,
	DamageType: string?,
	Destruction: string?,
}

export type KitData = {
	Icon: string,
	Name: string,
	Description: string,
	Rarity: string,
	Ability: AbilityData?,
	Passive: PassiveData?,
	Ultimate: UltimateData?,
}

KitsConfig.RarityInfo = {
	Legendary = {
		TEXT = "LEGENDARY",
		COLOR = Color3.fromRGB(255, 209, 43),
	},

	Mythic = {
		TEXT = "MYTHIC",
		COLOR = Color3.fromRGB(255, 67, 70),
	},
	
	Epic = {
		TEXT = "EPIC",
		COLOR = Color3.fromRGB(180, 76, 255),
	},
	
	Rare = {
		TEXT = "RARE",
		COLOR = Color3.fromRGB(66, 123, 255),
	},
	
	Common = {
		TEXT = "COMMON",
		COLOR = Color3.fromRGB(77, 79, 83),
	},

}

KitsConfig.Kits = {
	WhiteBeard = {
		Icon = "rbxassetid://72158182932036",
		Name = "WHITE BEARD",
		Description = "A colossal warrior whose titan-hammer cracks the earth, creating earthquakes and disasters, a fortress to his crew and a living catastrophe to his enemies.",
		Rarity = "Legendary",
		Price = 1250,

		Ability = {
			Name = "QUAKE BALL",
			Description = "Condenses seismic energy into a crackling sphere and fires it straight ahead. It rips through terrain and structures, crushing enemies with a collapsing shockwave and flinging survivors back.",
			Video = "",
			Damage = 45,
			DamageType = "Projectile",
			Destruction = "Huge",
			Cooldown = 8,
		},

		Ultimate = {
			Name = "GURA GURA NO MI",
			Description = "Unleash the full power of the tremor fruit, shattering the battlefield with devastating quakes.",
			Video = "",
			Damage = 120,
			DamageType = "AOE",
			Destruction = "Mega",
			UltCost = 100,
		},
	},

	Mob = {
		Icon = "rbxassetid://88925605827431",
		Name = "MOB",
		Description = "A quiet student with sealed psychic power who avoids conflict, afraid it will surge out of control. When someone he cares about is threatened, that power erupts and changes everything.",
		Rarity = "Epic",
		Price = 450,

		Ability = {
			Name = "Aegis Wall",
			Description = "Raise a massive wall that blocks bullets and abilities, protecting you and your allies. It's highly durable and can be angled or positioned exactly where you need it.",
			Video = "",
			Damage = 32.5,
			DamageType = "AOE",
			Destruction = "Big",
			Cooldown = 10,
		},

		Ultimate = {
			Name = "???",
			Description = "No one knows what you become when rage climbs this high. Something inside you wakes up, and the battlefield learns to fear it.",
			Video = "",
			DamageType = "Grab",
			Destruction = "Mega",
			UltCost = 100,
		},
	},

	ChainsawMan = {
		Icon = "rbxassetid://81755505866630",
		Name = "CHAINSAW MAN",
		Description = "A feral fighter fused with a chainsaw engine spirit, sprouting blades as his heart revs. He fights to survive, and when pushed too far he becomes a whirlwind of burning steel.",
		Rarity = "Rare",
		Price = 570,

		Ability = {
			Name = "Overdrive Guard",
			Description = "Raise a massive wall that blocks bullets and abilities, protecting you and your allies. It's highly durable and can be angled or positioned exactly where you need it.",
			Video = "",
			Damage = 32.5,
			DamageType = "AOE",
			Destruction = "Big",
			Cooldown = 6,
		},

		Passive = {
			Name = "Blood Fuel",
			Description = "When you fall below 50% health, he enters a Rage State with faster movement and boosted damage. Taking damage extends the rage, letting bold players keep the rampage going.",
			Video = "",
			PassiveType = "Heal",
		},

		Ultimate = {
			Name = "DEVIL TRIGGER",
			Description = "Transform into a full devil form, gaining massive damage and lifesteal for a short duration.",
			Video = "",
			Damage = 80,
			DamageType = "Melee",
			Destruction = "Huge",
			UltCost = 100,
		},
	},

	Genji = {
		Icon = "rbxassetid://107097170907543",
		Name = "GENJI",
		Description = "A fallen soul rebuilt with experimental robotics, moving with silent precision and impossible speed. A blur of steel and neon, he fights with honor, efficiency, and unbreakable resolve.",
		Rarity = "Common",
		Price = 12570,

		Ability = {
			Name = "Deflect",
			Description = "Deflect incoming projectiles back at enemies.",
			Video = "",
			Cooldown = 8,
		},

		Passive = {
			Name = "Cyber-Agility",
			Description = "Double Jump and dashing",
			Video = "",
			PassiveType = "Movement",
		},

		Ultimate = {
			Name = "DRAGONBLADE",
			Description = "Unsheathe the dragonblade for devastating melee attacks.",
			Video = "",
			Damage = 65,
			DamageType = "Melee",
			Destruction = "Big",
			UltCost = 100,
		},
	},

	Aki = {
		Icon = "rbxassetid://136186193137355",
		Name = "AKI",
		Description = "A disciplined fighter who makes binding deals with spirits and devils, gaining power at the cost of pain, stamina, and pieces of his soul. He fights with calm precision, as if he already knows the ending, weaving swordplay with deadly spectral techniques.",
		Rarity = "Mythic",
		Price = 12570,

		Ability = {
			Name = "KON",
			Description = "Call your Devil to rush in, deliver a vicious bite, and then vanish in a burst of smoke. Enemies are hurt and the area is clouded, giving you cover to move or strike.",
			Video = "",
			Damage = 32.5,
			DamageType = "AOE",
			Destruction = "Big",
			Cooldown = 7,
		},

		Passive = {
			Name = "TELEPORT",
			Description = "When you defeat a player, the Teleport Devil marks their death site. Activate the mark to instantly warp back to that spot, turning every kill into a doorway.",
			Video = "",
			PassiveType = "Movement",
		},

		Ultimate = {
			Name = "FATE",
			Description = "When you fall, time rewinds for you alone, restoring you to moments before death. Retrace your steps and defeat your attacker, or your original fate will claim you again.",
			Video = "",
			UltCost = 100,
		},
	},
}

-- Creates and returns a kit card template populated with the given kit data
-- @param kitId: The key in KitsConfig.Kits (e.g., "WhiteBeard")
-- @param template: The template instance to clone
-- @return ItemHolder: The populated kit card
function KitsConfig.createKitCard(kitId: string): ItemHolder?
	local kitData = KitsConfig.Kits[kitId]
	if not kitData then
		warn("[KitsConfig] Kit not found: " .. kitId)
		return nil
	end

	local card: ItemHolder = script.Template:Clone()
	card.Name = "Kit_" .. kitId
	card.Visible = true

	local itemFrame = card.Holder.itemFrame
	local holderStuff = itemFrame.HolderStuff

	-- Set kit icon
	--warn(holderStuff, card)
	holderStuff.Icon.Image = kitData.Icon

	-- Set kit name
	holderStuff.KitText.Text = kitData.Name

	-- Set rarity
	local rarityInfo = KitsConfig.RarityInfo[kitData.Rarity]
	if rarityInfo then
		holderStuff.Rarity.RarityText.Text = rarityInfo.TEXT

		-- Apply rarity color to the stroke gradient
		local rarityStroke = holderStuff.Rarity:FindFirstChild("UIStroke")
		if rarityStroke then
			rarityStroke.Color = rarityInfo.COLOR
		end

		-- Apply rarity color to the text gradient
		holderStuff.Rarity.BackgroundColor3 = rarityInfo.COLOR
		card.Holder.UIStroke.Color = rarityInfo.COLOR
		
		
	end

	-- Set low bar kit icon
	local lowBar = itemFrame:FindFirstChild("LowBar")
	if lowBar then
		lowBar.BackgroundColor3 = rarityInfo.COLOR
		local lowBarIcon = lowBar:FindFirstChild("KitIcon")
		if lowBarIcon then
			lowBarIcon.Image = kitData.Icon
		end
	end

	-- Initialize select as hidden
	local selectFrame = itemFrame:FindFirstChild("Select")
	if selectFrame then
		--selectFrame.BackgroundTransparency = 1
		selectFrame.BackgroundColor3 = rarityInfo.COLOR
	end

	return card
end

-- Gets a kit by its ID
function KitsConfig.getKit(kitId: string): KitData?
	return KitsConfig.Kits[kitId]
end

-- Gets all kit IDs
function KitsConfig.getKitIds(): {string}
	local ids = {}
	for kitId in KitsConfig.Kits do
		table.insert(ids, kitId)
	end
	return ids
end

return KitsConfig
