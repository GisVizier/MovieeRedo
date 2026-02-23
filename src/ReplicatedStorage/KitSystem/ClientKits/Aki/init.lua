--[[
	Aki Client Kit
	
	Ability: KON - Two variants:
	
	TRAP VARIANT (E while crouching/sliding):
	- Uses legacy VM animation ("Kon")
	- Places a hidden Kon trap at aimed position (red hitbox preview)
	- Server handles ALL detection (enemies + Aki self-launch)
	- 1 per kit equip, no cooldown
	
	MAIN VARIANT (E while standing) — PROJECTILE:
	- Uses new VM animations ("Konstart" → "Konthrow")
	- Hold E → Kon model spawns, follows camera, plays start anim
	- During hold: hitbox preview at predicted landing point (down-ray snapped)
	- Release E → Throw animation plays on both viewmodel AND Kon
	- Kon flies as a projectile, pierces breakable walls, stops at unbreakable
	- On impact: hitbox for 35 dmg + KonSlow, self-launch if Aki in radius, VoxelDestruction
	- Replicated to all clients via VFXRep
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
local ProjectilePhysics = require(Locations.Shared.Util:WaitForChild("ProjectilePhysics"))
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
local RELEASE_ANIM_SPEED = 1.67
local HITBOX_PREVIEW_FADE_TIME = 0.2
local HITBOX_PREVIEW_FLOOR_PITCH_DEG = 90
local GROUND_SNAP_HEIGHT = 12
local GROUND_SNAP_DISTANCE = 180

-- Viewmodel animation names (instances in Assets/Animations/ViewModel/Kits/Aki/)
local VM_START_ANIM_NAME = "Konstart"   -- Start animation (effectsplace→effectcharge→effectspawn→freeze→_finish)
local VM_THROW_ANIM_NAME = "Konthrow"   -- Throw animation (throw→_finish)
local VM_OLD_ANIM_NAME   = "Kon"        -- Legacy/trap variant animation

-- Trap variant constants
local TRAP_MAX_RANGE = 35            -- Aiming range for trap placement (studs)

-- Projectile variant constants (Main)
local PROJ_SPEED = 130               -- Studs/sec (strong arcing projectile)
local PROJ_DRAG = 0.005              -- Minimal air resistance
local PROJ_GRAVITY = 80              -- Reduced gravity for nice arc (workspace = 196.2)
local PROJ_MAX_RANGE = 500           -- Max distance before auto-despawn
local PROJ_LIFETIME = PROJ_MAX_RANGE / PROJ_SPEED + 2 -- generous lifetime
local PROJ_IMPACT_RADIUS = 10        -- Damage radius at impact
local PROJ_IMPACT_DAMAGE = 35        -- Damage at impact
local PROJ_KON_SCALE = 4             -- Scale factor for flying Kon
local PROJ_REPLICATION_INTERVAL = 1 / 18 -- How often we replicate position to server
local PROJ_DESTROY_INTERVAL = 1 / 12    -- How often we send destruction ticks along flight path
local PROJ_CHAR_HIT_RADIUS = 5          -- Proximity radius for hitting characters during flight
local SELF_LAUNCH_VERTICAL = 130         -- Upward velocity for self-launch (studs/sec)

-- Kon model animation IDs (played on the Kon rig itself, not the viewmodel)
local KON_START_ANIM_ID = "126864813156157"   -- Plays on Kon model during hold phase
local KON_THROW_ANIM_ID = "78604376351893"   -- Plays on Kon model during throw
local KON_FLY_ANIM_ID = "138478054902806"    -- Loops on Kon model during flight

-- Projectile physics config
local PROJ_PHYSICS_CONFIG = {
	speed = PROJ_SPEED,
	gravity = PROJ_GRAVITY,
	drag = PROJ_DRAG,
	lifetime = PROJ_LIFETIME,
}

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
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart or character:FindFirstChild("Root"))
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

	replicationController:ReplicateViewmodelAction("Fists", "", "SetTrackSpeed", string.format("%s|%s", trackName, tostring(speed)), true)
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
Aki._projectileInFlight = false  -- True while a Kon projectile is active (blocks new ability use)
Aki._holding = false             -- True from OnStart, false from OnEnded — used by freeze handler

-- Trap state (static - only one local player per client)
Aki._trapPlaced = false          -- Has trap been placed this kit equip?

-- Active Kon models per userId — lifecycle tracking (used by rep mod too via exports)
Aki._activeKons = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getTargetLocation(character: Model, maxDistance: number): (CFrame?, Vector3?)
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart or character:FindFirstChild("Root")
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
	-- Exclude camera children (viewmodel rig can block the ray)
	if Workspace.CurrentCamera then
		table.insert(filterList, Workspace.CurrentCamera)
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
-- Arc Landing Preview (Main Variant — Hitbox model at predicted landing)
--------------------------------------------------------------------------------

local ARC_SIM_STEP = 1 / 30           -- Simulation time step
local ARC_SIM_MAX_STEPS = 120         -- Max simulation steps (~4 sec of flight)

-- Raycast params for arc prediction (excludes characters, dummies, effects — only hits world map)
local function buildArcRayParams(character)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { character }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(filterList, player.Character)
		end
	end
	local dummiesFolder = Workspace:FindFirstChild("Dummies")
	if dummiesFolder then table.insert(filterList, dummiesFolder) end  -- exclude dummies so ray hits ground, not dummies
	local effectsFolder = Workspace:FindFirstChild("Effects")
	if effectsFolder then table.insert(filterList, effectsFolder) end
	local voxelCache = Workspace:FindFirstChild("VoxelCache")
	if voxelCache then table.insert(filterList, voxelCache) end
	local destructionFolder = Workspace:FindFirstChild("__Destruction")
	if destructionFolder then table.insert(filterList, destructionFolder) end
	if Workspace.CurrentCamera then table.insert(filterList, Workspace.CurrentCamera) end
	rayParams.FilterDescendantsInstances = filterList
	return rayParams
end

local function startArcPreview(state)
	if not state then return end

	-- Clean up previous preview
	if state.arcPreviewConn then
		state.arcPreviewConn:Disconnect()
		state.arcPreviewConn = nil
	end

	-- Create hitbox preview at predicted landing
	if state.hitboxPreview and state.hitboxPreview.Parent then
		state.hitboxPreview:Destroy()
	end
	local effectsFolder = getEffectsFolder()
	local template = getHitboxTemplate()
	local hitboxPreview = nil
	if template then
		hitboxPreview = template:Clone()
		hitboxPreview.Name = "KonArcEndPreview"
		hitboxPreview.Parent = effectsFolder
	end
	state.hitboxPreview = hitboxPreview

	-- Physics simulator for prediction
	local physics = ProjectilePhysics.new(PROJ_PHYSICS_CONFIG)
	local arcRayParams = buildArcRayParams(state.character)

	local function updateLanding()
		if not state.active or state.cancelled or state.released then return end

		local cam = Workspace.CurrentCamera
		local lookDir = cam.CFrame.LookVector
		-- Smart offset: reduce when aiming steeply down to avoid spawning below floor
		local downDot = math.abs(math.min(0, lookDir.Y))
		local adjustedOffset = 5 * (1 - downDot * 0.9)
		local startPos = cam.CFrame.Position + lookDir * adjustedOffset

		-- Simulate trajectory to find where it ends up
		local position = startPos
		local velocity = lookDir.Unit * PROJ_SPEED
		local hitPos = nil
		local hitNormal = nil

		for _ = 1, ARC_SIM_MAX_STEPS do
			local newPos, newVel, hitResult = physics:Step(position, velocity, ARC_SIM_STEP, arcRayParams)

			if hitResult then
				hitPos = hitResult.Position
				hitNormal = hitResult.Normal
				break
			end

			position = newPos
			velocity = newVel

			if velocity.Magnitude < 1 then break end
		end

		-- Determine the landing point using the same surface projection as the crouch variant
		local endPos = hitPos or position
		local surfNormal = hitNormal or Vector3.yAxis
		local endCF

		if hitNormal and surfNormal.Y <= 0.5 then
			-- Wall/ceiling: place directly on the surface
			endCF = CFrame.new(endPos, endPos + surfNormal)
		else
			-- Floor-like surface or no direct hit: shoot a down-ray to snap to ground
			local downResult = Workspace:Raycast(
				endPos + Vector3.new(0, GROUND_SNAP_HEIGHT, 0),
				Vector3.new(0, -GROUND_SNAP_DISTANCE, 0),
				arcRayParams
			)
			if downResult then
				endPos = downResult.Position
				surfNormal = downResult.Normal
			end

			-- Build a CFrame facing the camera's horizontal look direction
			local camCF = cam.CFrame
			local camPos2d = Vector3.new(camCF.Position.X, endPos.Y, camCF.Position.Z)
			local dirRelToCam = endPos - camPos2d
			if dirRelToCam.Magnitude < 0.001 then
				dirRelToCam = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
			end
			if dirRelToCam.Magnitude < 0.001 then
				dirRelToCam = Vector3.zAxis
			end
			endCF = CFrame.lookAt(endPos, endPos + dirRelToCam.Unit)
		end

		-- Position hitbox preview at landing
		if hitboxPreview and hitboxPreview.Parent then
			setPreviewPivot(hitboxPreview, endCF, surfNormal)
		end
	end

	updateLanding()
	state.arcPreviewConn = RunService.RenderStepped:Connect(updateLanding)
end

local function stopArcPreview(state, fadeDuration: number?)
	if not state then return end

	if state.arcPreviewConn then
		state.arcPreviewConn:Disconnect()
		state.arcPreviewConn = nil
	end

	-- Fade hitbox preview
	local preview = state.hitboxPreview
	state.hitboxPreview = nil
	if not preview or not preview.Parent then return end

	local duration = tonumber(fadeDuration) or HITBOX_PREVIEW_FADE_TIME
	if duration <= 0 then
		preview:Destroy()
		return
	end

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, instance in ipairs({preview, unpack(preview:GetDescendants())}) do
		if instance:IsA("BasePart") then
			pcall(function() TweenService:Create(instance, tweenInfo, { Transparency = 1 }):Play() end)
		elseif instance:IsA("Beam") then
			fadeBeam(instance, duration)
		end
	end
	task.delay(duration + 0.05, function()
		if preview and preview.Parent then preview:Destroy() end
	end)
end

--------------------------------------------------------------------------------
-- Kon Model Helpers (Projectile Variant)
--------------------------------------------------------------------------------

-- Get the konny template from the Kon VFX module
local function getKonnyTemplate()
	local konModule = ReplicatedStorage:FindFirstChild("Game")
		and ReplicatedStorage.Game:FindFirstChild("Replication")
		and ReplicatedStorage.Game.Replication:FindFirstChild("ReplicationModules")
		and ReplicatedStorage.Game.Replication.ReplicationModules:FindFirstChild("Kon")
	if konModule then
		return konModule:FindFirstChild("konny")
	end
	return nil
end

-- Play an animation on a Kon model by asset ID
local function playKonAnimById(konModel, animId, looped)
	if not konModel then return nil end

	local animController = konModel:FindFirstChildOfClass("AnimationController")
		or konModel:FindFirstChildOfClass("Humanoid")
	if not animController then return nil end

	local animator = animController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animController
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(animId)

	local track = animator:LoadAnimation(anim)
	if looped then
		track.Looped = true
	end
	track:Play()
	return track
end

--------------------------------------------------------------------------------
-- Kon Model Logic (consolidated from ReplicationModules/Kon/init.lua)
-- All Kon model creation, animation, lifecycle, and destruction lives here.
-- Exported on the Aki table so the rep mod can access them via lazy require.
--------------------------------------------------------------------------------

-- Reference to Kon replication module (for accessing templates, Sounds, Clients)
local _konRepModule
local function getKonRepModule()
	if not _konRepModule then
		_konRepModule = ReplicatedStorage:FindFirstChild("Game")
			and ReplicatedStorage.Game:FindFirstChild("Replication")
			and ReplicatedStorage.Game.Replication:FindFirstChild("ReplicationModules")
			and ReplicatedStorage.Game.Replication.ReplicationModules:FindFirstChild("Kon")
	end
	return _konRepModule
end

-- Get the regular Kon model template (non-konny variant)
local function getKonTemplate()
	local mod = getKonRepModule()
	return mod and mod:FindFirstChild("Kon")
end

-- Get the Kon animation object
local function getKonAnimation()
	local mod = getKonRepModule()
	return mod and mod:FindFirstChild("konanim")
end

-- Get the Sounds folder from the rep mod
local function getSoundsFolder()
	local mod = getKonRepModule()
	return mod and mod:FindFirstChild("Sounds")
end

-- Lazy-require the Clients/kon FX module (spawn, bite, smoke, shake)
local _konClientFX
local function getKonClientFX()
	if not _konClientFX then
		local mod = getKonRepModule()
		if mod then
			local clientsFolder = mod:FindFirstChild("Clients")
			local konFX = clientsFolder and clientsFolder:FindFirstChild("kon")
			if konFX then
				_konClientFX = require(konFX)
			end
		end
	end
	return _konClientFX
end

-- Build a CFrame where Kon stands ON the surface (UpVector = surface normal).
-- Works for floors, walls, ceilings, and slopes.
local function buildSurfaceCFrame(position, lookVector, surfaceNormal)
	local projectedLook = lookVector - surfaceNormal * lookVector:Dot(surfaceNormal)

	if projectedLook.Magnitude < 0.01 then
		local worldForward = Vector3.new(0, 0, 1)
		projectedLook = worldForward - surfaceNormal * worldForward:Dot(surfaceNormal)
		if projectedLook.Magnitude < 0.01 then
			local worldRight = Vector3.new(1, 0, 0)
			projectedLook = worldRight - surfaceNormal * worldRight:Dot(surfaceNormal)
		end
	end

	projectedLook = projectedLook.Unit
	local baseCFrame = CFrame.lookAt(position, position + projectedLook, surfaceNormal)
	return baseCFrame * CFrame.Angles(math.rad(90), 0, 0)
end

-- Spawn a Kon model at a surface-aligned CFrame.
-- @param targetCFrame CFrame — where Kon's Center part should land.
-- @param originUserId number
-- @param useKonny     boolean — true = konny template, false = regular Kon template
local function spawnKonModel(targetCFrame, originUserId, useKonny)
	local template = useKonny and getKonnyTemplate() or getKonTemplate()
	if not template then return nil end

	local konModel = template:Clone()
	konModel.Name = "Kon_" .. tostring(originUserId)

	local centerPart = konModel:FindFirstChild("Center")
	if centerPart then
		local centerOffset = konModel:GetPivot():ToObjectSpace(centerPart:GetPivot())
		konModel:PivotTo(targetCFrame * centerOffset:Inverse())
	elseif konModel.PrimaryPart then
		konModel:SetPrimaryPartCFrame(targetCFrame)
	else
		konModel:PivotTo(targetCFrame)
	end

	konModel.Parent = getEffectsFolder()
	return konModel
end

-- Fade out all BaseParts in a Kon model then destroy it.
local function despawnKon(konModel, fadeTime)
	if not konModel or not konModel.Parent then return end

	for _, part in ipairs(konModel:GetDescendants()) do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(fadeTime), { Transparency = 1 }):Play()
		end
	end

	task.delay(fadeTime, function()
		if konModel and konModel.Parent then
			konModel:Destroy()
		end
	end)
end

-- Play a sound at a world position using an invisible anchored part.
local function playSoundAtPosition(soundName, position)
	local soundsFolder = getSoundsFolder()
	if not soundsFolder then return end

	local soundTemplate = soundsFolder:FindFirstChild(soundName)
	if not soundTemplate then return end

	local soundPart = Instance.new("Part")
	soundPart.Name = "SoundEmitter_" .. soundName
	soundPart.Size = Vector3.one
	soundPart.Position = position
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.CanQuery = false
	soundPart.Transparency = 1
	soundPart.Parent = getEffectsFolder()

	local sound = soundTemplate:Clone()
	sound.Parent = soundPart
	sound:Play()

	task.delay(10, function()
		if soundPart and soundPart.Parent then soundPart:Destroy() end
	end)
end

-- VFX helpers — call Clients/kon module directly (no VFXRep round-trip)
local function playKonSpawnVFX(konModel, pivotCF)
	local fx = getKonClientFX()
	if fx and fx.spawn then
		task.spawn(function()
			fx.spawn(nil, { Character = LocalPlayer.Character, Kon = konModel, Pivot = pivotCF })
		end)
	end
end

local function playKonBiteVFX(konModel, pivotCF)
	local fx = getKonClientFX()
	if fx and fx.bite then
		fx.bite(nil, { Character = LocalPlayer.Character, Kon = konModel, Pivot = pivotCF })
	end
	-- Bite sound is played at SPAWN time (not bite-delay), so no sound here.
end

local function playKonSmokeVFX(konModel, pivotCF)
	local fx = getKonClientFX()
	if fx and fx.smoke then
		fx.smoke(nil, { Character = LocalPlayer.Character, Kon = konModel, Pivot = pivotCF })
	end
	local pos = typeof(pivotCF) == "CFrame" and pivotCF.Position or pivotCF
	playSoundAtPosition("smoke", pos)
end

-- Lifecycle timing constants (match animation timings)
local KON_LIFECYCLE_TIMING = {
	BITE_DELAY   = 0.6,
	SMOKE_DELAY  = 1.9,
	KON_LIFETIME = 2.5,
	FADE_TIME    = 0.3,
}

-- Run the full Kon lifecycle: spawn → animation → bite VFX → smoke VFX → despawn.
-- Tracks the model in Aki._activeKons[originUserId] for cleanup.
local function runKonLifecycle(konModel, targetCFrame, originUserId)
	Aki._activeKons[originUserId] = konModel

	playKonSpawnVFX(konModel, targetCFrame)
	local pos = typeof(targetCFrame) == "CFrame" and targetCFrame.Position or targetCFrame
	playSoundAtPosition("bite", pos)

	-- Play Kon animation
	local konAnim = getKonAnimation()
	if konAnim then
		local animController = konModel:FindFirstChildOfClass("AnimationController")
			or konModel:FindFirstChildOfClass("Humanoid")
		if animController then
			local animator = animController:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = animController
			end
			local track = animator:LoadAnimation(konAnim)
			track:Play()
		end
	end

	-- BITE VFX at delay
	task.delay(KON_LIFECYCLE_TIMING.BITE_DELAY, function()
		if not konModel or not konModel.Parent then return end
		if Aki._activeKons[originUserId] ~= konModel then return end
		playKonBiteVFX(konModel, targetCFrame)
	end)

	-- SMOKE VFX at delay
	task.delay(KON_LIFECYCLE_TIMING.SMOKE_DELAY, function()
		if not konModel or not konModel.Parent then return end
		if Aki._activeKons[originUserId] ~= konModel then return end
		playKonSmokeVFX(konModel, targetCFrame)
	end)

	-- DESPAWN after lifetime
	task.delay(KON_LIFECYCLE_TIMING.KON_LIFETIME - KON_LIFECYCLE_TIMING.FADE_TIME, function()
		if Aki._activeKons[originUserId] == konModel then
			despawnKon(konModel, KON_LIFECYCLE_TIMING.FADE_TIME)
			Aki._activeKons[originUserId] = nil
		end
	end)
end

--[[
	prepareKonRig — pre-create a konny clone with all animation tracks loaded
	on its own Animator so there is zero delay when the ability fires.
	Stores result in Aki._preparedKon = { model, tracks = {start, throw, fly} }
	Call once during OnEquip and again after each ability cleanup.

	IMPORTANT: Clone + LoadAnimation are fully synchronous (no yield) so
	_preparedKon is available on the SAME FRAME.  ContentProvider:PreloadAsync
	runs afterwards in a background thread purely for CDN warmth.
]]
local function prepareKonRig()
	-- Destroy any leftover prepared clone
	if Aki._preparedKon then
		if Aki._preparedKon.model and Aki._preparedKon.model.Parent then
			Aki._preparedKon.model:Destroy()
		end
		Aki._preparedKon = nil
	end

	local template = getKonnyTemplate()
	if not template then return end

	-- Clone the rig and parent offscreen so Animator works (all sync, no yield)
	local konModel = template:Clone()
	konModel.Name = "KonPreloaded"
	konModel.Parent = getEffectsFolder()
	konModel:PivotTo(CFrame.new(0, -500, 0))

	local animController = konModel:FindFirstChildOfClass("AnimationController")
		or konModel:FindFirstChildOfClass("Humanoid")
	if not animController then
		konModel:Destroy()
		return
	end

	local animator = animController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animController
	end

	-- Load every track NOW (sync — LoadAnimation returns instantly)
	local ids = {
		start = KON_START_ANIM_ID,
		throw = KON_THROW_ANIM_ID,
		fly   = KON_FLY_ANIM_ID,
	}
	local tracks = {}
	local preloadList = {}
	for key, id in pairs(ids) do
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(id)
		table.insert(preloadList, anim)
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and track then
			track.Looped = (key == "fly")
			tracks[key] = track
		end
	end

	-- Rig + tracks ready IMMEDIATELY (no yield has happened yet)
	Aki._preparedKon = {
		model  = konModel,
		tracks = tracks,
	}

	-- Background: warm CDN cache so Play() has animation data ready.
	-- This yields but _preparedKon is already set, so the ability can fire.
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(preloadList)
		end)
		for _, a in ipairs(preloadList) do
			a:Destroy()
		end
	end)
end

-- Spawn Kon model and attach it to follow the camera during hold phase.
-- Uses the pre-prepared clone from prepareKonRig() when available (zero-delay).
local function spawnHeldKon(state)
	local konModel
	local konAnimTrack

	if Aki._preparedKon and Aki._preparedKon.model and Aki._preparedKon.model.Parent then
		-- Use the pre-loaded clone + cached tracks (instant)
		konModel = Aki._preparedKon.model
		konModel.Name = "KonHeld_" .. tostring(LocalPlayer.UserId)

		-- Play the already-loaded start track
		konAnimTrack = Aki._preparedKon.tracks.start
		if konAnimTrack then
			konAnimTrack.Looped = false
			konAnimTrack.TimePosition = 0
			konAnimTrack:Play()
		end

		-- Stash throw/fly tracks so the throw phase can reuse them
		state.konThrowTrack = Aki._preparedKon.tracks.throw
		state.konFlyTrack   = Aki._preparedKon.tracks.fly

		Aki._preparedKon = nil  -- consumed
	else
		-- Fallback: fresh clone (first frame may hitch)
		local template = getKonnyTemplate()
		if not template then return end
		konModel = template:Clone()
		konModel.Name = "KonHeld_" .. tostring(LocalPlayer.UserId)
		konModel.Parent = getEffectsFolder()
		konAnimTrack = playKonAnimById(konModel, KON_START_ANIM_ID, false)
	end

	-- Position initially at camera
	local cam = Workspace.CurrentCamera
	konModel:PivotTo(cam.CFrame * CFrame.new(0, -1.15, 0) * CFrame.Angles(0, math.pi, 0))

	state.heldKonAnimTrack = konAnimTrack

	-- Listen for the Kon animation's own "freeze" event to pause at its designated frame
	if konAnimTrack then
		konAnimTrack:GetMarkerReachedSignal("Event"):Connect(function(param)
			if param == "freeze" and state.active and not state.released then
				konAnimTrack:AdjustSpeed(0)
			end
		end)
	end

	-- Follow camera every frame using RenderStepped loop
	local followConn
	followConn = RunService.RenderStepped:Connect(function()
		if not konModel or not konModel.Parent then
			if followConn then followConn:Disconnect() end
			return
		end
		konModel:PivotTo(cam.CFrame * CFrame.new(0, -1.15, 0) * CFrame.Angles(0, math.pi, 0))
	end)

	state.heldKonModel = konModel
	state.heldKonFollowConn = followConn
end

-- Self-launch: uncrouch + upward launch (used by both projectile impact and trap trigger)
local function doSelfLaunch()
	local character = LocalPlayer.Character
	if not character then return end

	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
	if not root then return end

	-- Force uncrouch / unslide before launching
	LocalPlayer:SetAttribute("ForceUncrouch", true)
	LocalPlayer:SetAttribute("BlockCrouchWhileAbility", true)
	LocalPlayer:SetAttribute("BlockSlideWhileAbility", true)

	if MovementStateManager:IsSliding() or MovementStateManager:IsCrouching() then
		MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
	end

	task.delay(1.5, function()
		if LocalPlayer and LocalPlayer.Parent then
			LocalPlayer:SetAttribute("ForceUncrouch", nil)
			LocalPlayer:SetAttribute("BlockCrouchWhileAbility", nil)
			LocalPlayer:SetAttribute("BlockSlideWhileAbility", nil)
		end
	end)

	-- Launch straight up
	root.AssemblyLinearVelocity *= Vector3.new(1, 0, 1) -- Clear vertical velocity
	local movementController = ServiceRegistry:GetController("Movement")
		or ServiceRegistry:GetController("MovementController")
	if movementController and movementController.BeginExternalLaunch then
		movementController:BeginExternalLaunch(Vector3.new(0, SELF_LAUNCH_VERTICAL, 0), 0.28)
	else
		root.AssemblyLinearVelocity = Vector3.new(0, SELF_LAUNCH_VERTICAL, 0)
	end
	warn("[Aki] Self-launched! velocity:", SELF_LAUNCH_VERTICAL)
end

-- Forward declarations for mutually-referencing functions
local onProjectileImpact -- defined after launchKonProjectile

-- Check if a hit part is breakable (for wall piercing)
local function isBreakablePart(part)
	if not part then return false end
	if part:HasTag("Breakable") or part:HasTag("BreakablePiece") or part:HasTag("Debris") then
		return true
	end
	local ancestor = part:FindFirstAncestorOfClass("Model")
	if ancestor and (ancestor:HasTag("Breakable") or ancestor:HasTag("BreakablePiece")) then
		return true
	end
	return false
end

-- Launch Kon as a projectile with physics simulation
local function launchKonProjectile(state, abilityRequest, character, viewmodelRig, startPos, direction)
	warn("[Aki Proj] === LAUNCH ===")
	warn("[Aki Proj] startPos:", startPos, "| direction:", direction, "| speed:", PROJ_SPEED)

	-- Create the flying Kon model
	local template = getKonnyTemplate()
	if not template then
		warn("[Aki Proj] ERROR: konny template not found!")
		return
	end

	local flyingKon = template:Clone()
	flyingKon.Name = "KonProjectile_" .. tostring(LocalPlayer.UserId)
	flyingKon:ScaleTo(PROJ_KON_SCALE)
	flyingKon.Parent = getEffectsFolder()

	-- Position at start
	flyingKon:PivotTo(CFrame.lookAt(startPos, startPos + direction) * CFrame.Angles(0, math.pi, 0))

	-- Play flying/looping animation
	playKonAnimById(flyingKon, KON_FLY_ANIM_ID, true)

	state.projectileKon = flyingKon
	state.projectileActive = true
	Aki._projectileInFlight = true

	-- Broadcast projectile start to other clients
	VFXRep:Fire("Others", { Module = "Kon", Function = "fireProjectile" }, {
		startPosition = { X = startPos.X, Y = startPos.Y, Z = startPos.Z },
		direction = { X = direction.X, Y = direction.Y, Z = direction.Z },
		ownerId = LocalPlayer.UserId,
	})

	-- Create projectile physics
	local physics = ProjectilePhysics.new(PROJ_PHYSICS_CONFIG)
	local position = startPos
	local velocity = direction.Unit * PROJ_SPEED
	local distanceTraveled = 0

	-- Build raycast params (exclude characters, effects, camera, dummies)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { character }

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(filterList, player.Character)
		end
	end
	local dummiesFolder = Workspace:FindFirstChild("Dummies")
	if dummiesFolder then table.insert(filterList, dummiesFolder) end
	local effectsFolder = Workspace:FindFirstChild("Effects")
	if effectsFolder then table.insert(filterList, effectsFolder) end
	local voxelCache = Workspace:FindFirstChild("VoxelCache")
	if voxelCache then table.insert(filterList, voxelCache) end
	local destructionFolder = Workspace:FindFirstChild("__Destruction")
	if destructionFolder then table.insert(filterList, destructionFolder) end
	if Workspace.CurrentCamera then table.insert(filterList, Workspace.CurrentCamera) end

	rayParams.FilterDescendantsInstances = filterList

	-- Physics loop on Heartbeat (NOT stored in state.connections — must survive finishAbility)
	local exploded = false
	local lastReplicationTime = 0
	local lastDestroyTime = 0
	local projActive = true  -- independent flag so finishAbility can't kill us

	local projConn
	projConn = RunService.Heartbeat:Connect(function(dt)
		if not projActive or state.cancelled then
			projConn:Disconnect()
			return
		end

		-- Safety: if the flying Kon was destroyed externally, treat as impact at current position
		if not flyingKon or not flyingKon.Parent then
			warn("[Aki Proj] SAFETY: flyingKon destroyed externally at pos:", position)
			projConn:Disconnect()
			projActive = false
			Aki._projectileInFlight = false
			-- Still send impact so server can do damage/destruction
			onProjectileImpact(state, abilityRequest, position, velocity, flyingKon, nil)
			return
		end

		-- Check max range
		if distanceTraveled >= PROJ_MAX_RANGE then
			warn("[Aki Proj] Max range reached:", string.format("%.0f", distanceTraveled), "/", PROJ_MAX_RANGE)
			projConn:Disconnect()
			exploded = true
			projActive = false
			onProjectileImpact(state, abilityRequest, position, velocity, flyingKon, nil)
			return
		end

		-- Step physics
		local newPosition, newVelocity, hitResult = physics:Step(position, velocity, dt, rayParams)
		local moveDistance = (newPosition - position).Magnitude
		distanceTraveled += moveDistance

		if hitResult then
			-- Hit something — check if breakable
			if isBreakablePart(hitResult.Instance) then
				-- Pierce through breakable wall: add to filter, nudge forward
				warn("[Aki Proj] Pierced breakable:", hitResult.Instance:GetFullName())
				local filter = rayParams.FilterDescendantsInstances
				table.insert(filter, hitResult.Instance)
				rayParams.FilterDescendantsInstances = filter
				position = hitResult.Position + velocity.Unit * 0.5
			else
				-- Unbreakable wall / ground — impact here
				warn("[Aki Proj] Hit unbreakable:", hitResult.Instance:GetFullName(), "| dist:", string.format("%.0f", distanceTraveled))
				position = hitResult.Position
				projConn:Disconnect()
				exploded = true
				projActive = false
				onProjectileImpact(state, abilityRequest, position, velocity, flyingKon, hitResult)
				return
			end
		else
			position = newPosition
		end

		velocity = newVelocity

		-- Proximity check: detect if projectile passes near any character (close-range hits)
		-- The raycast ignores characters, so without this, close-range shots fly through targets.
		do
			local nearbyTargets = Hitbox.GetCharactersInSphere(position, PROJ_CHAR_HIT_RADIUS, {
				Exclude = LocalPlayer,
			})
			if #nearbyTargets > 0 then
				warn("[Aki Proj] Proximity hit! Targets:", #nearbyTargets, "at pos:", position)
				projConn:Disconnect()
				exploded = true
				projActive = false
				onProjectileImpact(state, abilityRequest, position, velocity, flyingKon, nil)
				return
			end
		end

		-- Self-proximity check: detect if projectile passes near Aki (for self-launch)
		-- Only after minimum travel distance to avoid instant self-hit at spawn
		if distanceTraveled > 8 then
			local myRoot = character.PrimaryPart
				or character:FindFirstChild("HumanoidRootPart")
				or character:FindFirstChild("Root")
			if myRoot then
				local distToSelf = (myRoot.Position - position).Magnitude
				if distToSelf <= PROJ_CHAR_HIT_RADIUS then
					warn("[Aki Proj] Self proximity hit! dist:", string.format("%.1f", distToSelf), "at pos:", position)
					projConn:Disconnect()
					exploded = true
					projActive = false
					onProjectileImpact(state, abilityRequest, position, velocity, flyingKon, nil)
					return
				end
			end
		end

		-- Update visual (face movement direction, flipped for model orientation)
		if flyingKon and flyingKon.Parent then
			if velocity.Magnitude > 0.1 then
				flyingKon:PivotTo(CFrame.lookAt(position, position + velocity.Unit) * CFrame.Angles(0, math.pi, 0))
			else
				flyingKon:PivotTo(CFrame.new(position) * flyingKon:GetPivot().Rotation)
			end
		end

		local now = os.clock()

		-- Send destruction along flight path on a loop
		if now - lastDestroyTime >= PROJ_DESTROY_INTERVAL then
			lastDestroyTime = now
			abilityRequest.Send({
				action = "konProjectileDestroy",
				position = { X = position.X, Y = position.Y, Z = position.Z },
				allowMultiple = true,
			})
		end

		-- Replicate position to server at intervals
		if now - lastReplicationTime >= PROJ_REPLICATION_INTERVAL then
			lastReplicationTime = now
			abilityRequest.Send({
				action = "konProjectileUpdate",
				position = { X = position.X, Y = position.Y, Z = position.Z },
				direction = { X = velocity.Unit.X, Y = velocity.Unit.Y, Z = velocity.Unit.Z },
				allowMultiple = true,
			})
		end
	end)

	-- NOTE: do NOT put projConn in state.connections — the projectile must fly
	-- independently even after finishAbility is called (which disconnects all state connections).
	-- The loop self-terminates on impact, max range, or state.cancelled.
end

-- Handle projectile impact (damage request to server, cleanup)
onProjectileImpact = function(state, abilityRequest, impactPos, velocity, flyingKon, hitResult)
	warn("[Aki Proj] === IMPACT ===")
	warn("[Aki Proj] impactPos:", impactPos, "| hitInstance:", hitResult and hitResult.Instance or "none")

	-- Signal Hit first so ReplicateProjectile's impact FX loop fires on the
	-- caster's own client, then defer the actual destroy one frame so the
	-- loop has time to read the attribute before the instance is gone.
	if flyingKon and flyingKon.Parent then
		flyingKon:SetAttribute("Hit", true)
		task.defer(function()
			if flyingKon and flyingKon.Parent then
				flyingKon:Destroy()
			end
		end)
	end
	state.projectileKon = nil
	state.projectileActive = false
	Aki._projectileInFlight = false

	-- Kill lingering arc preview immediately on impact
	if state._arcPreviewLinger and state._arcPreviewLinger.Parent then
		state._arcPreviewLinger:Destroy()
	end
	state._arcPreviewLinger = nil

	-- Broadcast impact to all clients (destroys spectator Kon, VFX at impact)
	VFXRep:Fire("All", { Module = "Kon", Function = "projectileImpact" }, {
		position = { X = impactPos.X, Y = impactPos.Y, Z = impactPos.Z },
		ownerId = LocalPlayer.UserId,
	})

	-- Check if Aki (self) is in impact radius for self-launch
	local selfInRange = false
	local myChar = LocalPlayer.Character
	if myChar then
		local root = myChar.PrimaryPart or myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Root")
		if root then
			local distToSelf = (root.Position - impactPos).Magnitude
			warn("[Aki Proj] Self-range check | rootPos:", root.Position, "| dist:", string.format("%.1f", distToSelf), "| radius:", PROJ_IMPACT_RADIUS, "| inRange:", distToSelf <= PROJ_IMPACT_RADIUS)
			if distToSelf <= PROJ_IMPACT_RADIUS then
				selfInRange = true
			end
		else
			warn("[Aki Proj] Self-range check: no root part found")
		end
	end

	-- CLIENT-SIDE self-launch (immediate, no server round-trip delay)
	if selfInRange then
		warn("[Aki Proj] Self-launch triggered on CLIENT")
		doSelfLaunch()
	end

	-- Find OTHER characters hit in impact radius
	warn("[Aki Proj] Searching for targets in sphere | pos:", impactPos, "| radius:", PROJ_IMPACT_RADIUS)
	local targets = Hitbox.GetCharactersInSphere(impactPos, PROJ_IMPACT_RADIUS, {
		Exclude = LocalPlayer,
	})
	warn("[Aki Proj] Targets found:", #targets)

	local hitList = {}
	local hitAnyPlayer = false
	for _, targetChar in ipairs(targets) do
					local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		if targetPlayer then hitAnyPlayer = true end
		warn("[Aki Proj] Hit target:", targetChar.Name, "| isPlayer:", targetPlayer ~= nil, "| isDummy:", targetPlayer == nil)
					table.insert(hitList, {
						characterName = targetChar.Name,
						playerId = targetPlayer and targetPlayer.UserId or nil,
						isDummy = targetPlayer == nil,
					})
				end

	if hitAnyPlayer then
		task.delay(0.1, playHitVoice)
	end

	warn("[Aki Proj] Sending konProjectileHit | selfInRange:", selfInRange, "| hits:", #hitList)

	-- Send impact data to server for authoritative damage + destruction + self-launch
	-- MUST include allowMultiple because konProjectile already started the cooldown
				abilityRequest.Send({
		action = "konProjectileHit",
		impactPosition = { X = impactPos.X, Y = impactPos.Y, Z = impactPos.Z },
					hits = hitList,
		selfInRange = selfInRange,
		allowMultiple = true,
	})
end

--------------------------------------------------------------------------------
-- Shared Ability Helpers
--------------------------------------------------------------------------------

-- Clean up ability state and restore weapon (used by both start and throw phases)
local function finishAbility(state, kitController)
	if not state or not state.active then return end
			
			state.active = false
			Aki._abilityState = nil

			-- Cleanup connections
			for _, conn in ipairs(state.connections) do
				if typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				end
			end
			stopHitboxPreview(state, 0)
	stopArcPreview(state, 0)
	-- Note: do NOT destroy _arcPreviewLinger here — it lingers intentionally for 1s after throw

	-- Cleanup held Kon
	if state.heldKonFollowConn then
		state.heldKonFollowConn:Disconnect()
		state.heldKonFollowConn = nil
	end
	if state.heldKonModel and state.heldKonModel.Parent then
		state.heldKonModel:Destroy()
	end
	state.heldKonModel = nil

	-- Note: do NOT destroy the projectile Kon — it flies independently.

			-- Restore weapon
	if state.unlock then state.unlock() end
	if kitController then kitController:_unholsterWeapon() end

	-- Pre-prepare a fresh Kon rig for the next ability use
	task.spawn(prepareKonRig)
end

-- Chain from start animation → throw animation → projectile launch
local function startThrowPhase(state, abilityRequest, character, viewmodelRig, viewmodelAnimator, kitController)
	state.throwPhaseStarted = true

	-- Keep Kon following the camera during throw — it stays locked until the
	-- "throw" event fires and the held Kon is destroyed (which auto-disconnects the loop).

	-- Resume Kon anim so the throw transition looks right
	if state.heldKonAnimTrack then
		state.heldKonAnimTrack:AdjustSpeed(1)
	end

	-- Play throw animation on viewmodel
	local throwTrack = viewmodelAnimator:PlayKitAnimation(VM_THROW_ANIM_NAME, {
		priority = Enum.AnimationPriority.Action4,
	})

	-- Play throw animation on held Kon model simultaneously
	if state.heldKonModel and state.heldKonModel.Parent then
		if state.konThrowTrack then
			-- Use pre-loaded track (instant, no LoadAnimation overhead)
			state.konThrowTrack.Looped = false
			state.konThrowTrack.TimePosition = 0
			state.konThrowTrack:Play()
		else
			playKonAnimById(state.heldKonModel, KON_THROW_ANIM_ID, false)
		end
	end

	if not throwTrack then
		-- Fallback: launch immediately if throw animation failed to play
		local cam = Workspace.CurrentCamera
		local lookDir = cam.CFrame.LookVector
		local downDot = math.abs(math.min(0, lookDir.Y))
		local adjustedOffset = 5 * (1 - downDot * 0.9)
		local startPos = cam.CFrame.Position + lookDir * adjustedOffset

		abilityRequest.Send({
			action = "konProjectile",
			startPosition = { X = startPos.X, Y = startPos.Y, Z = startPos.Z },
			direction = { X = lookDir.X, Y = lookDir.Y, Z = lookDir.Z },
			allowMultiple = true,
		})
		if state.heldKonFollowConn then
			state.heldKonFollowConn:Disconnect()
			state.heldKonFollowConn = nil
		end
		if state.heldKonModel and state.heldKonModel.Parent then
			state.heldKonModel:Destroy()
		end
		state.heldKonModel = nil
		launchKonProjectile(state, abilityRequest, character, viewmodelRig, startPos, lookDir)

		-- VFX: fire/throw burst + projectile soaring trail (fallback path)
		VFXRep:Fire("Me", { Module = "Kon", Function = "fxFire" }, {
			Character = character,
			ViewModel = viewmodelRig,
		})
		if state.projectileKon and state.projectileKon.Parent then
			VFXRep:Fire("Me", { Module = "Kon", Function = "fxProjectile" }, {
				Projectile = state.projectileKon,
			})
		end

		task.delay(0.5, function()
			finishAbility(state, kitController)
		end)
		return
	end

	state.throwTrack = throwTrack

	-- Throw animation events
	local throwConn = throwTrack:GetMarkerReachedSignal("Event"):Connect(function(event)
		if event == "throw" then
			if state.cancelled or not state.active then return end

			-- Capture camera NOW (not earlier) so the aim is fresh
			local cam = Workspace.CurrentCamera
			local lookDir = cam.CFrame.LookVector
			-- Smart offset: reduce when aiming steeply down to avoid spawning below floor
			local downDot = math.abs(math.min(0, lookDir.Y)) -- 0=horizontal, 1=straight down
			local adjustedOffset = 5 * (1 - downDot * 0.9)   -- ~0.5 when aiming straight down
			local startPos = cam.CFrame.Position + lookDir * adjustedOffset

			-- Notify server
			abilityRequest.Send({
				action = "konProjectile",
				startPosition = { X = startPos.X, Y = startPos.Y, Z = startPos.Z },
				direction = { X = lookDir.X, Y = lookDir.Y, Z = lookDir.Z },
				allowMultiple = true,
			})

			-- Stop following camera and destroy held Kon (replaced by projectile Kon)
			if state.heldKonFollowConn then
				state.heldKonFollowConn:Disconnect()
				state.heldKonFollowConn = nil
			end
			if state.heldKonModel and state.heldKonModel.Parent then
				state.heldKonModel:Destroy()
			end
			state.heldKonModel = nil

			-- Launch projectile
			launchKonProjectile(state, abilityRequest, character, viewmodelRig, startPos, lookDir)

			-- VFX: fire/throw burst on viewmodel + projectile soaring trail
			VFXRep:Fire("Me", { Module = "Kon", Function = "fxFire" }, {
				Character = character,
				ViewModel = viewmodelRig,
			})
			if state.projectileKon and state.projectileKon.Parent then
				VFXRep:Fire("Me", { Module = "Kon", Function = "fxProjectile" }, {
					Projectile = state.projectileKon,
				})
			end

		elseif event == "_finish" then
			finishAbility(state, kitController)
		end
	end)
	table.insert(state.connections, throwConn)

	-- Safety: if throw animation stops without hitting _finish event
	local stoppedConn = throwTrack.Stopped:Once(function()
		if state.active then
			finishAbility(state, kitController)
		end
	end)
	table.insert(state.connections, stoppedConn)
end

--------------------------------------------------------------------------------
-- Ability: Kon
--------------------------------------------------------------------------------

function Aki.Ability:OnStart(abilityRequest)
	Aki._holding = true

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
	if Aki._abilityState and Aki._abilityState.active then return end -- Already in ability (start/freeze/throw)
	if kitController:IsAbilityActive() then return end
	if Aki._projectileInFlight then return end -- Can't use ability while a Kon projectile is in flight
	if not isTrapVariant and abilityRequest.IsOnCooldown() then return end

	------------------------------------------------------------------------
	-- Start ability (both variants use the same animation/hold/release flow)
	------------------------------------------------------------------------
	local ctx = abilityRequest.StartAbility()
	local unlock = kitController:LockWeaponSwitch()

	-- Play viewmodel animation (legacy "Kon" for trap, new "Konstart" for main)
	local viewmodelAnimator = ctx.viewmodelAnimator
	local viewmodelController = abilityRequest.viewmodelController
	local viewmodelRig = viewmodelController and viewmodelController:GetActiveRig()
	
	local vmAnimName = isTrapVariant and VM_OLD_ANIM_NAME or VM_START_ANIM_NAME
	local animation = viewmodelAnimator:PlayKitAnimation(vmAnimName, {
		priority = Enum.AnimationPriority.Action4,
		stopOthers = true,
	})

	if not animation then
		unlock()
		kitController:_unholsterWeapon()
		return
	end

	-- Determine ability range based on variant
	local abilityRange = isTrapVariant and TRAP_MAX_RANGE or MAX_RANGE

	-- Build a partial state now so spawnHeldKon can run on THIS FRAME.
	-- The Kon model animation MUST start at the same instant as the VM animation
	-- or it will be visually out of sync (the model lags behind the viewmodel).
	
	local state = {
		active = true,
		released = false,
		cancelled = false,
		frozen = false,
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

	-- MAIN VARIANT: spawn Kon immediately — same frame as PlayKitAnimation so
	-- the Kon start animation is perfectly in sync with the VM animation.
	--if not isTrapVariant then
	--	spawnHeldKon(state)
	--end

	-- Connect marker signal right after Kon is up (still same frame, no yields).
	-- StartEvents is forward-declared and filled in below via closure.


	-- Play start sound + voice line — run in a thread so any yields
	-- (e.g. ContentProvider:PreloadAsync inside playAbilityVoice) cannot
	-- block the Kon spawn or marker connection.
	task.spawn(playStartSound, viewmodelRig)
	task.spawn(playAbilityVoice, viewmodelRig)

	-- ====================================================================
	-- Start Animation Events (effectsplace → effectcharge → effectspawn → freeze → _finish)
	-- ====================================================================
	local StartEvents = {
		["effectsplace"] = function()
			if state.isTrapPlacement then return end
			-- VFX: wind aura + spawn flash/highlight on Kon
			VFXRep:Fire("Me", { Module = "Kon", Function = "fxWind" }, {
				Character = character,
				ViewModel = viewmodelRig,
				Kon = state.heldKonModel,
			})
			VFXRep:Fire("Me", { Module = "Kon", Function = "fxSpawn" }, {
				Character = character,
				ViewModel = viewmodelRig,
				Kon = state.heldKonModel,
			})
		end,

		["effectcharge"] = function()
			if state.isTrapPlacement then return end
			-- VFX: flipbook charge on both arms
			VFXRep:Fire("Me", { Module = "Kon", Function = "fxCharge" }, {
				Character = character,
				ViewModel = viewmodelRig,
				Part = "Right Arm",
			})
			VFXRep:Fire("Me", { Module = "Kon", Function = "fxCharge" }, {
				Character = character,
				ViewModel = viewmodelRig,
				Part = "Left Arm",
			})
		end,

		["effectspawn"] = function()
			if state.isTrapPlacement then return end
			-- VFX: FOV punch, CamShake, viewport mesh fx, white highlight on Kon
			VFXRep:Fire("Me", { Module = "Kon", Function = "fxKon" }, {
				Character = character,
				ViewModel = viewmodelRig,
				Kon = state.heldKonModel,
			})
		end,

		["freeze"] = function()
			if not Aki._holding then
				-- Quick tap — player already let go, just let the animation
				-- keep playing at normal speed. _finish will fire naturally.
	state.released = true
				return
			end

			-- Still holding: pause viewmodel animation until released
			if state.active then
				state.frozen = true
				animation:AdjustSpeed(0)
				replicateTrackSpeed(vmAnimName, 0)
				if state.isTrapPlacement then
					startHitboxPreview(state)
				else
					startArcPreview(state)
				end

				-- Poll for release, then resume animation
				task.spawn(function()
					while Aki._holding and state.active and not state.cancelled do
						task.wait()
					end
					if not state.active or state.cancelled then return end

					state.released = true

					if state.isTrapPlacement then
	stopHitboxPreview(state, HITBOX_PREVIEW_FADE_TIME)
					else
						stopArcPreview(state, HITBOX_PREVIEW_FADE_TIME)
					end

					local aName = state.isTrapPlacement and VM_OLD_ANIM_NAME or VM_START_ANIM_NAME
	if state.animation and state.animation.IsPlaying then
		state.animation:AdjustSpeed(RELEASE_ANIM_SPEED)
						replicateTrackSpeed(aName, RELEASE_ANIM_SPEED)
					end
					if state.heldKonAnimTrack then
						state.heldKonAnimTrack:AdjustSpeed(1)
					end
				end)
			end
		end,

		["_finish"] = function()
			if not state.active or state.cancelled then return end

			-- Stop preview
			if state.isTrapPlacement then
				stopHitboxPreview(state, 0)
			else
				-- Main variant: stop the live update, keep hitbox for 1s
				-- (projectile impact will destroy it early via state._arcPreviewLinger)
				if state.arcPreviewConn then
					state.arcPreviewConn:Disconnect()
					state.arcPreviewConn = nil
				end

				-- Move hitbox preview off of state so stopArcPreview won't grab it
				local lingerPreview = state.hitboxPreview
				state.hitboxPreview = nil
				if lingerPreview and lingerPreview.Parent then
					state._arcPreviewLinger = lingerPreview
					task.delay(1.0, function()
						-- Auto-cleanup after 1 second if not already destroyed
						if lingerPreview and lingerPreview.Parent then
							lingerPreview:Destroy()
						end
						if state._arcPreviewLinger == lingerPreview then
							state._arcPreviewLinger = nil
						end
					end)
				end
			end

			if state.isTrapPlacement then
				----------------------------------------------------------------
				-- TRAP VARIANT: Place trap at aimed position
				-- Server handles ALL detection (enemies + Aki self-launch)
				----------------------------------------------------------------
				if viewmodelController:GetActiveSlot() ~= "Fists" then
					finishAbility(state, kitController)
					return
				end

				local targetCFrame = state.previewTargetCFrame
				local surfaceNormal = state.previewSurfaceNormal
				if not targetCFrame then
					targetCFrame, surfaceNormal = getTargetLocation(character, abilityRange)
				end
				if not targetCFrame then
					finishAbility(state, kitController)
					return
				end

				surfaceNormal = surfaceNormal or Vector3.yAxis
				state.targetCFrame = targetCFrame
				local pos = targetCFrame.Position

				-- Send to server for validation + detection
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

				-- Mark as used (one per kit equip)
				Aki._trapPlaced = true

				-- Done — clean up
				finishAbility(state, kitController)

			else
				----------------------------------------------------------------
				-- MAIN VARIANT: Chain to throw animation
				-- startThrowPhase plays the throw anim → on "throw" event
				-- the projectile is actually launched.
				----------------------------------------------------------------
				startThrowPhase(state, abilityRequest, character, viewmodelRig, viewmodelAnimator, kitController)
			end
		end,
	}
	
	if not isTrapVariant then
		spawnHeldKon(state)
	end

	
	local markerConn = animation:GetMarkerReachedSignal("Event"):Connect(function(event)
		if StartEvents and StartEvents[event] then
			StartEvents[event]()
		end
	end)
	table.insert(state.connections, markerConn)
	
	-- Safety: if start animation stops without hitting _finish
	state.connections[#state.connections + 1] = animation.Stopped:Once(function()
		if state.active and not state.throwPhaseStarted then
			finishAbility(state, kitController)
		end
	end)

	state.connections[#state.connections + 1] = animation.Ended:Once(function()
		if state.active and not state.throwPhaseStarted then
			finishAbility(state, kitController)
		end
	end)
end

function Aki.Ability:OnEnded(abilityRequest)
	Aki._holding = false
end

function Aki.Ability:OnInterrupt(abilityRequest, reason)
	local state = Aki._abilityState
	if not state or not state.active then return end

	state.cancelled = true
	state.active = false
	state.projectileActive = false
	Aki._projectileInFlight = false
	Aki._abilityState = nil

	-- Cleanup active sounds
	cleanupSounds()

	-- Stop animations
	if state.animation and state.animation.IsPlaying then
		state.animation:Stop(0.1)
	end
	if state.throwTrack and state.throwTrack.IsPlaying then
		state.throwTrack:Stop(0.1)
	end

	stopHitboxPreview(state, HITBOX_PREVIEW_FADE_TIME)
	stopArcPreview(state, HITBOX_PREVIEW_FADE_TIME)

	-- Destroy lingering arc preview on interrupt
	if state._arcPreviewLinger and state._arcPreviewLinger.Parent then
		state._arcPreviewLinger:Destroy()
	end
	state._arcPreviewLinger = nil

	-- Destroy held Kon model
	if state.heldKonFollowConn then
		state.heldKonFollowConn:Disconnect()
		state.heldKonFollowConn = nil
	end
	if state.heldKonModel and state.heldKonModel.Parent then
		state.heldKonModel:Destroy()
	end
	state.heldKonModel = nil

	-- Destroy flying projectile Kon
	if state.projectileKon and state.projectileKon.Parent then
		state.projectileKon:Destroy()
	end
	state.projectileKon = nil

	-- Destroy any remaining Kon (legacy cleanup)
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

	-- Pre-prepare a fresh Kon rig for the next ability use
	task.spawn(prepareKonRig)
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

	-- Clean up any leftover trap visual from a previous equip cycle
	-- (server OnEquipped also broadcasts destroyTrap, this is belt-and-suspenders)
	if Aki._trapPlaced then
		VFXRep:Fire("Me", { Module = "Kon", Function = "destroyTrap" }, {})
		VFXRep:Fire("Others", { Module = "Kon", Function = "destroyTrap" }, {})
	end

	-- Reset state on re-equip
	Aki._trapPlaced = false
	Aki._projectileInFlight = false

	-- Listen for server-triggered self-launch (trap variant + projectile validation)
	-- The Kon rep module sets _KonSelfLaunchTick via attribute when the server
	-- broadcasts selfLaunch; actual movement logic stays here in the kit.
	self._connections.selfLaunchConn = LocalPlayer:GetAttributeChangedSignal("_KonSelfLaunchTick"):Connect(function()
		doSelfLaunch()
	end)

	-- Pre-create Kon rig with loaded animations so first ability use is instant
	task.spawn(prepareKonRig)
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

	-- Destroy trap visual (Placed model) on all clients if it exists
	if Aki._trapPlaced then
		VFXRep:Fire("Me", { Module = "Kon", Function = "destroyTrap" }, {})
		VFXRep:Fire("Others", { Module = "Kon", Function = "destroyTrap" }, {})
	end

	-- Destroy pre-prepared Kon rig (if still unused)
	if Aki._preparedKon then
		if Aki._preparedKon.model and Aki._preparedKon.model.Parent then
			Aki._preparedKon.model:Destroy()
		end
		Aki._preparedKon = nil
	end

	-- Clean up active Kon lifecycle models
	for userId, konModel in pairs(Aki._activeKons) do
		if konModel and typeof(konModel) == "Instance" and konModel.Parent then
			konModel:Destroy()
		end
	end
	Aki._activeKons = {}

	-- Reset state
	Aki._trapPlaced = false
	Aki._projectileInFlight = false
end

function Aki:Destroy()
	self:OnUnequip("Destroy")
end

--------------------------------------------------------------------------------
-- Exports — Kon model functions accessible by the rep mod via lazy require
--------------------------------------------------------------------------------
Aki.buildSurfaceCFrame = buildSurfaceCFrame
Aki.spawnKonModel      = spawnKonModel
Aki.playKonAnimById    = playKonAnimById
Aki.despawnKon         = despawnKon
Aki.runKonLifecycle    = runKonLifecycle
Aki.playSoundAtPosition = playSoundAtPosition
Aki.getEffectsFolder   = getEffectsFolder
Aki.getKonnyTemplate   = getKonnyTemplate
Aki.getKonTemplate     = getKonTemplate
Aki.getKonAnimation    = getKonAnimation

return Aki
