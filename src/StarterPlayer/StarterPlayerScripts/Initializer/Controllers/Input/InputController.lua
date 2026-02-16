local UserInputService = game:GetService("UserInputService")

local InputController = {}

local InputManager = require(script.Parent:WaitForChild("InputManager"))

function InputController:Init(_registry, net)
	self._net = net
	self.Manager = InputManager
	self.Manager:Init()

	-- Send detected platform to server for overhead display
	local platform = self.Manager.InputMode
	if platform == "Unknown" then
		platform = "PC"
	end
	self._net:FireServer("SetPlatform", platform)

	-- Re-send when input device changes (e.g. controller plugged in)
	UserInputService.LastInputTypeChanged:Connect(function(lastInputType)
		-- Update LastInputType first so DetectInputMode reads the correct value
		self.Manager.LastInputType = lastInputType
		self.Manager:DetectInputMode()
		local newPlatform = self.Manager.InputMode
		if newPlatform ~= "Unknown" then
			self._net:FireServer("SetPlatform", newPlatform)
		end
	end)
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
