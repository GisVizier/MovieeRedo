--[[
	UserSettings
	Stores and manages user-customizable settings that persist during the session.
	Values default to Config but can be overridden by user preferences.

	DISABLED: This module is currently disabled and saved for later custom UI integration.
	Uncomment and update when implementing new settings UI.
]]

--[[
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local LogService = require(Locations.Modules.Systems.Core.LogService)

local UserSettings = {}

-- Initialize default keybinds from ControlsConfig (dual slot system)
local function InitializeKeybindDefaults()
	local keybinds = {}
	for _, keybindInfo in ipairs(Config.Controls.CustomizableKeybinds) do
		keybinds["Keybind_" .. keybindInfo.Key .. "_Primary"] = keybindInfo.DefaultPrimary
		keybinds["Keybind_" .. keybindInfo.Key .. "_Secondary"] = keybindInfo.DefaultSecondary
	end
	return keybinds
end

-- Storage for user settings (defaults to Config values)
UserSettings._settings = {
	FieldOfView = Config.Controls.Camera.FieldOfView,
	BodyPartTransparency = Config.Controls.Camera.BodyPartTransparency,
	DisableDirectionalSliding = false,
	DisableCameraTransition = false,
}

-- Initialize keybind defaults
for key, value in pairs(InitializeKeybindDefaults()) do
	UserSettings._settings[key] = value
end

-- BindableEvent to notify listeners when settings change
local SettingsChanged = Instance.new("BindableEvent")
UserSettings.SettingsChanged = SettingsChanged.Event

function UserSettings:Get(key)
	return self._settings[key]
end

function UserSettings:Set(key, value)
	if self._settings[key] == value then
		return -- No change
	end

	-- Keybind conflict resolution - unbind other actions using the same key
	if key:match("^Keybind_") and value ~= nil then
		self:ResolveKeybindConflict(key, value)
	end

	self._settings[key] = value
	LogService:Debug("USER_SETTINGS", "Setting updated", { Key = key, Value = value })

	-- Fire change event
	SettingsChanged:Fire(key, value)
end

-- Unbinds any other keybind that conflicts with the new value
function UserSettings:ResolveKeybindConflict(settingKey, newValue)
	for existingKey, existingValue in pairs(self._settings) do
		-- Skip the key we're currently setting
		if existingKey ~= settingKey and existingKey:match("^Keybind_") then
			-- If another keybind uses the same input, unbind it
			if existingValue == newValue then
				self._settings[existingKey] = nil
				LogService:Debug("USER_SETTINGS", "Keybind conflict resolved - unbound previous binding", {
					UnboundKey = existingKey,
					ConflictingInput = tostring(newValue),
				})
				-- Fire change event for the unbound key
				SettingsChanged:Fire(existingKey, nil)
			end
		end
	end
end

function UserSettings:GetAll()
	return self._settings
end

return UserSettings
]]

-- Temporary stub to prevent errors from existing code
return {}
