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

	local mainui = self._ui;
	local grad = mainui:FindFirstChild("UIGradient");

	local camera = workspace.CurrentCamera;
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable;
		game.TweenService:Create(camera, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = camera:GetPivot() *CFrame.new(0, 15, 0),
		}):Play()
	end;

	if grad then
		grad.Offset = Vector2.new(0, -1);
		local fadeTween = game.TweenService:Create(grad, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Offset = Vector2.new(0, 1),
		})

		fadeTween:Play()
	end;

	return true
end

function module:hide()
	local mainui = self._ui;
	local grad = mainui:FindFirstChild("UIGradient");

	local camera = workspace.CurrentCamera;
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable;
		game.TweenService:Create(camera, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = camera:GetPivot() *CFrame.new(0, -15, 0),
		}):Play()
	end;

	local fadeTween;
	if grad then
		grad.Offset = Vector2.new(0, 1);
		fadeTween = game.TweenService:Create(grad, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Offset = Vector2.new(0, -1),
		})

		fadeTween:Play()
		fadeTween.Completed:Wait()
	end;

	camera.CameraType = Enum.CameraType.Fixed;
	self._ui.Visible = false
	return true
end

function module:showLeft()
	self._ui.Visible = true

	local mainui = self._ui
	local grad = mainui:FindFirstChild("UIGradient")

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		game.TweenService:Create(camera, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = camera:GetPivot() * CFrame.new(-15, 0, 0),
		}):Play()
	end

	if grad then
		grad.Rotation = 90
		grad.Offset = Vector2.new(0, -1)
		local fadeTween = game.TweenService:Create(grad, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Offset = Vector2.new(0, 1),
		})

		fadeTween:Play()
	end

	return true
end

function module:hideLeft()
	local mainui = self._ui
	local grad = mainui:FindFirstChild("UIGradient")

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		game.TweenService:Create(camera, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = camera:GetPivot() * CFrame.new(15, 0, 0),
		}):Play()
	end

	local fadeTween
	if grad then
		grad.Rotation = 90
		grad.Offset = Vector2.new(0, 1)
		fadeTween = game.TweenService:Create(grad, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Offset = Vector2.new(0, -1),
		})

		fadeTween:Play()
		fadeTween.Completed:Wait()
	end

	camera.CameraType = Enum.CameraType.Fixed
	self._ui.Visible = false
	return true
end

function module:showRight()
	self._ui.Visible = true

	local mainui = self._ui
	local grad = mainui:FindFirstChild("UIGradient")

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		game.TweenService:Create(camera, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = camera:GetPivot() * CFrame.new(15, 0, 0),
		}):Play()
	end

	if grad then
		grad.Rotation = -90
		grad.Offset = Vector2.new(0, -1)
		local fadeTween = game.TweenService:Create(grad, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Offset = Vector2.new(0, 1),
		})

		fadeTween:Play()
	end

	return true
end

function module:hideRight()
	local mainui = self._ui
	local grad = mainui:FindFirstChild("UIGradient")

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		game.TweenService:Create(camera, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = camera:GetPivot() * CFrame.new(-15, 0, 0),
		}):Play()
	end

	local fadeTween
	if grad then
		grad.Rotation = -90
		grad.Offset = Vector2.new(0, 1)
		fadeTween = game.TweenService:Create(grad, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Offset = Vector2.new(0, -1),
		})

		fadeTween:Play()
		fadeTween.Completed:Wait()
	end

	camera.CameraType = Enum.CameraType.Fixed
	self._ui.Visible = false
	return true
end

function module:_cleanup()

end

return module