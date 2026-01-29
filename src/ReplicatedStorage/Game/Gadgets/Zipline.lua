local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local GadgetBase = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("GadgetBase"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))

local HitDetectionAPI = nil
if RunService:IsServer() then
	HitDetectionAPI = require(Locations.Services.ServerScriptService:WaitForChild("Server"):WaitForChild("Services"):WaitForChild("AntiCheat"):WaitForChild("HitDetectionAPI"))
end
local EmoteService = nil
if RunService:IsClient() then
	EmoteService = require(Locations.Game:WaitForChild("Emotes"))
	if EmoteService and EmoteService.init then
		EmoteService.init()
	end
end

local Zipline = {}
Zipline.__index = Zipline
setmetatable(Zipline, GadgetBase)

local defaultSegmentCount = 16
local defaultSegmentSize = Vector3.new(0.2, 0.2, 0.2)
local defaultUseDistance = 12
local defaultBaseSpeed = 60
local defaultMaxSpeed = 120
local defaultUphillMultiplier = 0.85
local defaultDownhillMultiplier = 1.15
local defaultAttachWindow = 0.35
local defaultAttachOffset = Vector3.new(0, -5, 0)
local defaultEndFlingAccel = 140
local defaultEndFlingUpAccel = 60
local defaultEndFlingDuration = 0.2
local defaultDetachCooldown = 0.25
local defaultJumpDetachCooldownBonus = 0.6
local defaultJumpDetachAccel = 90
local defaultJumpDetachUpAccel = 140
local fastHookupSpeedMultiplier = 1.35
local ziplineAttributes = {
	"SegmentCount",
	"SegmentSize",
	"UseDistance",
	"ZiplineSpeed",
	"MaxSpeed",
	"UphillMultiplier",
	"DownhillMultiplier",
	"AttachWindow",
	"AttachOffset",
	"EndFlingAccel",
	"EndFlingUpAccel",
	"EndFlingDuration",
	"DetachCooldown",
	"JumpDetachCooldownBonus",
	"JumpDetachAccel",
	"JumpDetachUpAccel",
	"JumpDetachMoveSpeed",
}

function Zipline.new(params)
	local self = GadgetBase.new(params)
	setmetatable(self, Zipline)
	self._segmentsFolder = nil
	self._touchConnections = {}
	self._jumpConnection = nil
	self._crouchConnection = nil
	self._reloadConnection = nil
	self._abilityConnection = nil
	self._ultimateConnection = nil
	self._nearSide = nil
	self._nearUntil = 0
	self._isAttached = false
	self._attachedUsers = {}
	self._detachCooldowns = {}
	self._movementConnection = nil
	self._segmentsAddedConnection = nil
	self._savedVectorForce = nil
	self._savedAlignEnabled = nil
	self._lastTouchTime = 0
	self._lastJumpTime = 0
	self._inputController = nil
	self._ziplineFovActive = nil
	self._pathPoints = nil
	self._pathLengths = nil
	self._pathTotalLength = nil
	self._lastRideCFrame = nil
	self._lastForward = nil
	self._pendingEndFling = false
	self._pendingEndForward = nil
	self._rideDirection = 1
	self._rideSpeed = 0
	self._savedPlatformStand = nil
	self._savedAutoRotate = nil
	self._savedHumanoidState = nil
	self._savedStateEnabled = nil
	self._animationController = nil
	self._ziplineTrack = nil
	self._ziplineTrackConnection = nil
	self._cameraController = nil
	self._bufferedMovementInput = nil
	self._bufferedCameraAngle = nil
	return self
end

function Zipline:_getSegmentCount()
	local count = self.model and self.model:GetAttribute("SegmentCount")
	if type(count) ~= "number" or count < 2 then
		return defaultSegmentCount
	end
	return math.floor(count)
end

function Zipline:_getSegmentThickness(refPart)
	local size = self.model and self.model:GetAttribute("SegmentSize")
	if typeof(size) == "Vector3" then
		return size.X, size.Y
	end
	if type(size) == "number" and size > 0 then
		return size, size
	end
	if refPart and refPart:IsA("BasePart") then
		return refPart.Size.X, refPart.Size.Y
	end
	return defaultSegmentSize.X, defaultSegmentSize.Y
end

function Zipline:_getUseDistance()
	local distance = self.model and self.model:GetAttribute("UseDistance")
	if type(distance) ~= "number" or distance <= 0 then
		return defaultUseDistance
	end
	return distance
end

function Zipline:_getBaseSpeed()
	local speed = self.model and self.model:GetAttribute("ZiplineSpeed")
	if type(speed) ~= "number" or speed <= 0 then
		return defaultBaseSpeed
	end
	return speed
end

function Zipline:_getMaxSpeed()
	local speed = self.model and self.model:GetAttribute("MaxSpeed")
	if type(speed) ~= "number" or speed <= 0 then
		return defaultMaxSpeed
	end
	return speed
end

function Zipline:_getUphillMultiplier()
	local value = self.model and self.model:GetAttribute("UphillMultiplier")
	if type(value) ~= "number" or value <= 0 then
		return defaultUphillMultiplier
	end
	return value
end

function Zipline:_getDownhillMultiplier()
	local value = self.model and self.model:GetAttribute("DownhillMultiplier")
	if type(value) ~= "number" or value <= 0 then
		return defaultDownhillMultiplier
	end
	return value
end

function Zipline:_getAttachWindow()
	local value = self.model and self.model:GetAttribute("AttachWindow")
	if type(value) ~= "number" or value <= 0 then
		return defaultAttachWindow
	end
	return value
end

function Zipline:_getAttachOffset()
	local offset = self.model and self.model:GetAttribute("AttachOffset")
	if typeof(offset) == "Vector3" then
		return offset
	end
	return defaultAttachOffset
end

function Zipline:_getEndFlingAccel()
	local value = self.model and self.model:GetAttribute("EndFlingAccel")
	if type(value) ~= "number" or value <= 0 then
		return defaultEndFlingAccel
	end
	return value
end

function Zipline:_getEndFlingUpAccel()
	local value = self.model and self.model:GetAttribute("EndFlingUpAccel")
	if type(value) ~= "number" or value < 0 then
		return defaultEndFlingUpAccel
	end
	return value
end

function Zipline:_getEndFlingDuration()
	local value = self.model and self.model:GetAttribute("EndFlingDuration")
	if type(value) ~= "number" or value <= 0 then
		return defaultEndFlingDuration
	end
	return value
end

function Zipline:_getDetachCooldown()
	local value = self.model and self.model:GetAttribute("DetachCooldown")
	if type(value) ~= "number" or value < 0 then
		return defaultDetachCooldown
	end
	return value
end

function Zipline:_getJumpDetachCooldownBonus()
	local value = self.model and self.model:GetAttribute("JumpDetachCooldownBonus")
	if type(value) ~= "number" or value < 0 then
		return defaultJumpDetachCooldownBonus
	end
	return value
end

function Zipline:_getJumpDetachAccel()
	local value = self.model and self.model:GetAttribute("JumpDetachAccel")
	if type(value) ~= "number" or value <= 0 then
		return defaultJumpDetachAccel
	end
	return value
end

function Zipline:_getJumpDetachUpAccel()
	local value = self.model and self.model:GetAttribute("JumpDetachUpAccel")
	if type(value) ~= "number" or value < 0 then
		return defaultJumpDetachUpAccel
	end
	return value
end

function Zipline:_getAttachmentOnPart(partName, attachmentName)
	if not self.model then
		return nil
	end
	local part = self.model:FindFirstChild(partName)
	if not part or not part:IsA("BasePart") then
		return nil
	end
	local attachment = part:FindFirstChild(attachmentName)
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end
	return nil
end

function Zipline:_getRefPart()
	if not self.model then
		return nil
	end
	local ref = self.model:FindFirstChild("RefPart")
	if ref and ref:IsA("BasePart") then
		return ref
	end
	ref = self.model:FindFirstChild("refPart")
	if ref and ref:IsA("BasePart") then
		return ref
	end
	return nil
end

function Zipline:_getOrCreateSegmentsFolder()
	if self._segmentsFolder and self._segmentsFolder.Parent then
		return self._segmentsFolder
	end
	local folder = self.model and self.model:FindFirstChild("Segments")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Segments"
		folder.Parent = self.model
	end
	self._segmentsFolder = folder
	return folder
end

function Zipline:_clearSegments()
	local folder = self:_getOrCreateSegmentsFolder()
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

function Zipline:_applyRefProperties(part, refPart, allowTouch)
	if not part then
		return
	end
	if refPart then
		part.Color = refPart.Color
		part.Material = refPart.Material
		part.Transparency = refPart.Transparency
		part.Reflectance = refPart.Reflectance
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = allowTouch == true
	part.CanQuery = false
end

function Zipline:_bezierPoint(p0, p1, p2, t)
	local inv = 1 - t
	return (inv * inv) * p0 + (2 * inv * t) * p1 + (t * t) * p2
end

function Zipline:_buildPathPoints()
	local startAttachment = self:_getAttachmentOnPart("Base1", "Start")
	local endAttachment = self:_getAttachmentOnPart("Base2", "End")
	if not startAttachment or not endAttachment then
		return nil
	end

	local centerAttachment = self:_getAttachmentOnPart("Center", "Center")
	local count = self:_getSegmentCount()
	local points = {}

	if centerAttachment then
		local p0 = startAttachment.WorldPosition
		local p1 = centerAttachment.WorldPosition
		local p2 = endAttachment.WorldPosition
		for i = 0, count - 1 do
			local t = i / (count - 1)
			table.insert(points, self:_bezierPoint(p0, p1, p2, t))
		end
	else
		local p0 = startAttachment.WorldPosition
		local p1 = endAttachment.WorldPosition
		for i = 0, count - 1 do
			local t = i / (count - 1)
			table.insert(points, p0:Lerp(p1, t))
		end
	end

	return points
end

function Zipline:_buildPathLengths(points)
	local lengths = {}
	local total = 0
	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		local len = (b - a).Magnitude
		lengths[i] = len
		total += len
	end
	return lengths, total
end

function Zipline:_getPositionAtDistance(points, lengths, distance)
	if distance <= 0 then
		return points[1]
	end

	local remaining = distance
	for i = 1, #lengths do
		local segmentLength = lengths[i]
		if remaining <= segmentLength then
			local a = points[i]
			local b = points[i + 1]
			local t = segmentLength > 0 and (remaining / segmentLength) or 0
			return a:Lerp(b, t)
		end
		remaining -= segmentLength
	end

	return points[#points]
end

function Zipline:_getClosestPointData(points, lengths, position)
	local bestDistance = math.huge
	local bestPoint = nil
	local bestTangent = nil
	local bestDistanceAlong = 0
	local distanceAccum = 0

	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		local ab = b - a
		local abLen = ab.Magnitude
		if abLen > 0 then
			local t = math.clamp((position - a):Dot(ab) / (abLen * abLen), 0, 1)
			local closest = a + (ab * t)
			local dist = (position - closest).Magnitude
			if dist < bestDistance then
				bestDistance = dist
				bestPoint = closest
				bestTangent = ab.Unit
				bestDistanceAlong = distanceAccum + (abLen * t)
			end
			distanceAccum += abLen
		end
	end

	return {
		distance = bestDistance,
		point = bestPoint,
		tangent = bestTangent,
		distanceAlong = bestDistanceAlong,
	}
end

function Zipline:_getAttachmentParent(name)
	if name == "Start" then
		return self.model and self.model:FindFirstChild("Base1")
	elseif name == "End" then
		return self.model and self.model:FindFirstChild("Base2")
	end
	return nil
end

function Zipline:_setNearSide(side)
	self._nearSide = side
	self._nearUntil = os.clock() + self:_getAttachWindow()
	self._lastTouchTime = os.clock()
end

function Zipline:_isNearWindowActive()
	return os.clock() <= self._nearUntil
end

function Zipline:_connectTouch(part, side)
	if not part or not part:IsA("BasePart") then
		return
	end
	local connection = part.Touched:Connect(function(hit)
		local localPlayer = Players.LocalPlayer
		local character = localPlayer and localPlayer.Character
		if not character or not hit or not hit:IsDescendantOf(character) then
			return
		end
		self:_setNearSide(side)
	end)
	table.insert(self._touchConnections, connection)
end

function Zipline:_disconnectTouches()
	for _, conn in ipairs(self._touchConnections) do
		conn:Disconnect()
	end
	self._touchConnections = {}
	if self._segmentsAddedConnection then
		self._segmentsAddedConnection:Disconnect()
		self._segmentsAddedConnection = nil
	end
end

function Zipline:_getAnimationController()
	if self._animationController then
		return self._animationController
	end
	local context = self:getContext()
	local registry = context and context.registry
	self._animationController = registry and registry:TryGet("AnimationController") or nil
	return self._animationController
end

function Zipline:_getCameraController()
	if self._cameraController then
		return self._cameraController
	end
	local context = self:getContext()
	local registry = context and context.registry
	self._cameraController = registry and registry:TryGet("Camera") or nil
	return self._cameraController
end

function Zipline:_getWorldMovementDirection()
	-- Get the current movement input and convert to world direction
	if not self._inputController then
		return nil
	end
	
	local movementInput = self._inputController:GetMovementVector()
	if not movementInput or movementInput.Magnitude < 0.1 then
		return nil
	end
	
	local cameraController = self:_getCameraController()
	if not cameraController then
		return nil
	end
	
	local cameraAngles = cameraController:GetCameraAngles()
	local cameraYAngle = math.rad(cameraAngles.X)
	
	-- Convert 2D input to 3D world direction (same logic as MovementUtils:CalculateWorldMovementDirection)
	local inputVector = Vector3.new(movementInput.X, 0, -movementInput.Y)
	if inputVector.Magnitude > 0 then
		inputVector = inputVector.Unit
	end
	
	local cameraCFrame = CFrame.Angles(0, cameraYAngle, 0)
	local worldMovement = cameraCFrame:VectorToWorldSpace(inputVector)
	
	return worldMovement
end

function Zipline:_bufferMovementInput()
	local worldDir = self:_getWorldMovementDirection()
	if worldDir then
		self._bufferedMovementInput = worldDir
	end
end

function Zipline:_clearZiplineTrackConnection()
	if self._ziplineTrackConnection then
		self._ziplineTrackConnection:Disconnect()
		self._ziplineTrackConnection = nil
	end
	self._ziplineTrack = nil
end

function Zipline:_playZiplineAnimation(animationName)
	local animController = self:_getAnimationController()
	if not animController or not animController.PlayZiplineAnimation then
		return nil
	end
	local track = animController:PlayZiplineAnimation(animationName)
	self._ziplineTrack = track
	return track
end

function Zipline:_playZiplineIdle()
	self:_clearZiplineTrackConnection()
	self:_playZiplineAnimation("ZiplineIdle")
end

function Zipline:_playZiplineHookup(speed)
	self:_clearZiplineTrackConnection()
	local baseSpeed = self:_getBaseSpeed()
	local isFast = type(speed) == "number" and speed >= (baseSpeed * fastHookupSpeedMultiplier)
	local name = isFast and "ZiplineFastHookUp" or "ZiplineHookUp"
	local track = self:_playZiplineAnimation(name)
	if track then
		self._ziplineTrackConnection = track.Stopped:Connect(function()
			self._ziplineTrackConnection = nil
			if self._isAttached then
				self:_playZiplineIdle()
			end
		end)
	else
		self:_playZiplineIdle()
	end
end

function Zipline:_stopZiplineAnimations(fadeOutOverride)
	self:_clearZiplineTrackConnection()
	local animController = self:_getAnimationController()
	if animController and animController.StopZiplineAnimation then
		animController:StopZiplineAnimation(fadeOutOverride)
	end
end

function Zipline:_disconnectInputConnections()
	if self._jumpConnection and self._jumpConnection.Disconnect then
		self._jumpConnection:Disconnect()
		self._jumpConnection = nil
	end
	if self._crouchConnection and self._crouchConnection.Disconnect then
		self._crouchConnection:Disconnect()
		self._crouchConnection = nil
	end
	if self._reloadConnection and self._reloadConnection.Disconnect then
		self._reloadConnection:Disconnect()
		self._reloadConnection = nil
	end
	if self._abilityConnection and self._abilityConnection.Disconnect then
		self._abilityConnection:Disconnect()
		self._abilityConnection = nil
	end
	if self._ultimateConnection and self._ultimateConnection.Disconnect then
		self._ultimateConnection:Disconnect()
		self._ultimateConnection = nil
	end
end

function Zipline:_getLocalRoot()
	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("Root") or character.PrimaryPart
end

function Zipline:_getLocalCharacter()
	local localPlayer = Players.LocalPlayer
	return localPlayer and localPlayer.Character or nil
end

function Zipline:_applyRideCFrame(targetCFrame)
	local character = self:_getLocalCharacter()
	if character and character.PrimaryPart then
		character:PivotTo(targetCFrame)
		self._lastRideCFrame = targetCFrame
		return
	end

	local root = self:_getLocalRoot()
	if root and root:IsA("BasePart") then
		root.CFrame = targetCFrame
		self._lastRideCFrame = targetCFrame
	end
end

function Zipline:_getAttachPoints()
	local startAttachment = self:_getAttachmentOnPart("Base1", "Start")
	local endAttachment = self:_getAttachmentOnPart("Base2", "End")
	if not startAttachment or not endAttachment then
		return nil
	end
	return startAttachment.WorldPosition, endAttachment.WorldPosition, startAttachment, endAttachment
end

function Zipline:_computeSpeed(directionSign, startPos, endPos)
	local baseSpeed = self:_getBaseSpeed()
	local speed = baseSpeed * 1.5
	local delta = directionSign == 1 and (endPos.Y - startPos.Y) or (startPos.Y - endPos.Y)
	if delta < 0 then
		speed = speed * self:_getDownhillMultiplier()
	elseif delta > 0 then
		speed = speed * self:_getUphillMultiplier()
	end
	local maxSpeed = self:_getMaxSpeed()
	if speed > maxSpeed then
		speed = maxSpeed
	end
	return speed
end

function Zipline:_buildSegments(points)
	if not self.model then
		return
	end
	if #points < 2 then
		return
	end

	self:_clearSegments()
	local folder = self:_getOrCreateSegmentsFolder()
	local refPart = self:_getRefPart()
	local thicknessX, thicknessY = self:_getSegmentThickness(refPart)

	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		local delta = b - a
		local length = delta.Magnitude
		if length > 0 then
			local mid = a + (delta * 0.5)
			local part = Instance.new("Part")
			part.Name = "Segment_" .. tostring(i)
			part.Size = Vector3.new(thicknessX, thicknessY, length)
			part.CFrame = CFrame.lookAt(mid, b)
			self:_applyRefProperties(part, refPart, true)
			part.Parent = folder
		end
	end
end

function Zipline:onServerCreated()
	if not self.model or not self.model.Parent then
		return
	end

	local startAttachment = self:_getAttachmentOnPart("Base1", "Start")
	local endAttachment = self:_getAttachmentOnPart("Base2", "End")
	if not startAttachment or not endAttachment then
		return
	end
	
	local points = self:_buildPathPoints()
	if not points then
		return
	end
	self:_buildSegments(points)
end

function Zipline:onUseRequest(player, payload)
	if not player then
		return false
	end

	local action = payload and payload.action
	if action == "Detach" then
		self._attachedUsers[player.UserId] = nil
		local now = os.clock()
		local cooldown = self:_getDetachCooldown()
		if payload and payload.reason == "Jump" then
			cooldown += self:_getJumpDetachCooldownBonus()
		end
		self._detachCooldowns[player.UserId] = now + cooldown
		return {
			approved = true,
			data = {
				action = "Detach",
				reason = payload and payload.reason or "Force",
			},
		}
	end

	if action ~= "Attach" then
		return false
	end

	if self._attachedUsers[player.UserId] then
		return false
	end
	local cooldownUntil = self._detachCooldowns[player.UserId]
	if type(cooldownUntil) == "number" and os.clock() < cooldownUntil then
		return false
	end

	local points = self:_buildPathPoints()
	if not points or #points < 2 then
		return false
	end

	local character = player.Character
	if not character or not character.Parent then
		return false
	end

	local rootPosition = nil
	local root = character:FindFirstChild("Root") or character.PrimaryPart
	if root and root:IsA("BasePart") then
		rootPosition = root.Position
	end

	if HitDetectionAPI then
		local serverNow = workspace:GetServerTimeNow()
		local rollback = HitDetectionAPI:GetRollbackTime(player)
		local historicalPosition = HitDetectionAPI:GetPositionAtTime(player, serverNow - rollback)
		if typeof(historicalPosition) == "Vector3" then
			rootPosition = historicalPosition
		end
	end

	if not rootPosition then
		return false
	end

	local lengths, totalLength = self:_buildPathLengths(points)
	local closest = self:_getClosestPointData(points, lengths, rootPosition)
	local useDistance = self:_getUseDistance()
	if not closest.point or closest.distance > useDistance then
		return false
	end

	local directionSign = 1
	local lookVector = payload and payload.lookVector
	local tangent = closest.tangent
	if typeof(lookVector) == "Vector3" and tangent and tangent.Magnitude > 0 then
		directionSign = (lookVector:Dot(tangent) >= 0) and 1 or -1
	end

	local startPos = points[1]
	local endPos = points[#points]
	if directionSign < 0 then
		startPos, endPos = endPos, startPos
	end
	local speed = self:_computeSpeed(directionSign, startPos, endPos)
	self._attachedUsers[player.UserId] = {
		direction = directionSign,
	}

	return {
		approved = true,
		data = {
			action = "Attach",
			direction = directionSign,
			speed = speed,
			startDistance = closest.distanceAlong,
			totalLength = totalLength,
		},
	}
end

function Zipline:ForceDetach(player, reason)
	if not player then
		return
	end
	if not self._attachedUsers[player.UserId] then
		return
	end
	self._attachedUsers[player.UserId] = nil
	local context = self:getContext()
	local net = context and context.net
	if net then
		net:FireClient("GadgetUseResponse", player, self.id, true, {
			action = "Detach",
			reason = reason,
		})
	end
end

function Zipline:_beginRide(directionSign, startDistance, speed)
	local root = self:_getLocalRoot()
	if not root or not root:IsA("BasePart") then
		return
	end

	local points = self:_buildPathPoints()
	if not points or #points < 2 then
		return
	end
	self._pathPoints = points
	self._pathLengths, self._pathTotalLength = self:_buildPathLengths(points)
	if not self._pathTotalLength or self._pathTotalLength <= 0 then
		return
	end

	if self._movementConnection then
		self._movementConnection:Disconnect()
		self._movementConnection = nil
	end

	local vectorForce = root:FindFirstChild("VectorForce")
	if vectorForce and vectorForce:IsA("VectorForce") then
		self._savedVectorForce = vectorForce.Force
		vectorForce.Force = Vector3.zero
	end

	local movementAlign = root:FindFirstChild("AlignOrientation")
	if movementAlign and movementAlign:IsA("AlignOrientation") then
		self._savedAlignEnabled = movementAlign.Enabled
		movementAlign.Enabled = false
	end
	local character = self:_getLocalCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self._savedPlatformStand = humanoid.PlatformStand
		self._savedAutoRotate = humanoid.AutoRotate
		self._savedHumanoidState = humanoid:GetState()
		self._savedStateEnabled = {
			[Enum.HumanoidStateType.Freefall] = humanoid:GetStateEnabled(Enum.HumanoidStateType.Freefall),
			[Enum.HumanoidStateType.FallingDown] = humanoid:GetStateEnabled(Enum.HumanoidStateType.FallingDown),
			[Enum.HumanoidStateType.Jumping] = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
			[Enum.HumanoidStateType.Running] = humanoid:GetStateEnabled(Enum.HumanoidStateType.Running),
		}
		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	local context = self:getContext()
	local registry = context and context.registry
	self._inputController = registry and registry:TryGet("Input")

	-- Don't disable movement controller - just let VectorForce handle it
	-- This keeps input active so movement is buffered when jumping off

	FOVController:AddEffect("Zipline", 6)
	self._ziplineFovActive = true

	self._isAttached = true
	self._bufferedMovementInput = nil -- Reset buffered input at start

	local distance = math.clamp(startDistance or 0, 0, self._pathTotalLength)
	local direction = directionSign == 1 and 1 or -1
	local speedPerSecond = speed or self:_getBaseSpeed()
	local attachOffset = self:_getAttachOffset()
	self._rideDirection = direction
	self._rideSpeed = speedPerSecond

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero


	self._movementConnection = RunService.Heartbeat:Connect(function(dt)
		if not self._isAttached then
			return
		end
		if not root or not root.Parent then
			self:RequestDetach("MissingRoot")
			return
		end
		if EmoteService and EmoteService.isPlaying and EmoteService.isPlaying() then
			self:RequestDetach("Emote")
			return
		end

		distance += (speedPerSecond * dt) * direction
		if distance <= 0 then
			distance = 0
		elseif distance >= self._pathTotalLength then
			distance = self._pathTotalLength
		end

		local position = self:_getPositionAtDistance(self._pathPoints, self._pathLengths, distance)
		if position then
			local nextDistance = math.clamp(distance + (direction * 2), 0, self._pathTotalLength)
			local nextPos = self:_getPositionAtDistance(self._pathPoints, self._pathLengths, nextDistance)
			local forward = nil
			if nextPos then
				local delta = nextPos - position
				if delta.Magnitude > 1e-4 then
					forward = delta.Unit
				end
			end
			if not forward then
				local prevDistance = math.clamp(distance - (direction * 2), 0, self._pathTotalLength)
				local prevPos = self:_getPositionAtDistance(self._pathPoints, self._pathLengths, prevDistance)
				if prevPos then
					local delta = position - prevPos
					if delta.Magnitude > 1e-4 then
						forward = delta.Unit
					end
				end
			end
			if not forward then
				forward = root.CFrame.LookVector
			end
			self._lastForward = forward
			local targetCFrame = CFrame.lookAt(position + attachOffset, position + attachOffset + forward)
			self:_applyRideCFrame(targetCFrame)
		end

		-- Buffer movement input continuously so we have latest input when jumping off
		self:_bufferMovementInput()

		if distance == 0 or distance == self._pathTotalLength then
			self._pendingEndFling = true
			self._pendingEndForward = self._lastForward
			self:RequestDetach("ReachedEnd")
		end
	end)
end

function Zipline:_applyEndFling(root, forward)
	if not root or not forward or forward.Magnitude == 0 then
		return
	end
	
	
	root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 1  * self:_getEndFlingUpAccel(), root.AssemblyLinearVelocity.Z)
end

function Zipline:_applyJumpDetachFling(root, forward)
	if not root or not forward then
		return
	end
	
	local upVelocity = self.model:GetAttribute("JumpDetachUpAccel") or 40
	local bufferedMoveSpeed = self.model:GetAttribute("JumpDetachMoveSpeed") or 50
	
	-- Start with upward velocity
	local newVelocity = Vector3.new(0, upVelocity, 0)
	
	-- Apply buffered movement input direction for horizontal velocity
	if self._bufferedMovementInput and self._bufferedMovementInput.Magnitude > 0.1 then
		local moveDir = Vector3.new(self._bufferedMovementInput.X, 0, self._bufferedMovementInput.Z)
		if moveDir.Magnitude > 0.1 then
			moveDir = moveDir.Unit
			newVelocity = newVelocity + (moveDir * bufferedMoveSpeed)
		end
	else
		-- No movement input buffered, use forward direction from zipline
		local horizontalForward = Vector3.new(forward.X, 0, forward.Z)
		if horizontalForward.Magnitude > 0.1 then
			horizontalForward = horizontalForward.Unit
			local forwardSpeed = self.model:GetAttribute("JumpDetachAccel") or 30
			newVelocity = newVelocity + (horizontalForward * forwardSpeed)
		end
	end
	
	root.AssemblyLinearVelocity = newVelocity
end

function Zipline:_endRide()
	self._isAttached = false
	if self._movementConnection then
		self._movementConnection:Disconnect()
		self._movementConnection = nil
	end
	local root = self:_getLocalRoot()
	if root and root:IsA("BasePart") then
		if self._lastRideCFrame then
			self:_applyRideCFrame(self._lastRideCFrame)
		elseif self._pathPoints and self._pathTotalLength then
			local attachOffset = self:_getAttachOffset()
			local endDistance = self._pathTotalLength
			local endPos = self:_getPositionAtDistance(self._pathPoints, self._pathLengths, endDistance)
			if endPos then
				local targetCFrame = CFrame.new(endPos + attachOffset)
				self:_applyRideCFrame(targetCFrame)
			end
		end
		local vectorForce = root:FindFirstChild("VectorForce")
		if vectorForce and vectorForce:IsA("VectorForce") and self._savedVectorForce then
			vectorForce.Force = self._savedVectorForce
		end
		local movementAlign = root:FindFirstChild("AlignOrientation")
		if movementAlign and movementAlign:IsA("AlignOrientation") and self._savedAlignEnabled ~= nil then
			movementAlign.Enabled = self._savedAlignEnabled
		end
		if self._pendingEndFling then
			self:_applyEndFling(root, self._pendingEndForward or self._lastForward)
		elseif self._pendingJumpFling then
			self:_applyJumpDetachFling(root, self._pendingJumpForward or self._lastForward)
		end
	end
	local character = self:_getLocalCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if self._savedPlatformStand ~= nil then
			humanoid.PlatformStand = self._savedPlatformStand
		end
		if self._savedAutoRotate ~= nil then
			humanoid.AutoRotate = self._savedAutoRotate
		end
		if self._savedStateEnabled then
			for stateType, enabled in pairs(self._savedStateEnabled) do
				humanoid:SetStateEnabled(stateType, enabled)
			end
		end
		if self._savedHumanoidState then
			humanoid:ChangeState(self._savedHumanoidState)
		end
	end
	self._savedVectorForce = nil
	self._savedAlignEnabled = nil
	self._pendingEndFling = false
	self._pendingEndForward = nil
	self._pendingJumpFling = false
	self._pendingJumpForward = nil
	self._savedPlatformStand = nil
	self._savedAutoRotate = nil
	self._savedHumanoidState = nil
	self._savedStateEnabled = nil
	self._bufferedMovementInput = nil
	if self._ziplineFovActive then
		FOVController:RemoveEffect("Zipline")
		self._ziplineFovActive = nil
	end
end

function Zipline:RequestDetach(reason)
	if not self._isAttached then
		return
	end
	if reason == "Jump" then
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			localPlayer:SetAttribute("ZiplineJumpDetachTime", os.clock())
		end
	end
	local context = self:getContext()
	if context and context.net then
		context.net:FireServer("GadgetUseRequest", self.id, { action = "Detach", reason = reason })
	end
end

function Zipline:RequestForceDetach(reason)
	self:RequestDetach(reason or "Forced")
end

function Zipline:onUseResponse(approved, responseData)
	if approved ~= true or type(responseData) ~= "table" then
		return
	end

	if responseData.action == "Attach" then
		local directionSign = responseData.direction or 1
		local speed = responseData.speed or self:_getBaseSpeed()
		local startDistance = responseData.startDistance or 0
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			localPlayer:SetAttribute("ZiplineActive", true)
			local baseSpeed = self:_getBaseSpeed()
			local isFast = type(speed) == "number" and speed >= (baseSpeed * fastHookupSpeedMultiplier)
			localPlayer:SetAttribute("ZiplineHookupFast", isFast)
		end
		self:_playZiplineHookup(speed)
		self:_beginRide(directionSign, startDistance, speed)
	elseif responseData.action == "Detach" then
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			localPlayer:SetAttribute("ZiplineActive", false)
			localPlayer:SetAttribute("ZiplineHookupFast", false)
		end
		if responseData.reason == "Jump" then
			self._pendingJumpFling = true
			self._pendingJumpForward = self._lastForward
			if localPlayer then
				localPlayer:SetAttribute("ZiplineJumpDetachTime", os.clock())
			end
			local track = self:_playZiplineAnimation("ZiplineJump")
			if track then
				self._ziplineTrackConnection = track.Stopped:Connect(function()
					self._ziplineTrackConnection = nil
					self:_stopZiplineAnimations()
				end)
			else
				self:_stopZiplineAnimations()
			end
		else
			if responseData.reason == "ReachedEnd" then
				self:_stopZiplineAnimations(0)
			else
				self:_stopZiplineAnimations()
			end
		end
		self:_endRide()
	end
end

function Zipline:onClientCreated()
	local points = self:_buildPathPoints()
	if points then
		self._pathPoints = points
		self._pathLengths, self._pathTotalLength = self:_buildPathLengths(points)
	end

	local context = self:getContext()
	local registry = context and context.registry
	local inputController = registry and registry:TryGet("Input")

	self:_disconnectInputConnections()

	if inputController and inputController.ConnectToInput then
		self._jumpConnection = inputController:ConnectToInput("Jump", function(isJumping)
			if not isJumping then
				return
			end
			self._lastJumpTime = os.clock()
			if self._isAttached then
				self:RequestDetach("Jump")
				return
			end
			if not self:_isNearWindowActive() then
				return
			end
			if not self._pathPoints or not self._pathLengths then
				return
			end

			local root = self:_getLocalRoot()
			if not root or not root:IsA("BasePart") then
				return
			end
			local closest = self:_getClosestPointData(self._pathPoints, self._pathLengths, root.Position)
			if not closest.point or closest.distance > self:_getUseDistance() then
				return
			end

			local lookVector = root and root.CFrame.LookVector or Vector3.new(0, 0, 0)
			if context and context.net then
				context.net:FireServer("GadgetUseRequest", self.id, {
					action = "Attach",
					lookVector = lookVector,
				})
			end
		end)
		self._crouchConnection = inputController:ConnectToInput("Crouch", function(isCrouching)
			if self._isAttached and isCrouching then
				self:RequestDetach("Crouch")
			end
		end)
		self._reloadConnection = inputController:ConnectToInput("Reload", function(isReloading)
			if self._isAttached and isReloading then
				self:RequestDetach("Reload")
			end
		end)
		self._abilityConnection = inputController:ConnectToInput("Ability", function(inputState)
			if not self._isAttached then
				return
			end
			if inputState == Enum.UserInputState.Begin or inputState == true then
				self:RequestDetach("Ability")
			end
		end)
		self._ultimateConnection = inputController:ConnectToInput("Ultimate", function(inputState)
			if not self._isAttached then
				return
			end
			if inputState == Enum.UserInputState.Begin or inputState == true then
				self:RequestDetach("Ability")
			end
		end)
	end

	self:_disconnectTouches()
	local segmentsFolder = self.model and self.model:FindFirstChild("Segments")
	if segmentsFolder and segmentsFolder:IsA("Folder") then
		for _, child in ipairs(segmentsFolder:GetChildren()) do
			self:_connectTouch(child, "Segments")
		end
		self._segmentsAddedConnection = segmentsFolder.ChildAdded:Connect(function(child)
			self:_connectTouch(child, "Segments")
		end)
	end
end

function Zipline:destroy()
	self:_disconnectTouches()
	self:_disconnectInputConnections()
	self:_stopZiplineAnimations()
	self:_endRide()
	GadgetBase.destroy(self)
end

return Zipline
