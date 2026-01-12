local RagdollSystem = {}

RagdollSystem._states = {}

local function createAttachments(part0, part1, motor)
	local att0 = Instance.new("Attachment")
	att0.Name = "RagdollAttachment0_" .. motor.Name
	att0.CFrame = motor.C0
	att0.Parent = part0

	local att1 = Instance.new("Attachment")
	att1.Name = "RagdollAttachment1_" .. motor.Name
	att1.CFrame = motor.C1
	att1.Parent = part1

	return att0, att1
end

function RagdollSystem:RagdollRig(rig, options)
	options = options or {}

	if not rig or self._states[rig] then
		return false
	end

	local motorStates = {}
	local constraints = {}

	for _, motor in ipairs(rig:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			motorStates[motor] = {
				Enabled = motor.Enabled,
				C0 = motor.C0,
				C1 = motor.C1,
			}

			local att0, att1 = createAttachments(motor.Part0, motor.Part1, motor)
			local constraint = Instance.new("BallSocketConstraint")
			constraint.Name = "Ragdoll_" .. motor.Name
			constraint.Attachment0 = att0
			constraint.Attachment1 = att1
			constraint.Parent = motor.Part0

			constraints[motor] = constraint
			motor.Enabled = false
		end
	end

	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
			-- Keep the visual rig out of spatial queries even while ragdolled.
			-- (We still want physics collisions for ragdoll pieces, but not ray/query hits.)
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = false
			part.Anchored = false
		end
	end

	local hrp = rig:FindFirstChild("HumanoidRootPart")
	if hrp and options.Velocity then
		hrp.AssemblyLinearVelocity = options.Velocity
	end

	rig:SetAttribute("IsRagdolled", true)
	self._states[rig] = {
		MotorStates = motorStates,
		Constraints = constraints,
	}

	return true
end

function RagdollSystem:UnragdollRig(rig)
	local state = self._states[rig]
	if not state or not rig then
		return false
	end

	for motor, constraint in pairs(state.Constraints) do
		if constraint and constraint.Parent then
			constraint:Destroy()
		end

		local data = state.MotorStates[motor]
		if data then
			motor.C0 = data.C0
			motor.C1 = data.C1
			motor.Enabled = data.Enabled
		end
	end

	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.Anchored = true
		end
	end

	rig:SetAttribute("IsRagdolled", false)
	self._states[rig] = nil

	return true
end

function RagdollSystem:IsRagdolled(rig)
	return self._states[rig] ~= nil
end

return RagdollSystem
