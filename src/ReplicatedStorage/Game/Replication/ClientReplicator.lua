local ClientReplicator = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CompressionUtils = require(Locations.Shared.Util:WaitForChild("CompressionUtils"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local RigRotationUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("RigRotationUtils"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local ReplicationConfig = require(Locations.Global:WaitForChild("Replication"))
local ThirdPersonWeaponManager = require(Locations.Game:WaitForChild("Weapons"):WaitForChild("ThirdPersonWeaponManager"))
local PlayerDataTable = require(ReplicatedStorage:WaitForChild("PlayerDataTable"))
local function vmLog(...) end

local function isSingleTrackViewmodelAction(actionName: string): boolean
	return actionName == "PlayWeaponTrack" or actionName == "PlayAnimation"
end

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
ClientReplicator.LastForcedUpdateTime = 0  -- For heartbeat updates
ClientReplicator.SequenceNumber = 0
ClientReplicator.UpdateConnection = nil
ClientReplicator._net = nil
ClientReplicator.WeaponManager = nil
ClientReplicator.CurrentLoadout = nil
ClientReplicator.CurrentEquippedSlot = nil
ClientReplicator._loadoutConn = nil
ClientReplicator._slotConn = nil
ClientReplicator._emoteConn = nil
ClientReplicator._isEmoting = false
ClientReplicator._weaponHiddenByEmote = false
ClientReplicator._weaponHiddenByLobby = false
ClientReplicator._lobbyConn = nil
ClientReplicator._lastAnimChangeTime = 0  -- Tracks when animation last changed for retransmit window
ClientReplicator._viewmodelActionSequence = 0
ClientReplicator._lastViewmodelActionTimes = {}
ClientReplicator._pendingViewmodelActions = {}
ClientReplicator._activeViewmodelActionTracks = {}

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
	self._viewmodelActionSequence = 0
	self._lastViewmodelActionTimes = {}
	self._pendingViewmodelActions = {}
	self._activeViewmodelActionTracks = {}

	self:CalculateOffsets()
	self:_cacheRigOffsets()

	-- Initialize third-person weapon manager
	if self.Rig then
		self.WeaponManager = ThirdPersonWeaponManager.new(self.Rig)
	end

	-- Listen for loadout and equipped slot changes
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		-- Parse initial loadout if available
		self:_parseLoadout(localPlayer:GetAttribute("SelectedLoadout"))
		self._isEmoting = localPlayer:GetAttribute("IsEmoting") == true
		self:_equipSlotWeapon(localPlayer:GetAttribute("EquippedSlot"))

		-- Listen for loadout changes
		self._loadoutConn = localPlayer:GetAttributeChangedSignal("SelectedLoadout"):Connect(function()
			self:_parseLoadout(localPlayer:GetAttribute("SelectedLoadout"))
			-- Re-equip current slot with new loadout
			self:_equipSlotWeapon(self.CurrentEquippedSlot)
		end)

		-- Listen for equipped slot changes
		self._slotConn = localPlayer:GetAttributeChangedSignal("EquippedSlot"):Connect(function()
			self:_equipSlotWeapon(localPlayer:GetAttribute("EquippedSlot"))
		end)

		self._emoteConn = localPlayer:GetAttributeChangedSignal("IsEmoting"):Connect(function()
			local isEmoting = localPlayer:GetAttribute("IsEmoting") == true
			self._isEmoting = isEmoting

			if isEmoting then
				if self.WeaponManager then
					self.WeaponManager:UnequipWeapon()
					self._weaponHiddenByEmote = true
					vmLog("Hide third-person weapon due to emote")
				end
			elseif self._weaponHiddenByEmote then
				self._weaponHiddenByEmote = false
				self:_equipSlotWeapon(self.CurrentEquippedSlot)
				vmLog("Restore third-person weapon after emote")
			end
		end)

		-- Lobby: remove weapon replication and IK
		self._lobbyConn = localPlayer:GetAttributeChangedSignal("InLobby"):Connect(function()
			local inLobby = localPlayer:GetAttribute("InLobby") == true
			if inLobby then
				if self.WeaponManager then
					self.WeaponManager:UnequipWeapon()
					self._weaponHiddenByLobby = true
					vmLog("Hide third-person weapon due to lobby")
				end
			elseif self._weaponHiddenByLobby then
				self._weaponHiddenByLobby = false
				self:_equipSlotWeapon(self.CurrentEquippedSlot)
				vmLog("Restore third-person weapon after leaving lobby")
			end
		end)
		-- Apply initial lobby state
		if localPlayer:GetAttribute("InLobby") == true then
			if self.WeaponManager then
				self.WeaponManager:UnequipWeapon()
				self._weaponHiddenByLobby = true
			end
		end
	end

	self:_flushPendingViewmodelActions()

	local updateInterval = 1 / ReplicationConfig.UpdateRates.ClientToServer
	self.UpdateConnection = RunService.Heartbeat:Connect(function(dt)
		local currentTime = tick()
		if currentTime - self.LastUpdateTime >= updateInterval then
			self:SendStateUpdate()
			self.LastUpdateTime = currentTime
		end

		self:SyncParts(dt)
	end)
end

function ClientReplicator:Stop()
	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
		self.UpdateConnection = nil
	end

	if self._loadoutConn then
		self._loadoutConn:Disconnect()
		self._loadoutConn = nil
	end

	if self._slotConn then
		self._slotConn:Disconnect()
		self._slotConn = nil
	end

	if self._emoteConn then
		self._emoteConn:Disconnect()
		self._emoteConn = nil
	end

	if self._lobbyConn then
		self._lobbyConn:Disconnect()
		self._lobbyConn = nil
	end

	if self.WeaponManager then
		self.WeaponManager:Destroy()
		self.WeaponManager = nil
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
	self.CurrentLoadout = nil
	self.CurrentEquippedSlot = nil
	self._isEmoting = false
	self._weaponHiddenByEmote = false
	self._weaponHiddenByLobby = false
	self._viewmodelActionSequence = 0
	self._lastViewmodelActionTimes = {}
	self._pendingViewmodelActions = {}
	self._activeViewmodelActionTracks = {}
end

-- Parse the JSON loadout from player attribute
function ClientReplicator:_parseLoadout(raw)
	if type(raw) ~= "string" or raw == "" then
		self.CurrentLoadout = nil
		return
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)

	if not ok or type(decoded) ~= "table" then
		self.CurrentLoadout = nil
		return
	end

	-- Handle both {loadout: {...}} and direct loadout format
	local loadout = decoded.loadout or decoded
	self.CurrentLoadout = loadout
end

local function getEquippedSkinForWeapon(weaponId)
	if type(weaponId) ~= "string" or weaponId == "" then
		return ""
	end

	local ok, skinId = pcall(function()
		return PlayerDataTable.getEquippedSkin(weaponId)
	end)
	if not ok or type(skinId) ~= "string" or skinId == "" then
		return ""
	end

	return skinId
end

-- Force re-parse loadout and re-equip (for respawn deep refresh)
function ClientReplicator:ForceLoadoutRefresh()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	self:_parseLoadout(localPlayer:GetAttribute("SelectedLoadout"))
	self:_equipSlotWeapon(localPlayer:GetAttribute("EquippedSlot"))
end

-- Equip the weapon for a slot on the third-person rig
function ClientReplicator:_equipSlotWeapon(slot)
	self.CurrentEquippedSlot = slot
	vmLog("EquipSlotWeapon", "slot=", tostring(slot), "hasLoadout=", self.CurrentLoadout ~= nil)

	if not self.WeaponManager then
		return
	end

	if self._isEmoting then
		self.WeaponManager:UnequipWeapon()
		self._weaponHiddenByEmote = true
		vmLog("Skip equip while emoting")
		return
	end

	if self._weaponHiddenByLobby then
		self.WeaponManager:UnequipWeapon()
		vmLog("Skip equip while in lobby")
		return
	end

	if not slot or slot == "" then
		self.WeaponManager:UnequipWeapon()
		self:ReplicateViewmodelAction("", "", "Unequip", "", false)
		vmLog("Unequip due to empty slot")
		return
	end

	-- Get weapon ID from loadout
	local weaponId = nil
	if slot == "Fists" then
		weaponId = "Fists"
	elseif self.CurrentLoadout and type(self.CurrentLoadout) == "table" then
		weaponId = self.CurrentLoadout[slot]
	end

	if not weaponId or weaponId == "" then
		self.WeaponManager:UnequipWeapon()
		self:ReplicateViewmodelAction("", "", "Unequip", "", false)
		vmLog("Unequip due to no weapon", "slot=", tostring(slot), "weaponId=", tostring(weaponId))
		return
	end

	local skinId = getEquippedSkinForWeapon(weaponId)

	-- Equip the weapon
	local success = self.WeaponManager:EquipWeapon(weaponId, skinId)
	if success then
		self:ReplicateViewmodelAction(weaponId, skinId, "Equip", "Equip", true)
		vmLog("Local equip success", "weaponId=", tostring(weaponId))
	else
		vmLog("Local equip failed", "weaponId=", tostring(weaponId))
	end
	
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

function ClientReplicator:SyncParts(dt)
	dt = dt or 0.016 -- Fallback to ~60fps
	
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

	if self.WeaponManager then
		local isCrouched = MovementStateManager:IsCrouching() or MovementStateManager:IsSliding()
		self.WeaponManager:SetCrouching(isCrouched)
		self.WeaponManager:UpdateTransform(rootCFrame, self:_getAimPitch(), dt)
	end

end

function ClientReplicator:_getAimPitch()
	local cameraController = ServiceRegistry:GetController("CameraController")
	if cameraController and type(cameraController.GetCameraAngles) == "function" then
		local angles = cameraController:GetCameraAngles()
		if angles then
			return tonumber(angles.Y) or 0
		end
	end

	local camera = workspace.CurrentCamera
	if camera then
		local lookY = math.clamp(camera.CFrame.LookVector.Y, -1, 1)
		return math.deg(math.asin(lookY))
	end

	return 0
end

function ClientReplicator:ReplicateViewmodelAction(weaponId, skinId, actionName, trackName, isActive)
	if not self._net then
		return
	end

	if not self.IsActive then
		local queue = self._pendingViewmodelActions
		if not queue then
			queue = {}
			self._pendingViewmodelActions = queue
		end
		table.insert(queue, {
			WeaponId = weaponId,
			SkinId = skinId,
			ActionName = actionName,
			TrackName = trackName,
			IsActive = isActive,
		})
		while #queue > 24 do
			table.remove(queue, 1)
		end
		return
	end

	local now = workspace:GetServerTimeNow()
	self:_sendViewmodelAction(weaponId, skinId, actionName, trackName, isActive, now)
end

function ClientReplicator:_sendViewmodelAction(weaponId, skinId, actionName, trackName, isActive, now)
	local localPlayer = Players.LocalPlayer
	if localPlayer and localPlayer:GetAttribute("InLobby") == true then
		return
	end

	skinId = tostring(skinId or "")
	actionName = tostring(actionName or "")
	trackName = tostring(trackName or "")
	local actionTrackState = self._activeViewmodelActionTracks
	if type(actionTrackState) ~= "table" then
		actionTrackState = {}
		self._activeViewmodelActionTracks = actionTrackState
	end

	if actionName == "Unequip" or actionName == "Equip" then
		table.clear(actionTrackState)
	elseif isSingleTrackViewmodelAction(actionName) and isActive == true and trackName ~= "" then
		local stateKey = string.format("%s|%s", tostring(weaponId or ""), actionName)
		local previousTrack = actionTrackState[stateKey]
		if type(previousTrack) == "string" and previousTrack ~= "" and previousTrack ~= trackName then
			self:_sendViewmodelAction(weaponId, skinId, actionName, previousTrack, false, now)
		end
	end

	now = now or workspace:GetServerTimeNow()
	local minInterval = ReplicationConfig.ViewmodelActions and ReplicationConfig.ViewmodelActions.MinInterval or 0.03
	local actionKey = string.format("%s|%s|%s", tostring(actionName), tostring(trackName), tostring(isActive == true))
	local lastSentAt = self._lastViewmodelActionTimes[actionKey] or 0
	if now - lastSentAt < minInterval then
		return
	end

	self._lastViewmodelActionTimes[actionKey] = now
	self._viewmodelActionSequence = (self._viewmodelActionSequence + 1) % 65536

	local compressed = CompressionUtils:CompressViewmodelAction(
		localPlayer and localPlayer.UserId or 0,
		weaponId,
		skinId,
		actionName,
		trackName,
		isActive,
		self._viewmodelActionSequence,
		now
	)

	if compressed then
		self._net:FireServer("ViewmodelActionUpdate", compressed)
		vmLog("Sent action", "weaponId=", tostring(weaponId), "action=", tostring(actionName), "track=", tostring(trackName), "active=", tostring(isActive))

		if isSingleTrackViewmodelAction(actionName) then
			local stateKey = string.format("%s|%s", tostring(weaponId or ""), actionName)
			if isActive == true and trackName ~= "" then
				actionTrackState[stateKey] = trackName
			elseif actionTrackState[stateKey] == trackName then
				actionTrackState[stateKey] = nil
			end
		end
	end
end

function ClientReplicator:_flushPendingViewmodelActions()
	if not self.IsActive then
		return
	end

	local queue = self._pendingViewmodelActions
	if not queue or #queue == 0 then
		return
	end

	for _, payload in ipairs(queue) do
		self:_sendViewmodelAction(payload.WeaponId, payload.SkinId, payload.ActionName, payload.TrackName, payload.IsActive)
	end

	self._pendingViewmodelActions = {}
end

function ClientReplicator:SendStateUpdate()
	if not self.IsActive or not self.Character or not self.PrimaryPart then
		return
	end

	local position = self.PrimaryPart.Position
	local rotation = self.PrimaryPart.CFrame
	local velocity = self.PrimaryPart.AssemblyLinearVelocity
	local timestamp = workspace:GetServerTimeNow()
	local isGrounded = MovementStateManager:GetIsGrounded()
	local aimPitch = self:_getAimPitch()

	local animationController = ServiceRegistry:GetController("AnimationController")
	local animationId = animationController and animationController:GetCurrentAnimationId() or 1

	local rigTilt = RigRotationUtils:GetCurrentTilt(self.Character) or 0

	-- Track animation changes for retransmit window (unreliable transport can drop packets)
	if self.LastSentState and self.LastSentState.AnimationId ~= animationId then
		self._lastAnimChangeTime = timestamp
	end

	-- Keep sending briefly after an animation change to improve delivery under packet loss.
	local ANIM_RETRANSMIT_WINDOW = 0.6
	local recentAnimChange = (timestamp - self._lastAnimChangeTime) < ANIM_RETRANSMIT_WINDOW

	-- Heartbeat: force periodic updates even when unchanged for server-side history safety.
	local HEARTBEAT_INTERVAL = 0.75
	local timeSinceLastForced = timestamp - self.LastForcedUpdateTime
	local forceHeartbeat = timeSinceLastForced >= HEARTBEAT_INTERVAL

	if ReplicationConfig.Compression.UseDeltaCompression and self.LastSentState and not forceHeartbeat then
		local shouldSendPosition = CompressionUtils:ShouldSendPositionUpdate(self.LastSentState.Position, position)
		local shouldSendRotation = CompressionUtils:ShouldSendRotationUpdate(self.LastSentState.Rotation, rotation)
		local shouldSendVelocity = CompressionUtils:ShouldSendVelocityUpdate(self.LastSentState.Velocity, velocity)
		local shouldSendGrounded = (self.LastSentState.IsGrounded ~= isGrounded)
		local shouldSendAnimation = (self.LastSentState.AnimationId ~= animationId)
		local shouldSendRigTilt = math.abs((self.LastSentState.RigTilt or 0) - rigTilt) > 1
		local shouldSendAimPitch = CompressionUtils:ShouldSendAimPitchUpdate(self.LastSentState.AimPitch, aimPitch)

		if
			not shouldSendPosition
			and not shouldSendRotation
			and not shouldSendVelocity
			and not shouldSendGrounded
			and not shouldSendAnimation
			and not shouldSendRigTilt
			and not shouldSendAimPitch
			and not recentAnimChange
		then
			return
		end
	end
	
	-- Update heartbeat timer
	self.LastForcedUpdateTime = timestamp

	self.SequenceNumber = (self.SequenceNumber + 1) % 65536

	local compressedState = CompressionUtils:CompressState(
		position,
		rotation,
		velocity,
		timestamp,
		isGrounded,
		animationId,
		rigTilt,
		self.SequenceNumber,
		aimPitch
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
		AimPitch = aimPitch,
	}
end

return ClientReplicator
