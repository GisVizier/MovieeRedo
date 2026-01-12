local InputController = {}

local InputManager = require(script.Parent:WaitForChild("InputManager"))

function InputController:Init()
	self.Manager = InputManager
	self.Manager:Init()
end

function InputController:Start()
end

function InputController:ConnectToInput(inputType, callback)
	return self.Manager:ConnectToInput(inputType, callback)
end

function InputController:GetMovementVector()
	return self.Manager:GetMovementVector()
end

function InputController:GetLookDelta()
	return self.Manager:GetLookDelta()
end

function InputController:IsJumpHeld()
	return self.Manager:IsJumpHeld()
end

function InputController:IsSprintHeld()
	return self.Manager:IsSprintHeld()
end

function InputController:IsCrouchHeld()
	return self.Manager:IsCrouchHeld()
end

function InputController:ResetInputState()
	return self.Manager:ResetInputState()
end

function InputController:GetInputMode()
	return self.Manager.InputMode
end

function InputController:GetMobileControls()
	return self.Manager.MobileControls
end

return InputController
