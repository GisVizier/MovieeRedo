--[[
	Aki Client Kit
	
	Ability: KON - Two variants:
	
	TRAP VARIANT (E while crouching/sliding):
	- Places a hidden Kon trap at player's feet
	- Red outline visible to all for 1s, then only to owner
	- 1 per match, no cooldown
	- Auto-detects Aki proximity → self-launch away from trap (no damage)
	
	MAIN VARIANT (E while standing):
	- Hold → Aim → Release → Kon spawns at target → Bite
	- Will be reworked into projectile variant later
	
	Animation Events (Main variant):
	- freeze: Pause animation (Speed = 0)
	- place: Spawn Kon via VFXRep + hitbox
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
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))

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

-- Trap variant constants
local TRAP_MAX_RANGE = 35            -- Aiming range for trap placement (studs)
local TRAP_SELF_LAUNCH_RADIUS = 9.5  -- Auto-detect proximity for self-launch
local SELF_LAUNCH_HORIZONTAL = 80    -- Horizontal force away from trap pivot
local SELF_LAUNCH_VERTICAL = 180     -- Upward force for self-launch

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

local function replicateTrackSpeed(trackName: string, speed: number)
	if type(trackName) ~= "string" or trackName == "" then
		return
	end
	if type(speed) ~= "number" then
		return
	end

	local replicationController = ServiceRegistry:GetController("Replication")
	if not replicationController or type(replicationController.ReplicateViewmodelAction) ~= "function" then
		return
	end

	replicationController:ReplicateViewmodelAction("Fists", "SetTrackSpeed", string.format("%s|%s", trackName, tostring(speed)), true)
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

-- Trap state (static - only one local player per client)
Aki._trapPlaced = false          -- Has trap been placed this match?
Aki._trapPosition = nil          -- Vector3 position of the placed trap
Aki._trapProximityConn = nil     -- Heartbeat connection for self-launch proximity
Aki._trapPlayerLeftRadius = false -- Has the player left trap radius since placement?

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

	-- If we directly hit a wall/ceiling (non-floor surface), place there immediately
	if result and result.Instance and result.Instance.Transparency ~= 1 then
		local hitPosition = result.Position
		local normal = result.Normal

		if normal.Y <= 0.5 then
			-- Wall/ceiling: place directly on the surface, facing outward
			return CFrame.new(hitPosition, hitPosition + normal), normal
		end
	end

	-- Otherwise, snap to the ground below the aimed point
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

	-- Direct hit on a floor-like surface but no ground snap found
	if result and result.Instance and result.Instance.Transparency ~= 1 then
		local hitPosition = result.Position
		local normal = result.Normal
		local camPos = Vector3.new(camCF.Position.X, hitPosition.Y, camCF.Position.Z)
		local dirRelToCam = CFrame.lookAt(camPos, hitPosition).LookVector
		return CFrame.lookAt(hitPosition, hitPosition + dirRelToCam), normal
	end

	-- Nothing hit: try one more ground snap at max range
	local hitPos = camCF.Position + camCF.LookVector * maxDistance
	local fallback = Workspace:Raycast(hitPos + Vector3.new(0, 5, 0), Vector3.yAxis * -GROUND_SNAP_DISTANCE, TargetParams)
	if fallback then
		return CFrame.lookAt(fallback.Position, fallback.Position + camCF.LookVector), fallback.Normal
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
		local range = state.maxRange or MAX_RANGE
		local targetCFrame, surfaceNormal = getTargetLocation(state.character, range)
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
-- Trap Variant Helpers
--------------------------------------------------------------------------------

--[[ Clean up trap proximity detection loop ]]
local function cleanupTrapProximity()
	if Aki._trapProximityConn then
		Aki._trapProximityConn:Disconnect()
		Aki._trapProximityConn = nil
	end
end

--[[ Perform the self-launch from the trap: launch straight up, show Kon VFX ]]
local function performSelfLaunch()
	if not Aki._trapPosition then return end

	local character = LocalPlayer.Character
	if not character then return end

	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local trapPos = Aki._trapPosition

	-- Force uncrouch / unslide before launching (same pattern as HonoredOne)
	LocalPlayer:SetAttribute("ForceUncrouch", true)
	LocalPlayer:SetAttribute("BlockCrouchWhileAbility", true)
	LocalPlayer:SetAttribute("BlockSlideWhileAbility", true)

	-- Stop sliding if active
	if MovementStateManager:IsSliding() or MovementStateManager:IsCrouching() then
		MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
	end

	-- Clear the gate after a short delay so player can crouch/slide again after landing
	task.delay(1.5, function()
		LocalPlayer:SetAttribute("ForceUncrouch", nil)
		LocalPlayer:SetAttribute("BlockCrouchWhileAbility", nil)
		LocalPlayer:SetAttribute("BlockSlideWhileAbility", nil)
	end)

	-- Launch straight up
	local launchVelocity = Vector3.new(0, SELF_LAUNCH_VERTICAL, 0)

	-- Clear vertical velocity for a clean launch
	root.AssemblyLinearVelocity *= Vector3.new(1, 0, 1)

	-- Apply launch via MovementController
	local movementController = ServiceRegistry:GetController("Movement")
		or ServiceRegistry:GetController("MovementController")
	if movementController and movementController.BeginExternalLaunch then
		movementController:BeginExternalLaunch(launchVelocity, 0.28)
	else
		root.AssemblyLinearVelocity = launchVelocity
	end

	-- Send to server for validation
	local kitController = ServiceRegistry:GetController("Kit")
	if kitController then
		kitController:requestActivateAbility("Ability", Enum.UserInputState.Begin, {
			action = "selfLaunch",
			allowMultiple = true,
		})
	end

	-- Destroy trap marker (instant local + relay to others)
	VFXRep:Fire("Me", { Module = "Kon", Function = "destroyTrap" }, {})
	VFXRep:Fire("Others", { Module = "Kon", Function = "destroyTrap" }, {})

	-- Spawn Kon at trap position (same proven createKon visual as normal ability)
	local lookDir = root.CFrame.LookVector
	local konVfxData = {
		position = { X = trapPos.X, Y = trapPos.Y, Z = trapPos.Z },
		lookVector = { X = lookDir.X, Y = lookDir.Y, Z = lookDir.Z },
		surfaceNormal = { X = 0, Y = 1, Z = 0 },
	}
	VFXRep:Fire("Me", { Module = "Kon", Function = "createKon" }, konVfxData)
	VFXRep:Fire("Others", { Module = "Kon", Function = "createKon" }, konVfxData)

	-- Clean up local trap state (allow re-placement)
	Aki._trapPlaced = false
	Aki._trapPosition = nil
	Aki._trapPlayerLeftRadius = false
	cleanupTrapProximity()
end

--[[ Start proximity detection loop for self-launch.
     Only triggers once the player has LEFT the trap radius and returned. ]]
local function startSelfLaunchProximity()
	cleanupTrapProximity()

	Aki._trapPlayerLeftRadius = false -- Must leave radius first before self-launch activates

	Aki._trapProximityConn = RunService.Heartbeat:Connect(function()
		-- Guard: if trap was destroyed, stop checking
		if not Aki._trapPosition then
			Aki._trapPlaced = false
			cleanupTrapProximity()
			return
		end

		-- Check if the VFX trap marker still exists (server may have triggered/destroyed it)
		local effectsFolder = Workspace:FindFirstChild("Effects")
		local markerName = "KonTrap_" .. tostring(LocalPlayer.UserId)
		local marker = effectsFolder and effectsFolder:FindFirstChild(markerName)
		if not marker then
			-- Trap was destroyed externally (triggered by enemy or server cleanup)
			Aki._trapPlaced = false
			Aki._trapPosition = nil
			Aki._trapPlayerLeftRadius = false
			cleanupTrapProximity()
			return
		end

		local character = LocalPlayer.Character
		if not character then return end

		local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
		if not root then return end

		local distance = (root.Position - Aki._trapPosition).Magnitude

		-- Player must leave radius before self-launch can activate
		if not Aki._trapPlayerLeftRadius then
			if distance > TRAP_SELF_LAUNCH_RADIUS then
				Aki._trapPlayerLeftRadius = true
			end
			return
		end

		-- Auto-detect: if player is within radius and has previously left, trigger self-launch
		if distance <= TRAP_SELF_LAUNCH_RADIUS then
			performSelfLaunch()
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

	------------------------------------------------------------------------
	-- Detect variant: Crouch/Slide → Trap, Standing → Main
	------------------------------------------------------------------------
	local isCrouching = MovementStateManager:IsCrouching()
	local isSliding = MovementStateManager:IsSliding()
	local isTrapVariant = (isCrouching or isSliding)

	-- Trap-specific guards
	if isTrapVariant then
		if Aki._trapPlaced then return end -- 1 per match
	end

	-- Common guards
	if kitController:IsAbilityActive() then return end
	if not isTrapVariant and abilityRequest.IsOnCooldown() then return end

	------------------------------------------------------------------------
	-- Start ability (both variants use the same animation/hold/release flow)
	------------------------------------------------------------------------
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

	-- Determine ability range based on variant
	local abilityRange = isTrapVariant and TRAP_MAX_RANGE or MAX_RANGE

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
		isTrapPlacement = isTrapVariant,
		maxRange = abilityRange,
	}
	Aki._abilityState = state

	-- Animation event handlers
	animation:AdjustSpeed(1.3)
	local Events = {
		["freeze"] = function()
			-- Pause animation until released (both variants show preview here)
			if state.active and not state.released then
				animation:AdjustSpeed(0)
				replicateTrackSpeed(VM_ANIM_NAME, 0)
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

			-- Get target location at moment of placement (prefer held preview target)
			local targetCFrame = state.previewTargetCFrame
			local surfaceNormal = state.previewSurfaceNormal
			if not targetCFrame then
				targetCFrame, surfaceNormal = getTargetLocation(character, abilityRange)
			end
			if not targetCFrame then return end
			
			surfaceNormal = surfaceNormal or Vector3.yAxis
			state.targetCFrame = targetCFrame

			if state.isTrapPlacement then
				----------------------------------------------------------------
				-- TRAP VARIANT: Place hidden trap at aimed position
				----------------------------------------------------------------
				local pos = targetCFrame.Position

				-- Send to server for validation
				abilityRequest.Send({
					action = "placeTrap",
					position = { X = pos.X, Y = pos.Y, Z = pos.Z },
					allowMultiple = true,
				})

				-- Broadcast trap indicator VFX to all clients
				VFXRep:Fire("All", { Module = "Kon", Function = "placeTrap" }, {
					position = { X = pos.X, Y = pos.Y, Z = pos.Z },
					ownerId = LocalPlayer.UserId,
				})

				-- Update local trap state
				Aki._trapPlaced = true
				Aki._trapPosition = pos

				-- Immediate release check: if Aki is already in radius, self-launch now
				local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - pos).Magnitude <= TRAP_SELF_LAUNCH_RADIUS then
					-- Slight delay so VFX marker has time to appear before self-launch consumes it
					task.delay(0.05, function()
						if Aki._trapPlaced and Aki._trapPosition then
							performSelfLaunch()
						end
					end)
				else
					-- Start self-launch proximity detection (leave-and-return cycle)
					startSelfLaunchProximity()
				end
			else
				----------------------------------------------------------------
				-- MAIN VARIANT: Spawn Kon at aimed position
				----------------------------------------------------------------

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
								upwardVelocity = 150,
								outwardVelocity = 180,
								preserveMomentum = 0.25,
							})
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
			end
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
		replicateTrackSpeed(VM_ANIM_NAME, RELEASE_ANIM_SPEED)
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
	-- Reset trap state on re-equip (handles round restart where kit is re-used)
	Aki._trapPlaced = false
	Aki._trapPosition = nil
	Aki._trapPlayerLeftRadius = false
	cleanupTrapProximity()
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

	-- Clean up trap proximity detection
	cleanupTrapProximity()

	-- Reset trap state (kit is destroyed on death/round end, trap resets)
	Aki._trapPlaced = false
	Aki._trapPosition = nil
	Aki._trapPlayerLeftRadius = false
end

function Aki:Destroy()
	self:OnUnequip("Destroy")
end

return Aki
