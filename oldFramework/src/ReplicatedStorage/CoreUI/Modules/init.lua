--[[
	CoreUI Modules
	
	This folder contains UI modules that control UI elements.
	Each module name must match a UI element name in the ScreenGui.
	
	To create a new UI module:
		1. Create a ModuleScript (or folder with init.lua) here
		2. Name it EXACTLY like the UI element in your ScreenGui
		3. Export a `start(export, ui)` function that returns a module instance
		4. The module instance should have `show()` and optionally `hide()` methods
]]

local module = {}

return module
