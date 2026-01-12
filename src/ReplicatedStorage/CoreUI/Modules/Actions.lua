--[[
================================================================================
                            COREUI MODULE TEMPLATE
================================================================================

SETUP:
1. Create a ModuleScript in CoreUI/Modules/
2. Name it EXACTLY like the UI element in your ScreenGui
3. Copy this template and implement your logic

LIFECYCLE:
    start(export, ui)  → Called once when CoreUI initializes
    show()             → Called when module is shown via CoreUI:show(name)
    hide()             → Called when module is hidden, return true to confirm cleanup
    _cleanup()         → Called after hide() returns true, connections auto-cleaned

EXPORT OBJECT (passed to start):
    export.tween              → TweenLibrary instance (shared)
    export.connections        → ConnectionManager for THIS module (auto-cleaned on hide)
    export:emit(event, ...)   → Fire event to other modules
    export:on(event, cb)      → Listen for events from other modules
    export:getModule(name)    → Get another module's instance
    export:isOpen(name?)      → Check if module (or self) is open
    export:show(name?)        → Show module (or self)
    export:hide(name?)        → Hide module (or self)

TWEEN LIBRARY METHODS:
    tween:tween(instance, properties, tweenInfo?, groupName?)
    tween:tweenSequence(sequence, groupName?)
    tween:fadeIn(instance, duration?, groupName?)
    tween:fadeOut(instance, duration?, groupName?)
    tween:fadeGroup(canvasGroup, targetTransparency, duration?, groupName?)
    tween:slideIn(instance, direction, duration?, groupName?)   -- "top"|"bottom"|"left"|"right"
    tween:slideOut(instance, direction, duration?, groupName?)
    tween:scaleIn(instance, duration?, groupName?)
    tween:scaleOut(instance, duration?, groupName?)
    tween:bounce(instance, intensity?, duration?, groupName?)
    tween:flash(instance, duration?, groupName?)
    tween:scrollTo(scrollingFrame, position, duration?, groupName?)
    tween:scrollToChild(scrollingFrame, child, duration?, groupName?)

CONNECTION MANAGER METHODS:
    connections:add(connection, groupName?)
    connections:track(instance, eventName, callback, groupName?)
    connections:cleanupGroup(groupName)
    connections:cleanupAll()

EVENT EXAMPLES:
    -- In Actions module: open inventory
    export:emit("OpenInventory", {tab = "weapons"})
    
    -- In Inventory module: listen for open request
    export:on("OpenInventory", function(data)
        self:openTab(data.tab)
        export:show()
    end)

================================================================================
]]

local module = {}
module.__index = module

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._tween = export.tween
	self._connections = export.connections

	self:_init()

	return self
end

function module:_init()

end

function module:show()
	self._ui.Visible = true

	return true
end

function module:hide()
	local tween = self._tween:fadeOut(self._ui, 0.3, "hideAnim")
	tween.Completed:Wait()
	
	self._ui.Visible = false
	return true
end

function module:_cleanup()

end

return module