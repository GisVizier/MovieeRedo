local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KitConfig = require(ReplicatedStorage.Configs.KitConfig)

local KitsUI = {}

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
export type AbilityData = KitConfig.AbilityData
export type PassiveData = KitConfig.PassiveData
export type UltimateData = KitConfig.UltimateData
export type KitData = KitConfig.KitData

KitsUI.RarityInfo = KitConfig.RarityInfo
KitsUI.Kits = KitConfig.Kits

-- Creates and returns a kit card template populated with the given kit data
-- @param kitId: The key in KitsUI.Kits (e.g., "WhiteBeard")
-- @param template: The template instance to clone
-- @return ItemHolder: The populated kit card
function KitsUI.createKitCard(kitId: string): ItemHolder?
	local kitData = KitsUI.Kits[kitId]
	if not kitData then
		warn("[KitsUI] Kit not found: " .. kitId)
		return nil
	end

	local card: ItemHolder = script.Template:Clone()
	card.Name = "Kit_" .. kitId
	card.Visible = true

	local itemFrame = card.Holder.itemFrame
	local holderStuff = itemFrame.HolderStuff

	-- Set kit icon
	holderStuff.Icon.Image = kitData.Icon

	-- Set kit name
	holderStuff.KitText.Text = kitData.Name

	-- Set rarity
	local rarityInfo = KitsUI.RarityInfo[kitData.Rarity]
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
		selectFrame.BackgroundColor3 = rarityInfo.COLOR
	end

	return card
end

-- Gets a kit by its ID
function KitsUI.getKit(kitId: string): KitData?
	return KitsUI.Kits[kitId]
end

-- Gets all kit IDs
function KitsUI.getKitIds(): {string}
	local ids = {}
	for kitId in KitsUI.Kits do
		table.insert(ids, kitId)
	end
	return ids
end

return KitsUI
