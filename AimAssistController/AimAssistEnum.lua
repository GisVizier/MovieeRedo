export type AimAssistMethod = "friction" | "tracking" | "centering"
export type AimAssistType = "rotational" | "translational"
export type AimAssistSortingBehavior = "distance" | "angle"
export type AimAssistEasingAttribute = "distance" | "angle" | "normalizedDistance" | "normalizedAngle"

local AimAssistEnum = {
	AimAssistMethod = {
		Friction = "friction" :: AimAssistMethod,
		Tracking = "tracking" :: AimAssistMethod,
		Centering = "centering" :: AimAssistMethod,
	},

	AimAssistType = {
		Rotational = "rotational" :: AimAssistType,
		Translational = "translational" :: AimAssistType,
	},

	AimAssistSortingBehavior = {
		Distance = "distance" :: AimAssistSortingBehavior,
		Angle = "angle" :: AimAssistSortingBehavior,
	},

	AimAssistEasingAttribute = {
		Distance = "distance" :: AimAssistEasingAttribute,
		Angle = "angle" :: AimAssistEasingAttribute,
		NormalizedDistance = "normalizedDistance" :: AimAssistEasingAttribute,
		NormalizedAngle = "normalizedAngle" :: AimAssistEasingAttribute,
	},
}

return AimAssistEnum
