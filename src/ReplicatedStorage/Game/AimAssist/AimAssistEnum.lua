--[[
	AimAssistEnum.lua
	
	Type definitions and enums for the Aim Assist system.
]]

export type AimAssistMethod = "friction" | "tracking" | "centering"
export type AimAssistType = "rotational" | "translational"
export type AimAssistSortingBehavior = "distance" | "angle"
export type AimAssistEasingAttribute = "distance" | "angle" | "normalizedDistance" | "normalizedAngle"

local AimAssistEnum = {
	-- Methods of aim assist
	AimAssistMethod = {
		Friction = "friction" :: AimAssistMethod,    -- Slows input near targets
		Tracking = "tracking" :: AimAssistMethod,    -- Follows moving targets
		Centering = "centering" :: AimAssistMethod,  -- Pulls aim toward target
	},

	-- How aim assist transforms the subject
	AimAssistType = {
		Rotational = "rotational" :: AimAssistType,       -- Rotates (for cameras)
		Translational = "translational" :: AimAssistType, -- Moves position (for projectiles)
	},

	-- How to prioritize between multiple targets
	AimAssistSortingBehavior = {
		Distance = "distance" :: AimAssistSortingBehavior,  -- Closest target
		Angle = "angle" :: AimAssistSortingBehavior,        -- Target nearest to crosshair
	},

	-- Attributes for easing functions
	AimAssistEasingAttribute = {
		Distance = "distance" :: AimAssistEasingAttribute,
		Angle = "angle" :: AimAssistEasingAttribute,
		NormalizedDistance = "normalizedDistance" :: AimAssistEasingAttribute,
		NormalizedAngle = "normalizedAngle" :: AimAssistEasingAttribute,
	},
}

return AimAssistEnum
