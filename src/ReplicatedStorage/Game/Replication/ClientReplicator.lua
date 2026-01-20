local ClientReplicator = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CompressionUtils = require(Locations.Shared.Util:WaitForChild("CompressionUtils"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local RigRotationUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("RigRotationUtils"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local ReplicationConfig = require(Locations.Global:WaitForChild("Replication"))
local ArmIK = require(Locations.Shared.Util:WaitForChild("ArmIK"))

ClientReplicator.Character = nil
ClientReplicator.PrimaryPart = nil
ClientReplicator.Rig = nil
ClientReplicator.RigOffset = CFrame.new()
ClientReplicator.HumanoidOffset = CFrame.new()
ClientReplicator.HeadOffset = CFrame.new()
ClientReplicator.RigPartOffsets = nil
ClientReplicator.IsActive = false
ClientReplicator.LastUpdateTime = 0
ClientReplicator.LastSentState = nil
ClientReplicator.SequenceNumber = 0
ClientReplicator.UpdateConnection = nil
ClientReplicator._net = nil
ClientReplicator.ArmIK = nil

function ClientReplicator:Init(net)
	self._net = net
end

function ClientReplicator:Start(character)
	if self.IsActive then
		self:Stop()
	end

	self.Character = character
	self.PrimaryPart = character and character.PrimaryPart or nil
	self.Rig = CharacterLocations:GetRig(character)
	self.IsActive = true
	self.LastUpdateTime = 0
	self.LastSentState = nil
	self.SequenceNumber = 0

	self:CalculateOffsets()
	self:_cacheRigOffsets()

	-- Initialize arm IK for local player's rig (third-person view)
	if self.Rig then
		self.ArmIK = ArmIK.new(self.Rig)
	end

	local updateInterval = 1 / ReplicationConfig.UpdateRates.ClientToServer
	self.UpdateConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		if currentTime - self.LastUpdateTime >= updateInterval then
			self:SendStateUpdate()
			self.LastUpdateTime = currentTime
		end

		self:SyncParts()
	end)
end

function ClientReplicator:Stop()
	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
		self.UpdateConnection = nil
	end

	if self.ArmIK then
		self.ArmIK:Destroy()
		self.ArmIK = nil
	end

	self.IsActive = false
	self.Character = nil
	self.PrimaryPart = nil
	self.Rig = nil
	self.RigOffset = CFrame.new()
	self.HumanoidOffset = CFrame.new()
	self.HeadOffset = CFrame.new()
	self.RigPartOffsets = nil
	self.SequenceNumber = 0
end

function ClientReplicator:CalculateOffsets()
	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not characterTemplate then
		return
	end

	local templateRoot = characterTemplate:FindFirstChild("Root")
	if not templateRoot then
		return
	end

	local templateRig = characterTemplate:FindFirstChild("Rig")
	local templateRigHRP = templateRig and templateRig:FindFirstChild("HumanoidRootPart")
	if templateRigHRP then
		self.RigOffset = templateRoot.CFrame:Inverse() * templateRigHRP.CFrame
	end

	local templateHumanoidHRP = characterTemplate:FindFirstChild("HumanoidRootPart")
	if templateHumanoidHRP then
		self.HumanoidOffset = templateRoot.CFrame:Inverse() * templateHumanoidHRP.CFrame
	end

	local templateHead = characterTemplate:FindFirstChild("Head")
	if templateHead then
		self.HeadOffset = templateRoot.CFrame:Inverse() * templateHead.CFrame
	end
end

function ClientReplicator:_cacheRigOffsets()
	self.RigPartOffsets = nil
	if not self.Rig then
		return
	end

	local rigRoot = self.Rig:FindFirstChild("HumanoidRootPart") or self.Rig.PrimaryPart
	if not rigRoot then
		return
	end

	local offsets = {}
	for _, part in ipairs(self.Rig:GetDescendants()) do
		if part:IsA("BasePart") then
			offsets[part] = rigRoot.CFrame:ToObjectSpace(part.CFrame)
		end
	end

	self.RigPartOffsets = offsets
end

function ClientReplicator:CollectHumanoidParts(parts, cframes, rootCFrame)
	local humanoidRootPart = self.Character and self.Character:FindFirstChild("HumanoidRootPart")
	local humanoidHead = self.Character and CharacterLocations:GetHumanoidHead(self.Character)

	if humanoidRootPart then
		humanoidRootPart.Massless = true
		humanoidRootPart.Anchored = true
		table.insert(parts, humanoidRootPart)
		table.insert(cframes, rootCFrame * self.HumanoidOffset)
	end

	if humanoidHead then
		humanoidHead.Massless = true
		humanoidHead.Anchored = true
		table.insert(parts, humanoidHead)
		table.insert(cframes, rootCFrame * (self.HeadOffset or self.HumanoidOffset))
	end
end

function ClientReplicator:SyncParts()
	if not self.Character or not self.PrimaryPart or not self.PrimaryPart.Parent then
		return
	end

	local parts, cframes = {}, {}
	local rootCFrame = self.PrimaryPart.CFrame

	local isRagdolled = self.Character:GetAttribute("RagdollActive")
	if self.Rig and not isRagdolled then
		local rigTargetCFrame = rootCFrame * self.RigOffset
		local offsets = self.RigPartOffsets

		if offsets then
			for part, offset in pairs(offsets) do
				if part:IsA("BasePart") then
					table.insert(parts, part)
					table.insert(cframes, rigTargetCFrame * offset)
				end
			end
		else
			for _, part in pairs(self.Rig:GetDescendants()) do
				if part:IsA("BasePart") then
					table.insert(parts, part)
					table.insert(cframes, rigTargetCFrame)
				end
			end
		end
	end

	self:CollectHumanoidParts(parts, cframes, rootCFrame)

	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end

	-- Apply arm IK after positioning (arms point toward aim direction)
	if self.ArmIK and self.PrimaryPart then
		local camera = workspace.CurrentCamera
		if camera then
			local aimDistance = 15
			local aimPos = camera.CFrame.Position + camera.CFrame.LookVector * aimDistance
			self.ArmIK:PointAt(aimPos, 0.6)
		end
	end
end

function ClientReplicator:SendStateUpdate()
	if not self.IsActive or not self.Character or not self.PrimaryPart then
		return
	end

	local position = self.PrimaryPart.Position
	local rotation = self.PrimaryPart.CFrame
	local velocity = self.PrimaryPart.AssemblyLinearVelocity
	local timestamp = tick()
	local isGrounded = MovementStateManager:GetIsGrounded()

	local animationController = ServiceRegistry:GetController("AnimationController")
	local animationId = animationController and animationController:GetCurrentAnimationId() or 1

	local rigTilt = RigRotationUtils:GetCurrentTilt(self.Character) or 0

	if ReplicationConfig.Compression.UseDeltaCompression and self.LastSentState then
		local shouldSendPosition = CompressionUtils:ShouldSendPositionUpdate(self.LastSentState.Position, position)
		local shouldSendRotation = CompressionUtils:ShouldSendRotationUpdate(self.LastSentState.Rotation, rotation)
		local shouldSendVelocity = CompressionUtils:ShouldSendVelocityUpdate(self.LastSentState.Velocity, velocity)
		local shouldSendGrounded = (self.LastSentState.IsGrounded ~= isGrounded)
		local shouldSendAnimation = (self.LastSentState.AnimationId ~= animationId)
		local shouldSendRigTilt = math.abs((self.LastSentState.RigTilt or 0) - rigTilt) > 1

		if
			not shouldSendPosition
			and not shouldSendRotation
			and not shouldSendVelocity
			and not shouldSendGrounded
			and not shouldSendAnimation
			and not shouldSendRigTilt
		then
			return
		end
	end

	self.SequenceNumber = (self.SequenceNumber + 1) % 65536

	local compressedState = CompressionUtils:CompressState(
		position,
		rotation,
		velocity,
		timestamp,
		isGrounded,
		animationId,
		rigTilt,
		self.SequenceNumber
	)

	if compressedState then
		self._net:FireServer("CharacterStateUpdate", compressedState)
	end

	self.LastSentState = {
		Position = position,
		Rotation = rotation,
		Velocity = velocity,
		Timestamp = timestamp,
		IsGrounded = isGrounded,
		AnimationId = animationId,
		RigTilt = rigTilt,
	}
end

return ClientReplicator
