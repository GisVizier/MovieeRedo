local MovementStateManager = {}

-- Movement states
MovementStateManager.States = {
	Walking = "Walking",
	Sprinting = "Sprinting",
	Crouching = "Crouching",
	Sliding = "Sliding",
}

local FOVController = nil
local function GetFOVController()
	if FOVController then
		return FOVController
	end
	local success, controller = pcall(function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
		return require(Locations.Modules.Systems.Core.FOVController)
	end)
	if success then
		FOVController = controller
		return controller
	end
	return nil
end

MovementStateManager.CurrentState = MovementStateManager.States.Walking
MovementStateManager.PreviousState = nil
MovementStateManager.StateChangeCallbacks = {}
MovementStateManager.Character = nil -- Reference to character for visual crouch handling

-- Movement tracking (for animations and other systems)
MovementStateManager.IsMoving = false
MovementStateManager.MovementChangeCallbacks = {}

-- Grounded tracking (for animations and other systems)
MovementStateManager.IsGrounded = true
MovementStateManager.GroundedChangeCallbacks = {}

-- State priority (higher number = higher priority)
local STATE_PRIORITIES = {
	[MovementStateManager.States.Walking] = 1,
	[MovementStateManager.States.Sprinting] = 2,
	[MovementStateManager.States.Crouching] = 3,
	[MovementStateManager.States.Sliding] = 4,
}

function MovementStateManager:GetCurrentState()
	return self.CurrentState
end

function MovementStateManager:GetPreviousState()
	return self.PreviousState
end

function MovementStateManager:CanTransitionTo(newState)
	local currentPriority = STATE_PRIORITIES[self.CurrentState] or 0
	local newPriority = STATE_PRIORITIES[newState] or 0

	-- Always allow transitions to same state or higher priority states
	if newPriority >= currentPriority then
		return true
	end

	-- Special cases for lower priority transitions
	if
		self.CurrentState == self.States.Sliding
		and (newState == self.States.Walking or newState == self.States.Sprinting or newState == self.States.Crouching)
	then
		-- Sliding can exit to walking, sprinting, or crouching when slide ends
		return true
	elseif
		self.CurrentState == self.States.Crouching
		and (newState == self.States.Walking or newState == self.States.Sprinting)
	then
		-- Crouching can exit to walking or sprinting
		return true
	elseif self.CurrentState == self.States.Sprinting and newState == self.States.Walking then
		-- Sprinting can exit to walking when sprint key released
		return true
	end

	return false
end

function MovementStateManager:TransitionTo(newState, data)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local TestMode = require(ReplicatedStorage.TestMode)

	-- Early return for same state to prevent unnecessary logging
	if self.CurrentState == newState then
		if TestMode.Logging.LogSlidingSystem then
			local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
			local LogService = require(Locations.Modules.Systems.Core.LogService)

			LogService:Debug("MOVEMENT", "STATE TRANSITION SKIPPED - already in state", {
				CurrentState = self.CurrentState,
				RequestedState = newState,
			})
		end
		return true
	end

	if TestMode.Logging.LogSlidingSystem then
		local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
		local LogService = require(Locations.Modules.Systems.Core.LogService)

		LogService:Info("MOVEMENT", "STATE TRANSITION ATTEMPT", {
			FromState = self.CurrentState,
			ToState = newState,
			CanTransition = self:CanTransitionTo(newState),
			Data = data,
			Timestamp = tick(),
		})
	end

	if not self:CanTransitionTo(newState) then
		if TestMode.Logging.LogSlidingSystem then
			local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
			local LogService = require(Locations.Modules.Systems.Core.LogService)

			LogService:Info("MOVEMENT", "STATE TRANSITION FAILED", {
				FromState = self.CurrentState,
				ToState = newState,
				Reason = "Transition not allowed by priority rules",
				CurrentPriority = STATE_PRIORITIES[self.CurrentState] or 0,
				NewPriority = STATE_PRIORITIES[newState] or 0,
			})
		end
		return false
	end

	self.PreviousState = self.CurrentState
	self.CurrentState = newState

	if TestMode.Logging.LogSlidingSystem then
		local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
		local LogService = require(Locations.Modules.Systems.Core.LogService)

		LogService:Info("MOVEMENT", "STATE TRANSITION SUCCESSFUL", {
			PreviousState = self.PreviousState,
			NewState = self.CurrentState,
			Data = data,
			Timestamp = tick(),
		})
	end

	-- Automatically handle visual crouch based on state
	self:UpdateVisualCrouchForState(self.CurrentState)

	-- Handle sprint FOV effect
	local fovController = GetFOVController()
	if fovController then
		if newState == self.States.Sprinting then
			fovController:AddEffect("Sprint")
		elseif self.PreviousState == self.States.Sprinting then
			fovController:RemoveEffect("Sprint")
		end
	end

	-- Fire callbacks
	self:FireStateChangeCallbacks(self.PreviousState, self.CurrentState, data)

	return true
end

function MovementStateManager:IsInState(state)
	return self.CurrentState == state
end

function MovementStateManager:ShouldBeVisuallyCrouched(state)
	-- Determine if a state requires visual crouch
	return state == self.States.Crouching or state == self.States.Sliding
end

function MovementStateManager:IsWalking()
	return self:IsInState(self.States.Walking)
end

function MovementStateManager:IsSprinting()
	return self:IsInState(self.States.Sprinting)
end

function MovementStateManager:IsCrouching()
	return self:IsInState(self.States.Crouching)
end

function MovementStateManager:IsSliding()
	return self:IsInState(self.States.Sliding)
end

function MovementStateManager:ConnectToStateChange(callback)
	table.insert(self.StateChangeCallbacks, callback)
end

function MovementStateManager:ConnectToMovementChange(callback)
	table.insert(self.MovementChangeCallbacks, callback)
end

function MovementStateManager:ConnectToGroundedChange(callback)
	table.insert(self.GroundedChangeCallbacks, callback)
end

function MovementStateManager:FireStateChangeCallbacks(previousState, newState, data)
	for _, callback in ipairs(self.StateChangeCallbacks) do
		pcall(callback, previousState, newState, data)
	end
end

function MovementStateManager:FireMovementChangeCallbacks(previousMoving, newMoving)
	for _, callback in ipairs(self.MovementChangeCallbacks) do
		pcall(callback, previousMoving, newMoving)
	end
end

function MovementStateManager:UpdateMovementState(isMoving)
	if self.IsMoving ~= isMoving then
		local previousMoving = self.IsMoving
		self.IsMoving = isMoving
		self:FireMovementChangeCallbacks(previousMoving, isMoving)
	end
end

function MovementStateManager:GetIsMoving()
	return self.IsMoving
end

function MovementStateManager:FireGroundedChangeCallbacks(previousGrounded, newGrounded)
	for _, callback in ipairs(self.GroundedChangeCallbacks) do
		pcall(callback, previousGrounded, newGrounded)
	end
end

function MovementStateManager:UpdateGroundedState(isGrounded)
	if self.IsGrounded ~= isGrounded then
		local previousGrounded = self.IsGrounded
		self.IsGrounded = isGrounded
		self:FireGroundedChangeCallbacks(previousGrounded, isGrounded)
	end
end

function MovementStateManager:GetIsGrounded()
	return self.IsGrounded
end

function MovementStateManager:Reset()
	self.PreviousState = self.CurrentState
	self.CurrentState = self.States.Walking
	self:FireStateChangeCallbacks(self.PreviousState, self.CurrentState)
end

function MovementStateManager:SetCharacter(character)
	self.Character = character
end

function MovementStateManager:UpdateVisualCrouchForState(state)
	if not self.Character then
		return
	end

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
	local CrouchUtils = require(Locations.Modules.Systems.Character.CrouchUtils)
	local RemoteEvents = require(Locations.Modules.RemoteEvents)

	local shouldBeCrouched = self:ShouldBeVisuallyCrouched(state)
	local isVisuallyCrouched = CrouchUtils:IsVisuallycrouched(self.Character)

	if shouldBeCrouched and not isVisuallyCrouched then
		-- Apply visual crouch (skip clearance check since state system already validated the transition)
		CrouchUtils:ApplyVisualCrouch(self.Character, true)
		RemoteEvents:FireServer("CrouchStateChanged", true)
	elseif not shouldBeCrouched and isVisuallyCrouched then
		-- Remove visual crouch
		CrouchUtils:RemoveVisualCrouch(self.Character)
		RemoteEvents:FireServer("CrouchStateChanged", false)
	end
end

return MovementStateManager
