--[[
	Template Emote Module
	
	This is an example emote module showing the structure for creating new emotes.
	Copy this file and modify for each new emote.
	
	ANIMATIONS:
	Define animation IDs directly in the Animations table below.
	These are preloaded when the EmoteService initializes.
	
	OPTIONAL ASSETS (for sounds/VFX):
	Asset Location: Assets/Animations/Emotes/{EmoteId}/
	Structure:
	- Sound/        Optional sound effects
	- VFX/          Optional visual effects (future)
	
	USAGE:
	1. Copy this file to Game/Emotes/Emotes/{YourEmoteId}.lua
	2. Rename "Template" to your emote name throughout
	3. Set the Id for this emote
	4. Add animation IDs to the Animations table
	5. Configure DisplayName, Rarity, and behavior settings
]]

local EmoteBase = require(script.Parent.Parent.EmoteBase)

local Template = setmetatable({}, { __index = EmoteBase })
Template.__index = Template

--[[ REQUIRED SETTINGS ]]--

-- Unique identifier - MUST match the folder name in Assets/Animations/Emotes/
Template.Id = "Template"

-- Display name shown in the emote wheel UI
Template.DisplayName = "Template Emote"

-- Rarity tier: Common, Rare, Epic, Legendary, Mythic
Template.Rarity = "Common"

--[[ ANIMATIONS TABLE ]]--
-- Define animation IDs here for preloading and playback
-- The EmoteService will preload these when it initializes
Template.Animations = {
	Main = "rbxassetid://140073348012061", -- Primary emote animation
	-- Add more animation keys as needed:
	-- Intro = "rbxassetid://...",
	-- Loop = "rbxassetid://...",
	-- Outro = "rbxassetid://...",
}

--[[ BEHAVIOR SETTINGS ]]--

-- If true, animation loops until manually stopped
-- If false, emote ends when animation completes
Template.Loopable = false

-- If true, player can move while emoting
-- If false, movement cancels the emote
Template.AllowMove = true

-- Animation playback speed multiplier (1 = normal)
Template.Speed = 1

--[[ OPTIONAL: Animation timing overrides ]]--
-- Template.FadeInTime = 0.2   -- Seconds to fade in animation
-- Template.FadeOutTime = 0.2  -- Seconds to fade out animation

--[[ OPTIONAL: Custom constructor ]]--
-- Override new() for custom setup like spawning props
function Template.new(emoteId, emoteData, rig)
	local self = EmoteBase.new(emoteId, emoteData, rig)
	setmetatable(self, Template)
	
	-- Custom initialization here
	-- Example: self._prop = nil
	
	return self
end

--[[ OPTIONAL: Custom start behavior ]]--
-- Override start() for pre-animation logic
function Template:start()
	-- Custom pre-start logic here
	-- Example: spawn props, play intro sound, etc.
	
	return EmoteBase.start(self)
end

--[[ OPTIONAL: Custom stop behavior ]]--
-- Override stop() for cleanup logic
function Template:stop()
	-- Custom cleanup logic here
	-- Example: remove props, play outro sound, etc.
	
	return EmoteBase.stop(self)
end

return Template
