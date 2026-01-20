local MovementStateManager = {}

MovementStateManager.States = {
	Walking = "Walking",
	Sprinting = "Sprinting",
	Crouching = "Crouching",
	Sliding = "Sliding",
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local CrouchUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("CrouchUtils"))
local Net = require(Locations.Shared:WaitForChild("Net"):WaitForChild("Net"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))

MovementStateManager.CurrentState = MovementStateManager.States.Walking
MovementStateManager.PreviousState = nil
MovementStateManager.StateChangeCallbacks = {}
MovementStateManager.Character = nil

MovementStateManager.IsMoving = false
MovementStateManager.MovementChangeCallbacks = {}

MovementStateManager.IsGrounded = true
MovementStateManager.GroundedChangeCallbacks = {}

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

	if newPriority >= currentPriority then
		return true
	end

	if self.CurrentState == self.States.Sliding and (newState == self.States.Walking or newState == self.States.Sprinting or newState == self.States.Crouching) then
		return true
	elseif self.CurrentState == self.States.Crouching and (newState == self.States.Walking or newState == self.States.Sprinting) then
		return true
	elseif self.CurrentState == self.States.Sprinting and newState == self.States.Walking then
		return true
	end

	return false
end

function MovementStateManager:TransitionTo(newState, data)
	if self.CurrentState == newState then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("MOVEMENT", "STATE TRANSITION SKIPPED - already in state", {
				CurrentState = self.CurrentState,
				RequestedState = newState,
			})
		end
		return true
	end

	if TestMode.Logging.LogSlidingSystem then
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
		LogService:Info("MOVEMENT", "STATE TRANSITION SUCCESSFUL", {
			PreviousState = self.PreviousState,
			NewState = self.CurrentState,
			Data = data,
			Timestamp = tick(),
		})
	end

	self:UpdateVisualCrouchForState(self.CurrentState)

	-- Sprint FOV is now handled via velocity check, not state change
	-- This allows FOV to only change when actually moving while sprinting
	if self.PreviousState == self.States.Sprinting then
		FOVController:RemoveEffect("Sprint")
	end

	self:FireStateChangeCallbacks(self.PreviousState, self.CurrentState, data)

	return true
end

function MovementStateManager:IsInState(state)
	return self.CurrentState == state
end

function MovementStateManager:ShouldBeVisuallyCrouched(state)
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
	local previousState = self.CurrentState
	self.PreviousState = previousState
	self.CurrentState = self.States.Walking

	local previousMoving = self.IsMoving
	self.IsMoving = false
	if previousMoving ~= self.IsMoving then
		self:FireMovementChangeCallbacks(previousMoving, self.IsMoving)
	end

	local previousGrounded = self.IsGrounded
	self.IsGrounded = true
	if previousGrounded ~= self.IsGrounded then
		self:FireGroundedChangeCallbacks(previousGrounded, self.IsGrounded)
	end

	self:FireStateChangeCallbacks(previousState, self.CurrentState)
end

function MovementStateManager:SetCharacter(character)
	self.Character = character
end

function MovementStateManager:UpdateVisualCrouchForState(state)
	if not self.Character then
		return
	end

	local shouldBeCrouched = self:ShouldBeVisuallyCrouched(state)
	local isVisuallyCrouched = CrouchUtils:IsVisuallycrouched(self.Character)

	if shouldBeCrouched and not isVisuallyCrouched then
		CrouchUtils:ApplyVisualCrouch(self.Character, true)
		Net:FireServer("CrouchStateChanged", true)
	elseif not shouldBeCrouched and isVisuallyCrouched then
		CrouchUtils:RemoveVisualCrouch(self.Character)
		Net:FireServer("CrouchStateChanged", false)
	end
end

return MovementStateManager
