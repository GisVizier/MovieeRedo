--[[
	Data store configuration for Anime FPS.
	Bump StoreVersion when making breaking schema changes (invalidates old profiles).
]]

return {
	DataStore = {
		StoreVersion = 2, -- Bumped: wipe profiles for Aim Assist/Auto Shoot defaults (console/mobile = YES)
		Disabled = false, -- Set true for Studio testing without DataStore
	},
}
