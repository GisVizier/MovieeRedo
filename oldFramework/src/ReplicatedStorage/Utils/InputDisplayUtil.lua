--[[
	InputDisplayUtil
	Utility for converting Roblox KeyCode and UserInputType enums to user-friendly display names.
]]

local InputDisplayUtil = {}

-- Map of KeyCode enums to readable display names
InputDisplayUtil.KeyCodeNames = {
	-- Letters
	[Enum.KeyCode.A] = "A",
	[Enum.KeyCode.B] = "B",
	[Enum.KeyCode.C] = "C",
	[Enum.KeyCode.D] = "D",
	[Enum.KeyCode.E] = "E",
	[Enum.KeyCode.F] = "F",
	[Enum.KeyCode.G] = "G",
	[Enum.KeyCode.H] = "H",
	[Enum.KeyCode.I] = "I",
	[Enum.KeyCode.J] = "J",
	[Enum.KeyCode.K] = "K",
	[Enum.KeyCode.L] = "L",
	[Enum.KeyCode.M] = "M",
	[Enum.KeyCode.N] = "N",
	[Enum.KeyCode.O] = "O",
	[Enum.KeyCode.P] = "P",
	[Enum.KeyCode.Q] = "Q",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.S] = "S",
	[Enum.KeyCode.T] = "T",
	[Enum.KeyCode.U] = "U",
	[Enum.KeyCode.V] = "V",
	[Enum.KeyCode.W] = "W",
	[Enum.KeyCode.X] = "X",
	[Enum.KeyCode.Y] = "Y",
	[Enum.KeyCode.Z] = "Z",

	-- Numbers (main keyboard)
	[Enum.KeyCode.Zero] = "0",
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
	[Enum.KeyCode.Seven] = "7",
	[Enum.KeyCode.Eight] = "8",
	[Enum.KeyCode.Nine] = "9",

	-- Function keys
	[Enum.KeyCode.F1] = "F1",
	[Enum.KeyCode.F2] = "F2",
	[Enum.KeyCode.F3] = "F3",
	[Enum.KeyCode.F4] = "F4",
	[Enum.KeyCode.F5] = "F5",
	[Enum.KeyCode.F6] = "F6",
	[Enum.KeyCode.F7] = "F7",
	[Enum.KeyCode.F8] = "F8",
	[Enum.KeyCode.F9] = "F9",
	[Enum.KeyCode.F10] = "F10",
	[Enum.KeyCode.F11] = "F11",
	[Enum.KeyCode.F12] = "F12",

	-- Special keys
	[Enum.KeyCode.Space] = "Space",
	[Enum.KeyCode.Return] = "Enter",
	[Enum.KeyCode.Tab] = "Tab",
	[Enum.KeyCode.Backspace] = "Backspace",
	[Enum.KeyCode.Delete] = "Delete",
	[Enum.KeyCode.Insert] = "Insert",
	[Enum.KeyCode.Home] = "Home",
	[Enum.KeyCode.End] = "End",
	[Enum.KeyCode.PageUp] = "Page Up",
	[Enum.KeyCode.PageDown] = "Page Down",
	[Enum.KeyCode.Escape] = "Escape",

	-- Modifiers
	[Enum.KeyCode.LeftShift] = "Left Shift",
	[Enum.KeyCode.RightShift] = "Right Shift",
	[Enum.KeyCode.LeftControl] = "Left Ctrl",
	[Enum.KeyCode.RightControl] = "Right Ctrl",
	[Enum.KeyCode.LeftAlt] = "Left Alt",
	[Enum.KeyCode.RightAlt] = "Right Alt",
	[Enum.KeyCode.LeftSuper] = "Left Super",
	[Enum.KeyCode.RightSuper] = "Right Super",
	[Enum.KeyCode.CapsLock] = "Caps Lock",

	-- Arrow keys
	[Enum.KeyCode.Up] = "Up Arrow",
	[Enum.KeyCode.Down] = "Down Arrow",
	[Enum.KeyCode.Left] = "Left Arrow",
	[Enum.KeyCode.Right] = "Right Arrow",

	-- Keypad
	[Enum.KeyCode.KeypadZero] = "Keypad 0",
	[Enum.KeyCode.KeypadOne] = "Keypad 1",
	[Enum.KeyCode.KeypadTwo] = "Keypad 2",
	[Enum.KeyCode.KeypadThree] = "Keypad 3",
	[Enum.KeyCode.KeypadFour] = "Keypad 4",
	[Enum.KeyCode.KeypadFive] = "Keypad 5",
	[Enum.KeyCode.KeypadSix] = "Keypad 6",
	[Enum.KeyCode.KeypadSeven] = "Keypad 7",
	[Enum.KeyCode.KeypadEight] = "Keypad 8",
	[Enum.KeyCode.KeypadNine] = "Keypad 9",
	[Enum.KeyCode.KeypadPeriod] = "Keypad .",
	[Enum.KeyCode.KeypadEnter] = "Keypad Enter",
	[Enum.KeyCode.KeypadPlus] = "Keypad +",
	[Enum.KeyCode.KeypadMinus] = "Keypad -",
	[Enum.KeyCode.KeypadMultiply] = "Keypad *",
	[Enum.KeyCode.KeypadDivide] = "Keypad /",

	-- Mouse buttons
	[Enum.UserInputType.MouseButton1] = "Left Click",
	[Enum.UserInputType.MouseButton2] = "Right Click",
	[Enum.UserInputType.MouseButton3] = "Middle Click",

	-- Scroll wheel (stored as strings, not enums)
	["ScrollWheelUp"] = "Scroll Wheel Up",
	["ScrollWheelDown"] = "Scroll Wheel Down",

	-- Other
	[Enum.KeyCode.Semicolon] = ";",
	[Enum.KeyCode.Equals] = "=",
	[Enum.KeyCode.Comma] = ",",
	[Enum.KeyCode.Minus] = "-",
	[Enum.KeyCode.Period] = ".",
	[Enum.KeyCode.Slash] = "/",
	[Enum.KeyCode.Backquote] = "`",
	[Enum.KeyCode.LeftBracket] = "[",
	[Enum.KeyCode.BackSlash] = "\\",
	[Enum.KeyCode.RightBracket] = "]",
	[Enum.KeyCode.Quote] = "'",

	-- Controller buttons
	[Enum.KeyCode.ButtonA] = "A Button",
	[Enum.KeyCode.ButtonB] = "B Button",
	[Enum.KeyCode.ButtonX] = "X Button",
	[Enum.KeyCode.ButtonY] = "Y Button",
	[Enum.KeyCode.ButtonL1] = "L1",
	[Enum.KeyCode.ButtonL2] = "L2",
	[Enum.KeyCode.ButtonL3] = "L3",
	[Enum.KeyCode.ButtonR1] = "R1",
	[Enum.KeyCode.ButtonR2] = "R2",
	[Enum.KeyCode.ButtonR3] = "R3",
	[Enum.KeyCode.ButtonStart] = "Start",
	[Enum.KeyCode.ButtonSelect] = "Select",
	[Enum.KeyCode.DPadLeft] = "D-Pad Left",
	[Enum.KeyCode.DPadRight] = "D-Pad Right",
	[Enum.KeyCode.DPadUp] = "D-Pad Up",
	[Enum.KeyCode.DPadDown] = "D-Pad Down",
}

-- Map of KeyCode enums to compact display names (for small indicators/badges)
InputDisplayUtil.CompactKeyCodeNames = {
	-- Keypad - show just the number/symbol
	[Enum.KeyCode.KeypadZero] = "0",
	[Enum.KeyCode.KeypadOne] = "1",
	[Enum.KeyCode.KeypadTwo] = "2",
	[Enum.KeyCode.KeypadThree] = "3",
	[Enum.KeyCode.KeypadFour] = "4",
	[Enum.KeyCode.KeypadFive] = "5",
	[Enum.KeyCode.KeypadSix] = "6",
	[Enum.KeyCode.KeypadSeven] = "7",
	[Enum.KeyCode.KeypadEight] = "8",
	[Enum.KeyCode.KeypadNine] = "9",
	[Enum.KeyCode.KeypadPeriod] = ".",
	[Enum.KeyCode.KeypadEnter] = "↵",
	[Enum.KeyCode.KeypadPlus] = "+",
	[Enum.KeyCode.KeypadMinus] = "-",
	[Enum.KeyCode.KeypadMultiply] = "*",
	[Enum.KeyCode.KeypadDivide] = "/",

	-- Special keys - compact versions
	[Enum.KeyCode.LeftShift] = "⇧",
	[Enum.KeyCode.RightShift] = "⇧",
	[Enum.KeyCode.LeftControl] = "Ctrl",
	[Enum.KeyCode.RightControl] = "Ctrl",
	[Enum.KeyCode.LeftAlt] = "Alt",
	[Enum.KeyCode.RightAlt] = "Alt",
	[Enum.KeyCode.Space] = "␣",
	[Enum.KeyCode.Return] = "Ent",
	[Enum.KeyCode.Tab] = "Tab",
	[Enum.KeyCode.Backspace] = "⌫",
	[Enum.KeyCode.Delete] = "Del",
	[Enum.KeyCode.Insert] = "Ins",
	[Enum.KeyCode.Home] = "↖",
	[Enum.KeyCode.End] = "↘",
	[Enum.KeyCode.PageUp] = "PUp",
	[Enum.KeyCode.PageDown] = "PDn",
	[Enum.KeyCode.Escape] = "Esc",
	[Enum.KeyCode.CapsLock] = "Caps",

	-- Arrow keys - symbols
	[Enum.KeyCode.Up] = "↑",
	[Enum.KeyCode.Down] = "↓",
	[Enum.KeyCode.Left] = "←",
	[Enum.KeyCode.Right] = "→",

	-- Function keys - compact
	[Enum.KeyCode.F1] = "F1",
	[Enum.KeyCode.F2] = "F2",
	[Enum.KeyCode.F3] = "F3",
	[Enum.KeyCode.F4] = "F4",
	[Enum.KeyCode.F5] = "F5",
	[Enum.KeyCode.F6] = "F6",
	[Enum.KeyCode.F7] = "F7",
	[Enum.KeyCode.F8] = "F8",
	[Enum.KeyCode.F9] = "F9",
	[Enum.KeyCode.F10] = "F10",
	[Enum.KeyCode.F11] = "F11",
	[Enum.KeyCode.F12] = "F12",

	-- Mouse buttons - compact
	[Enum.UserInputType.MouseButton1] = "M1",
	[Enum.UserInputType.MouseButton2] = "M2",
	[Enum.UserInputType.MouseButton3] = "M3",

	-- Scroll wheel - compact
	["ScrollWheelUp"] = "⇧",
	["ScrollWheelDown"] = "⇩",

	-- Controller buttons - compact
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "Y",
	[Enum.KeyCode.ButtonL1] = "L1",
	[Enum.KeyCode.ButtonL2] = "L2",
	[Enum.KeyCode.ButtonL3] = "L3",
	[Enum.KeyCode.ButtonR1] = "R1",
	[Enum.KeyCode.ButtonR2] = "R2",
	[Enum.KeyCode.ButtonR3] = "R3",
	[Enum.KeyCode.ButtonStart] = "▶",
	[Enum.KeyCode.ButtonSelect] = "◀",
	[Enum.KeyCode.DPadLeft] = "◁",
	[Enum.KeyCode.DPadRight] = "▷",
	[Enum.KeyCode.DPadUp] = "△",
	[Enum.KeyCode.DPadDown] = "▽",
}

-- Converts a KeyCode or UserInputType enum to a user-friendly display string
-- @param input: Enum.KeyCode or Enum.UserInputType
-- @return string: Display name (e.g., "Left Shift", "Space", "Left Click")
function InputDisplayUtil:GetDisplayName(input)
	local displayName = self.KeyCodeNames[input]
	if displayName then
		return displayName
	end

	-- Fallback: extract the name from the enum value
	local inputString = tostring(input)
	-- Format: "Enum.KeyCode.LeftShift" -> "LeftShift"
	local name = inputString:match("%.([^%.]+)$")
	return name or inputString
end

-- Converts a KeyCode or UserInputType enum to a compact display string (for indicators/badges)
-- Falls back to regular display name if no compact version exists
-- @param input: Enum.KeyCode or Enum.UserInputType
-- @return string: Compact display name (e.g., "⇧", "7", "M1", ".")
function InputDisplayUtil:GetCompactDisplayName(input)
	-- Try compact name first
	local compactName = self.CompactKeyCodeNames[input]
	if compactName then
		return compactName
	end

	-- Fall back to regular display name (already compact for letters, numbers, symbols)
	return self:GetDisplayName(input)
end

-- Converts a display name back to a KeyCode or UserInputType enum
-- @param displayName: string (e.g., "Left Shift", "A", "Left Click")
-- @return Enum.KeyCode or Enum.UserInputType or nil
function InputDisplayUtil:GetInputFromDisplayName(displayName)
	-- Search through the KeyCodeNames table to find matching display name
	for input, name in pairs(self.KeyCodeNames) do
		if name == displayName then
			return input
		end
	end

	-- Fallback: try to match by KeyCode name directly
	local success, keyCode = pcall(function()
		return Enum.KeyCode[displayName]
	end)
	if success and keyCode then
		return keyCode
	end

	-- Try UserInputType
	success, keyCode = pcall(function()
		return Enum.UserInputType[displayName]
	end)
	if success and keyCode then
		return keyCode
	end

	return nil
end

-- Returns a list of all available input options for keybind settings
-- @return table: Array of {Input = enum, DisplayName = string}
function InputDisplayUtil:GetAllInputOptions()
	local options = {}

	for input, displayName in pairs(self.KeyCodeNames) do
		table.insert(options, {
			Input = input,
			DisplayName = displayName,
		})
	end

	-- Sort by display name for better UI presentation
	table.sort(options, function(a, b)
		return a.DisplayName < b.DisplayName
	end)

	return options
end

return InputDisplayUtil
