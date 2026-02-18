--[[
	Data store configuration for Anime FPS.
	Bump StoreVersion when making breaking schema changes (invalidates old profiles).
]]

return {
	DataStore = {
		StoreVersion = 1,
		Disabled = false, -- Set true for Studio testing without DataStore
	},
}
