--[[
	Aki Client Kit
	
	Ability: Kon - Summon devil that rushes to target location and bites
	
	Flow:
	1. Press E → Play animation → Freezes at "freeze" marker
	2. Hold → Animation frozen, player can aim
	3. Release E → Animation continues, events trigger ability
	
	Animation Events:
	- freeze: Pause animation (Speed = 0)
	- spawn: Spawn Kon via VFXRep
	- bite: Hitbox + knockback + send to server
	- _finish: Cleanup and restore weapon
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local Hitbox = require(Locations.Shared.Util:WaitForChild("Hitbox"))
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))
local Dialogue = require(ReplicatedStorage:WaitForChild("Dialogue"))

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_RANGE = 150
local BITE_RADIUS = 12
local BITE_KNOCKBACK_PRESET = "Fling"
local VM_ANIM_NAME = "Kon"
local RELEASE_ANIM_SPEED = 1.67
local HITBOX_PREVIEW_FADE_TIME = 0.2
local HITBOX_PREVIEW_FLOOR_PITCH_DEG = 90
local GROUND_SNAP_HEIGHT = 12
local GROUND_SNAP_DISTANCE = 180

-- Sound Configuration & Preloading
local SOUND_CONFIG = {
	start = { id = "rbxassetid://105009462750670", volume = 1 },
}

local preloadItems = {}
for name, config in pairs(SOUND_CONFIG) do
	if not script:FindFirstChild(name) then
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = config.id
		sound.Volume = config.volume
		sound.Parent = script
	end
	table.insert(preloadItems, script:FindFirstChild(name))
end
ContentProvider:PreloadAsync(preloadItems)

-- Voice Lines with subtitles
local ABILITY_VOICE_LINES = {
	{ soundId = "rbxassetid://88406145669909", text = "Kon—tear into 'em!" },
	{ soundId = "rbxassetid://96250233556151", text = "Devourer Fang!" },
	{ soundId = "rbxassetid://83671676663633", text = "Kon!" },
}
local HIT_VOICE_LINE = { soundId = "rbxassetid://138015603446992", text = "Got you!" }

--------------------------------------------------------------------------------
-- Raycast Setup
--------------------------------------------------------------------------------

local TargetParams = RaycastParams.new()
TargetParams.FilterType = Enum.RaycastFilterType.Exclude

--------------------------------------------------------------------------------
-- Voice Line Helpers
--------------------------------------------------------------------------------

local function showSubtitle(text: string)
	-- Fire subtitle event for the Dialogue UI
	Dialogue.onLine:fire({
		character = "Aki",
		text = text,
		speaker = true,
		audience = "Self",
	})
	
	-- Auto-hide after a delay
	task.delay(2.5, function()
		Dialogue.onFinish:fire({ key = "Aki" })
	end)
end

local function playVoiceLine(voiceData: { soundId: string, text: string }, parent: Instance?)
	local character = LocalPlayer.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if not root then return end
	
	-- Play sound
	local sound = Instance.new("Sound")
	sound.SoundId = voiceData.soundId
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMaxDistance = 50
	sound.Parent = parent or root
	if not sound.IsLoaded then
		ContentProvider:PreloadAsync({ sound })
	end
	sound:Play()
	Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 0.5)
	
	-- Show subtitle
	if voiceData.text then
		showSubtitle(voiceData.text)
	end
end

local function playRandomAbilityVoice(parent: Instance?)
	local randomIndex = math.random(1, #ABILITY_VOICE_LINES)
	playVoiceLine(ABILITY_VOICE_LINES[randomIndex], parent)
end

local function playHitVoice(parent: Instance?)
	playVoiceLine(HIT_VOICE_LINE, parent)
end

-- Active ability sounds (for cleanup on cancel)
local activeSounds = {}

local function playStartSound(viewmodelRig: any): Sound?
	-- Play the "start" sound on the viewmodel root part
	local startSound = script:FindFirstChild("start")
	if not startSound then return nil end
	
	local rootPart = viewmodelRig and viewmodelRig.Model and viewmodelRig.Model:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end
	
	local sound = startSound:Clone()
	sound.Parent = rootPart
	sound:Play()

	-- Track for cleanup
	table.insert(activeSounds, sound)
	Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 0.5)

	return sound
end

local function playAbilityVoice(viewmodelRig: any): Sound?
	-- Play random ability voice on viewmodel root
	local randomIndex = math.random(1, #ABILITY_VOICE_LINES)
	local voiceData = ABILITY_VOICE_LINES[randomIndex]
	
	local rootPart = viewmodelRig and viewmodelRig.Model and viewmodelRig.Model:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end
	
	local sound = Instance.new("Sound")
	sound.SoundId = voiceData.soundId
	sound.Volume = 1
	sound.Parent = rootPart
	if not sound.IsLoaded then
		ContentProvider:PreloadAsync({ sound })
	end
	sound:Play()

	-- Track for cleanup
	table.insert(activeSounds, sound)
	Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 0.5)
	
	-- Show subtitle
	if voiceData.text then
		showSubtitle(voiceData.text)
	end
	
	return sound
end

local function cleanupSounds()
	for _, sound in ipairs(activeSounds) do
		if sound and sound.Parent then
			sound:Destroy()
		end
	end
	activeSounds = {}
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local Aki = {}
Aki.__index = Aki

Aki.Ability = {}
Aki.Ultimate = {}

Aki._ctx = nil
Aki._connections = {}

-- Active ability state
Aki._abilityState = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getTargetLocation(character: Model, maxDistance: number): (CFrame?, Vector3?)
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not root then return nil, nil end

	local filterList = { character }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(filterList, player.Character)
		end
	end
	local dummiesFolder = Workspace:FindFirstChild("Dummies")
	if dummiesFolder then
		table.insert(filterList, dummiesFolder)
	end
	local effectsFolder = Workspace:FindFirstChild("Effects")
	if effectsFolder then
		table.insert(filterList, effectsFolder)
	end
	TargetParams.FilterDescendantsInstances = filterList

	local camCF = Workspace.CurrentCamera.CFrame
	local result = Workspace:Raycast(camCF.Position, camCF.LookVector * maxDistance, TargetParams)
	local desiredPoint = result and result.Position or (camCF.Position + camCF.LookVector * maxDistance)

	local downResult = Workspace:Raycast(
		desiredPoint + Vector3.new(0, GROUND_SNAP_HEIGHT, 0),
		Vector3.new(0, -GROUND_SNAP_DISTANCE, 0),
		TargetParams
	)
	if downResult then
		local floorPos = downResult.Position
		local camPos = Vector3.new(camCF.Position.X, floorPos.Y, camCF.Position.Z)
		local dirRelToCam = floorPos - camPos
		if dirRelToCam.Magnitude < 0.001 then
			dirRelToCam = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
		end
		if dirRelToCam.Magnitude < 0.001 then
			dirRelToCam = Vector3.zAxis
		end
		return CFrame.lookAt(floorPos, floorPos + dirRelToCam.Unit), downResult.Normal
	end

	if result and result.Instance and result.Instance.Transparency ~= 1 then
		local hitPosition = result.Position
		local normal = result.Normal
		
		if normal.Y > 0.5 then
			-- Floor: Kon stands upright, faces direction from camera
			local camPos = Vector3.new(camCF.Position.X, hitPosition.Y, camCF.Position.Z)
			local dirRelToCam = CFrame.lookAt(camPos, hitPosition).LookVector
			return CFrame.lookAt(hitPosition, hitPosition + dirRelToCam), normal
		else
			-- Wall/ceiling: Kon faces outward from surface
			return CFrame.new(hitPosition, hitPosition + normal), normal
		end
	else
		local hitPos = camCF.Position + camCF.LookVector * maxDistance
		result = Workspace:Raycast(hitPos + Vector3.new(0, 5, 0), Vector3.yAxis * -GROUND_SNAP_DISTANCE, TargetParams)
		if result then
			return CFrame.lookAt(result.Position, result.Position + camCF.LookVector), result.Normal
		end
	end

	return nil, nil
end

local function getEffectsFolder()
	local folder = Workspace:FindFirstChild("Effects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder
end

local function getHitboxTemplate(): Instance?
	return script:FindFirstChild("hitbox") or script:FindFirstChild("Hitbox")
end

local function setPreviewPivot(preview: Instance, pivot: CFrame, surfaceNormal: Vector3?)
	if not preview or not preview.Parent or typeof(pivot) ~= "CFrame" then
		return
	end

	local adjustedPivot = pivot
	if typeof(surfaceNormal) == "Vector3" and surfaceNormal.Y > 0.5 then
		adjustedPivot = adjustedPivot * CFrame.Angles(math.rad(HITBOX_PREVIEW_FLOOR_PITCH_DEG), 0, 0)
	end

	if preview:IsA("Model") then
		preview:PivotTo(adjustedPivot)
		return
	end

	if preview:IsA("BasePart") then
		preview.CFrame = adjustedPivot
		return
	end

	local posNode = preview:FindFirstChild("Pos", true)
	if posNode then
		if posNode:IsA("Model") then
			posNode:PivotTo(adjustedPivot)
		elseif posNode:IsA("BasePart") then
			posNode.CFrame = adjustedPivot
		elseif posNode:IsA("Attachment") then
			local ok = pcall(function()
				posNode.WorldCFrame = adjustedPivot
			end)
			if not ok then
				pcall(function()
					posNode.CFrame = adjustedPivot
				end)
			end
		end
	end
end

local function startHitboxPreview(state)
	if not state then
		return
	end
	if state.hitboxPreviewConnection then
		state.hitboxPreviewConnection:Disconnect()
		state.hitboxPreviewConnection = nil
	end
	if state.hitboxPreview and state.hitboxPreview.Parent then
		state.hitboxPreview:Destroy()
	end

	local template = getHitboxTemplate()
	if not template then
		return
	end

	local preview = template:Clone()
	preview.Name = "KonHitboxPreview"
	preview.Parent = getEffectsFolder()
	state.hitboxPreview = preview

	local function updatePreview()
		if not state.active or state.cancelled or state.released then
			return
		end
		local targetCFrame, surfaceNormal = getTargetLocation(state.character, MAX_RANGE)
		if not targetCFrame then
			return
		end
		state.previewTargetCFrame = targetCFrame
		state.previewSurfaceNormal = surfaceNormal or Vector3.yAxis
		setPreviewPivot(preview, targetCFrame, state.previewSurfaceNormal)
	end

	updatePreview()
	state.hitboxPreviewConnection = RunService.RenderStepped:Connect(updatePreview)
end

local function fadeBeam(beam: Beam, duration: number)
	if not beam or not beam.Parent then
		return
	end

	if duration <= 0 then
		beam.Transparency = NumberSequence.new(1)
		return
	end

	local startSeq = beam.Transparency
	local startTime = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not beam or not beam.Parent then
			if connection then
				connection:Disconnect()
			end
			return
		end

		local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)
		local keypoints = startSeq.Keypoints
		local faded = table.create(#keypoints)
		for i, keypoint in ipairs(keypoints) do
			local value = keypoint.Value + (1 - keypoint.Value) * alpha
			faded[i] = NumberSequenceKeypoint.new(keypoint.Time, value, keypoint.Envelope)
		end
		beam.Transparency = NumberSequence.new(faded)

		if alpha >= 1 and connection then
			connection:Disconnect()
		end
	end)
end

local function stopHitboxPreview(state, fadeDuration: number?)
	if not state then
		return
	end

	if state.hitboxPreviewConnection then
		state.hitboxPreviewConnection:Disconnect()
		state.hitboxPreviewConnection = nil
	end

	local preview = state.hitboxPreview
	state.hitboxPreview = nil
	state.previewTargetCFrame = nil
	state.previewSurfaceNormal = nil

	if not preview or not preview.Parent then
		return
	end

	local duration = tonumber(fadeDuration) or HITBOX_PREVIEW_FADE_TIME
	duration = math.max(0, duration)

	if duration <= 0 then
		preview:Destroy()
		return
	end

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTargets = { preview }
	for _, descendant in ipairs(preview:GetDescendants()) do
		table.insert(fadeTargets, descendant)
	end

	for _, instance in ipairs(fadeTargets) do
		if instance:IsA("BasePart") then
			local ok = pcall(function()
				TweenService:Create(instance, tweenInfo, { Transparency = 1 }):Play()
			end)
			if not ok then
				-- Ignore unknown/customized instances
			end
		elseif instance:IsA("Decal") or instance:IsA("Texture") then
			local ok = pcall(function()
				TweenService:Create(instance, tweenInfo, { Transparency = 1 }):Play()
			end)
			if not ok then
				-- Ignore unknown/customized instances
			end
		elseif instance:IsA("Beam") then
			fadeBeam(instance, duration)
		end
	end

	task.delay(duration + 0.05, function()
		if preview and preview.Parent then
			preview:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------
-- Ability: Kon
--------------------------------------------------------------------------------

function Aki.Ability:OnStart(abilityRequest)
	local hrp = abilityRequest.humanoidRootPart
	local character = abilityRequest.character
	if not hrp or not character then return end

	local kitController = ServiceRegistry:GetController("Kit")

	if kitController:IsAbilityActive() then return end
	if abilityRequest.IsOnCooldown() then return end

	-- Start ability
	local ctx = abilityRequest.StartAbility()
	local unlock = kitController:LockWeaponSwitch()

	-- Play viewmodel animation
	local viewmodelAnimator = ctx.viewmodelAnimator
	local viewmodelController = abilityRequest.viewmodelController
	local viewmodelRig = viewmodelController and viewmodelController:GetActiveRig()
	
	local animation = viewmodelAnimator:PlayKitAnimation(VM_ANIM_NAME, {
		priority = Enum.AnimationPriority.Action4,
		stopOthers = true,
	})

	if not animation then
		unlock()
		kitController:_unholsterWeapon()
		return
	end

	-- Play start sound + voice line immediately on ability fire
	playStartSound(viewmodelRig)
	playAbilityVoice(viewmodelRig)

	-- State tracking
	local state = {
		active = true,
		released = false,
		cancelled = false,
		animation = animation,
		unlock = unlock,
		abilityRequest = abilityRequest,
		character = character,
		viewmodelRig = viewmodelRig,
		connections = {},
	}
	Aki._abilityState = state

	-- Animation event handlers
	animation:AdjustSpeed(1.3)
	local Events = {
		["freeze"] = function()
			-- Pause animation until released
			if state.active and not state.released then
				animation:AdjustSpeed(0)
				startHitboxPreview(state)
			end
		end,

		["shake"] = function()
			-- Caster viewmodel effects
			VFXRep:Fire("Me", { Module = "Kon", Function = "User" }, {
				ViewModel = viewmodelRig,
				forceAction = "start",
			})
		end,

		["place"] = function()
			if not state.active or state.cancelled then return end
			if viewmodelController:GetActiveSlot() ~= "Fists" then return end

			-- Get target location at moment of spawn (prefer held preview target)
			local targetCFrame = state.previewTargetCFrame
			local surfaceNormal = state.previewSurfaceNormal
			if not targetCFrame then
				targetCFrame, surfaceNormal = getTargetLocation(character, MAX_RANGE)
			end
			if not targetCFrame then return end
			
			surfaceNormal = surfaceNormal or Vector3.yAxis

			state.targetCFrame = targetCFrame

			-- Send to server for validation
			abilityRequest.Send({
				action = "requestKonSpawn",
				targetPosition = { X = targetCFrame.Position.X, Y = targetCFrame.Position.Y, Z = targetCFrame.Position.Z },
				targetLookVector = { X = targetCFrame.LookVector.X, Y = targetCFrame.LookVector.Y, Z = targetCFrame.LookVector.Z },
			})

			-- Spawn Kon for ALL clients via VFXRep
			VFXRep:Fire("All", { Module = "Kon", Function = "createKon" }, {
				position = { X = targetCFrame.Position.X, Y = targetCFrame.Position.Y, Z = targetCFrame.Position.Z },
				lookVector = { X = targetCFrame.LookVector.X, Y = targetCFrame.LookVector.Y, Z = targetCFrame.LookVector.Z },
				surfaceNormal = { X = surfaceNormal.X, Y = surfaceNormal.Y, Z = surfaceNormal.Z },
			})

			local targets = Hitbox.GetCharactersInSphere(targetCFrame.Position, BITE_RADIUS, {
				Exclude = abilityRequest.player,
			})

			-- Knockback
			local knockbackController = ServiceRegistry:GetController("Knockback")
			local hitList = {}
			local hitAnyPlayer = false
			
			for _, targetChar in ipairs(targets) do
				if knockbackController then
					local direction = (targetChar.PrimaryPart.Position - targetCFrame.Position).Unit

					knockbackController:ApplyKnockback(targetChar, direction, {
						upwardVelocity = 60,
						outwardVelocity = 30,
						preserveMomentum = -1.0,
					})
				end

				local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
				if targetPlayer then
					hitAnyPlayer = true
				end
				
				table.insert(hitList, {
					characterName = targetChar.Name,
					playerId = targetPlayer and targetPlayer.UserId or nil,
					isDummy = targetPlayer == nil,
				})
			end
			
			-- Play hit voice if we hit any player
			if hitAnyPlayer then
				task.delay(0.3, playHitVoice)
			end
			
			task.spawn(function()
				task.wait(.6)
				
				if not state.active or state.cancelled then return end
				if viewmodelController:GetActiveSlot() ~= "Fists" then return end
				if not state.targetCFrame then return end

				local bitePosition = state.targetCFrame.Position

				-- Hitbox
				local targets = Hitbox.GetCharactersInSphere(bitePosition, BITE_RADIUS, {
					Exclude = abilityRequest.player,
				})

				-- Knockback
				local knockbackController = ServiceRegistry:GetController("Knockback")
				local hitList = {}

				for _, targetChar in ipairs(targets) do
					if knockbackController then
						local direction = (targetChar.PrimaryPart.Position - bitePosition).Unit
						
						knockbackController:ApplyKnockback(targetChar, direction, {
							upwardVelocity = 150,       -- Good lift (slightly less than jump pad)
							outwardVelocity = 180,     -- Strong horizontal push away
							preserveMomentum = 0.25,
						})

						--knockbackController:ApplyKnockbackPreset(targetChar, `FlingHuge`, bitePosition)
					end

					local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
					table.insert(hitList, {
						characterName = targetChar.Name,
						playerId = targetPlayer and targetPlayer.UserId or nil,
						isDummy = targetPlayer == nil,
					})
				end

				-- Send hits to server
				abilityRequest.Send({
					action = "konBite",
					hits = hitList,
					bitePosition = { X = bitePosition.X, Y = bitePosition.Y, Z = bitePosition.Z },
				})

				-- Caster bite effects
				VFXRep:Fire("Me", { Module = "Kon", Function = "User" }, {
					ViewModel = viewmodelRig,
					forceAction = "bite",
				})
			end)

		end,

		["_finish"] = function()
			if not state.active then return end
			
			state.active = false
			Aki._abilityState = nil

			-- Cleanup connections
			for _, conn in ipairs(state.connections) do
				if typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				end
			end
			stopHitboxPreview(state, 0)

			-- Restore weapon
			state.unlock()
			kitController:_unholsterWeapon()
		end,
	}

	-- Connect to animation events
	state.connections[#state.connections + 1] = animation:GetMarkerReachedSignal("Event"):Connect(function(event)
		if Events[event] then
			Events[event]()
		end
	end)

	-- Handle animation end (safety cleanup)
	state.connections[#state.connections + 1] = animation.Stopped:Once(function()
		if state.active then
			Events["_finish"]()
		end
	end)

	state.connections[#state.connections + 1] = animation.Ended:Once(function()
		if state.active then
			Events["_finish"]()
		end
	end)
end

function Aki.Ability:OnEnded(abilityRequest)
	local state = Aki._abilityState
	if not state or not state.active then return end

	-- Mark as released
	state.released = true

	stopHitboxPreview(state, HITBOX_PREVIEW_FADE_TIME)

	-- Resume animation from freeze
	if state.animation and state.animation.IsPlaying then
		state.animation:AdjustSpeed(RELEASE_ANIM_SPEED)
	end
end

function Aki.Ability:OnInterrupt(abilityRequest, reason)
	local state = Aki._abilityState
	if not state or not state.active then return end

	state.cancelled = true
	state.active = false
	Aki._abilityState = nil

	-- Cleanup active sounds
	cleanupSounds()

	-- Stop animation
	if state.animation and state.animation.IsPlaying then
		state.animation:Stop(0.1)
	end

	stopHitboxPreview(state, HITBOX_PREVIEW_FADE_TIME)

	-- Destroy Kon if spawned
	VFXRep:Fire("All", { Module = "Kon", Function = "destroyKon" }, {})

	-- Cleanup connections
	for _, conn in ipairs(state.connections) do
		if typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end

	-- Restore weapon
	state.unlock()
	ServiceRegistry:GetController("Kit"):_unholsterWeapon()
end

--------------------------------------------------------------------------------
-- Ultimate (placeholder)
--------------------------------------------------------------------------------

function Aki.Ultimate:OnStart(abilityRequest)
	abilityRequest.Send()
end

function Aki.Ultimate:OnEnded(abilityRequest)
end

function Aki.Ultimate:OnInterrupt(abilityRequest, reason)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Aki.new(ctx)
	local self = setmetatable({}, Aki)
	self._ctx = ctx
	self._connections = {}
	self.Ability = Aki.Ability
	self.Ultimate = Aki.Ultimate
	return self
end

function Aki:OnEquip(ctx)
	self._ctx = ctx
end

function Aki:OnUnequip(reason)
	for _, conn in pairs(self._connections) do
		if typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
	end
	self._connections = {}

	-- Cancel active ability
	if Aki._abilityState and Aki._abilityState.active then
		Aki.Ability:OnInterrupt(nil, "unequip")
	end
end

function Aki:Destroy()
	self:OnUnequip("Destroy")
end

return Aki
