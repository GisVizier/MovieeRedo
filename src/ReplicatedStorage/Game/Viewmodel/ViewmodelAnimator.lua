local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

local ViewmodelAnimator = {}
ViewmodelAnimator.__index = ViewmodelAnimator

local DEBUG_VIEWMODEL = false

-- Kit animation storage (shared across all instances)
local PreloadedKitAnimations = {} -- { [animName] = Animation }
local KitAnimationsPreloaded = false

local AIRBORNE_SPRINT_SPEED = 0.2

local LocalPlayer = Players.LocalPlayer

local function replicateKitTrackAction(animIdOrName: string, isActive: boolean)
	local replicationController = ServiceRegistry:GetController("Replication")
	if not replicationController or type(replicationController.ReplicateViewmodelAction) ~= "function" then
		return
	end

	replicationController:ReplicateViewmodelAction("Fists", "PlayWeaponTrack", animIdOrName, isActive == true)
end

local function expAlpha(dt: number, k: number): number
	if dt <= 0 then
		return 0
	end
	return 1 - math.exp(-k * dt)
end

local function getRootPart(): BasePart?
	local character = LocalPlayer and LocalPlayer.Character
	if not character then
		return nil
	end
	return character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
end

local function isValidAnimId(animId: any): boolean
	return type(animId) == "string" and animId ~= "" and animId ~= "rbxassetid://0"
end

local function getAnimationInstance(weaponId: string, animName: string, skinId: string?): Animation?
	-- Try to load from Assets/Animations/ViewModel/{WeaponId}/{AnimName}
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	local animations = assets:FindFirstChild("Animations")
	if not animations then
		return nil
	end

	local viewModel = animations:FindFirstChild("ViewModel")
	if not viewModel then
		return nil
	end

	local weaponFolder = viewModel:FindFirstChild(weaponId)
	if not weaponFolder then
		return nil
	end

	-- Check skin-specific animations first
	if skinId then
		local skinFolder = weaponFolder:FindFirstChild(skinId)
		if skinFolder then
			local animInstance = skinFolder:FindFirstChild(animName)
			if animInstance and animInstance:IsA("Animation") then
				return animInstance
			end
		end
	end

	-- Fall back to default Viewmodel folder
	local viewmodelFolder = weaponFolder:FindFirstChild("Viewmodel")
	if not viewmodelFolder then
		return nil
	end

	local animInstance = viewmodelFolder:FindFirstChild(animName)
	if animInstance and animInstance:IsA("Animation") then
		return animInstance
	end

	return nil
end

local function resolveViewmodelAnimations(weaponId: string?, skinId: string?)
	local baseAnims = {}
	local skinAnims = {}

	-- Get base weapon animations
	local baseCfg = ViewmodelConfig.Weapons[weaponId or ""] or ViewmodelConfig.Weapons.Fists
	if baseCfg and baseCfg.Animations then
		for name, animRef in pairs(baseCfg.Animations) do
			baseAnims[name] = animRef
		end
	end

	-- Get skin-specific animation overrides
	if skinId and ViewmodelConfig.Skins then
		local weaponSkins = ViewmodelConfig.Skins[weaponId]
		if weaponSkins and weaponSkins[skinId] and weaponSkins[skinId].Animations then
			for name, animRef in pairs(weaponSkins[skinId].Animations) do
				skinAnims[name] = animRef
			end
		end
	end

	-- Merge: skin animations override base animations
	local merged = {}
	for name, animRef in pairs(baseAnims) do
		merged[name] = animRef
	end
	for name, animRef in pairs(skinAnims) do
		merged[name] = animRef
	end

	return merged
end

local function buildTracks(animator: Animator, weaponId: string?, skinId: string?)
	local tracks = {}
	local trackSettings = {}
	local anims = resolveViewmodelAnimations(weaponId, skinId)

	for name, animRef in pairs(anims) do
		local animInstance = nil

		-- Try to load as Animation instance first (check skin folder, then base)
		if type(animRef) == "string" and not string.find(animRef, "rbxassetid://") then
			animInstance = getAnimationInstance(weaponId, animRef, skinId)
			if animInstance then
				
			else
		
			end
		end

		-- Fall back to asset ID if no instance found
		if not animInstance and isValidAnimId(animRef) then
			animInstance = Instance.new("Animation")
			animInstance.AnimationId = animRef
		end

		if animInstance then
			local animId = animInstance.AnimationId
			if
				type(animId) ~= "string"
				or animId == ""
				or animId == "rbxassetid://0"
				or not string.find(animId, "^rbxassetid://")
			then
				animInstance = nil
			end
		end

		if animInstance then
			local track = animator:LoadAnimation(animInstance)
			
			-- Priority: check attribute (string or EnumItem), fall back to Action
			local priorityAttr = animInstance:GetAttribute("Priority")
			if type(priorityAttr) == "string" and Enum.AnimationPriority[priorityAttr] then
				track.Priority = Enum.AnimationPriority[priorityAttr]
			elseif type(priorityAttr) == "userdata" then
				track.Priority = priorityAttr
			else
				track.Priority = Enum.AnimationPriority.Action
			end
			if name == "ZiplineHold" or name == "ZiplineHookUp" or name == "ZiplineFastHookUp" then
				track.Priority = Enum.AnimationPriority.Action4
			end
			
			-- Loop: check attribute, fall back to based on animation type
			local loopAttr = animInstance:GetAttribute("Loop")
			if type(loopAttr) == "boolean" then
				track.Looped = loopAttr
			else
				track.Looped = (name == "Idle" or name == "Walk" or name == "Run" or name == "ADS" or name == "ZiplineHold")
			end

			-- Build settings from attributes (matching base animation structure)
			local settings = {}
			
			local fadeInAttr = animInstance:GetAttribute("FadeInTime")
			if type(fadeInAttr) == "number" then
				settings.FadeInTime = fadeInAttr
			end
			
			local fadeOutAttr = animInstance:GetAttribute("FadeOutTime")
			if type(fadeOutAttr) == "number" then
				settings.FadeOutTime = fadeOutAttr
			end
			
			local weightAttr = animInstance:GetAttribute("Weight")
			if type(weightAttr) == "number" then
				settings.Weight = weightAttr
			end
			
			local speedAttr = animInstance:GetAttribute("Speed")
			if type(speedAttr) == "number" then
				settings.Speed = speedAttr
			end
			
			trackSettings[name] = settings
			tracks[name] = track
		end
	end

	return tracks, trackSettings
end

function ViewmodelAnimator.new()
	local self = setmetatable({}, ViewmodelAnimator)
	self._rig = nil
	self._tracks = {}
	self._trackSettings = {}
	self._currentMove = nil
	self._conn = nil
	self._initialized = false
	self._smoothedSpeed = 0
	
	-- Kit animation tracks (loaded per-instance since they need an animator)
	self._kitTracks = {} -- { [animName] = AnimationTrack }
	self._kitTrackReplicateStopTokens = {}
	self._kitTrackReplicateStopConnections = {}
	
	return self
end

--[[
	Preloads all kit animations from Assets.Animations.ViewModel.Kits
	Structure: Assets/Animations/ViewModel/Kits/{KitName}/{AnimName}
	
	Uses GetDescendants() to find all Animation instances in subfolders.
	Stores by both full path and just animation name for flexible lookup.
	
	Call this once at startup - animations are shared across all instances.
]]
function ViewmodelAnimator.PreloadKitAnimations()
	if KitAnimationsPreloaded then
		return PreloadedKitAnimations
	end
	
	-- StreamingEnabled-safe: wait briefly for Assets/Animations to exist.
	local assets = ReplicatedStorage:FindFirstChild("Assets") or ReplicatedStorage:WaitForChild("Assets", 10)
	if not assets then
	
		return PreloadedKitAnimations
	end
	
	local animations = assets:FindFirstChild("Animations") or assets:WaitForChild("Animations", 10)
	if not animations then
		return PreloadedKitAnimations
	end
	
	local viewModel = animations:FindFirstChild("ViewModel") or animations:WaitForChild("ViewModel", 10)
	if not viewModel then
		return PreloadedKitAnimations
	end
	
	local kitsFolder = viewModel:FindFirstChild("Kits")
	if not kitsFolder then
		return PreloadedKitAnimations
	end
	
	-- Use GetDescendants to find all Animation instances
	local count = 0
	for _, descendant in ipairs(kitsFolder:GetDescendants()) do
		if descendant:IsA("Animation") then
			-- Build path relative to Kits folder (e.g., "Airborne/CloudskipDash")
			local pathParts = {}
			local current = descendant
			while current and current ~= kitsFolder do
				table.insert(pathParts, 1, current.Name)
				current = current.Parent
			end
			local fullPath = table.concat(pathParts, "/")
			
			-- Store by full path (e.g., "Airborne/CloudskipDash")
			PreloadedKitAnimations[fullPath] = descendant
			
			-- Also store by just the animation name (e.g., "CloudskipDash")
			-- This allows simpler lookups but may overwrite if names aren't unique
			PreloadedKitAnimations[descendant.Name] = descendant
			
			count += 1
			
		end
	end
	
	KitAnimationsPreloaded = true
	return PreloadedKitAnimations
end

--[[
	Gets a preloaded kit animation by name or rbxassetid
	@param animIdOrName: Animation name (e.g. "Updraft", "Airborne/Updraft") or rbxassetid
	@return Animation? The Animation instance if found
]]
function ViewmodelAnimator.GetKitAnimation(animIdOrName: string): Animation?
	if not animIdOrName or animIdOrName == "" then
		return nil
	end
	
	-- If it's an asset ID, create a new Animation instance
	if string.find(animIdOrName, "rbxassetid://") then
		local anim = Instance.new("Animation")
		anim.AnimationId = animIdOrName
		return anim
	end
	
	-- Look up in preloaded animations
	return PreloadedKitAnimations[animIdOrName]
end

function ViewmodelAnimator:BindRig(rig, weaponId: string?, skinId: string?)
	self:Unbind()

	self._rig = rig
	self._tracks = {}
	self._currentMove = nil
	self._initialized = false
	self._smoothedSpeed = 0
	self._weaponId = weaponId
	self._skinId = skinId or (rig and rig._skinId) -- Use rig's stored skinId as fallback
	
	-- Store original Motor6D transforms (bind pose) for reset
	self._bindPose = {}
	local model = rig and rig.Model
	if model then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("Motor6D") then
				self._bindPose[desc] = {
					C0 = desc.C0,
					C1 = desc.C1,
				}
			end
		end
	end

	if not rig or not rig.Animator then
		return
	end

	if rig._preloadedTracks and next(rig._preloadedTracks) ~= nil then
		self._tracks = rig._preloadedTracks
		self._trackSettings = rig._preloadedSettings or {}
	else
		self._tracks, self._trackSettings = buildTracks(rig.Animator, weaponId, self._skinId)
	end

	-- Pre-load all movement animations by playing and immediately stopping them
	-- This "primes" the animation system so they're ready when needed
	for name, track in pairs(self._tracks) do
		if name == "Walk" or name == "Run" then
			track:Play(0)
			track:Stop(0)
		end
	end

	-- Start with idle
	self:Play("Idle", 0.15, true)
	self._currentMove = "Idle"

	-- Mark as initialized immediately so movement updates (Idle/Walk/Run) run right away.
	-- The previous 0.1s delay caused animations to not play on join/respawn until re-equip.
	self._initialized = true

	-- Start the movement update loop immediately
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_updateMovement(dt)
	end)
end

function ViewmodelAnimator:PreloadRig(rig, weaponId: string?, skinId: string?)
	if not rig or not rig.Animator then
		return
	end

	-- Store skinId on rig for later use in BindRig
	rig._skinId = skinId

	local tracks, trackSettings = buildTracks(rig.Animator, weaponId, skinId)
	rig._preloadedTracks = tracks
	rig._preloadedSettings = trackSettings

	-- Pre-load all tracks by briefly playing them.
	for name, track in pairs(tracks) do
		track:Play(0)
		track:Stop(0)
	end
end

function ViewmodelAnimator:Unbind()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end

	for _, track in pairs(self._tracks) do
		pcall(function()
			if track.IsPlaying then
				track:Stop(0)
			end
		end)
	end
	
	-- Stop and clear kit animation tracks
	for _, track in pairs(self._kitTracks) do
		pcall(function()
			if track.IsPlaying then
				track:Stop(0)
			end
		end)
	end
	self._kitTracks = {}
	self:_clearKitReplicatedStopWatch()
	self._bindPose = nil

	self._rig = nil
	self._tracks = {}
	self._currentMove = nil
	self._initialized = false
end

function ViewmodelAnimator:_clearKitReplicatedStopWatch(animKey: string?)
	local connectionMap = self._kitTrackReplicateStopConnections
	if type(connectionMap) ~= "table" then
		self._kitTrackReplicateStopConnections = {}
		return
	end

	if animKey == nil then
		for key, connections in pairs(connectionMap) do
			if type(connections) == "table" then
				for _, connection in ipairs(connections) do
					if typeof(connection) == "RBXScriptConnection" then
						connection:Disconnect()
					end
				end
			end
			connectionMap[key] = nil
		end
		self._kitTrackReplicateStopTokens = {}
		return
	end

	local connections = connectionMap[animKey]
	if type(connections) == "table" then
		for _, connection in ipairs(connections) do
			if typeof(connection) == "RBXScriptConnection" then
				connection:Disconnect()
			end
		end
	end
	connectionMap[animKey] = nil
end

function ViewmodelAnimator:_watchKitReplicatedStop(animIdOrName: string, track: AnimationTrack)
	if type(animIdOrName) ~= "string" or animIdOrName == "" then
		return
	end
	if type(track) ~= "userdata" then
		return
	end

	local key = tostring(animIdOrName)
	local tokenMap = self._kitTrackReplicateStopTokens
	if type(tokenMap) ~= "table" then
		tokenMap = {}
		self._kitTrackReplicateStopTokens = tokenMap
	end

	local token = (tokenMap[key] or 0) + 1
	tokenMap[key] = token
	self:_clearKitReplicatedStopWatch(key)

	local emitted = false
	local function replicateStop()
		if emitted then
			return
		end
		if tokenMap[key] ~= token then
			return
		end
		emitted = true
		self:_clearKitReplicatedStopWatch(key)
		replicateKitTrackAction(animIdOrName, false)
	end

	self._kitTrackReplicateStopConnections[key] = {
		track.Stopped:Connect(replicateStop),
		track.Ended:Connect(replicateStop),
	}
end

function ViewmodelAnimator:Play(name: string, fadeTime: number?, restart: boolean?)
	local track = self._tracks[name]
	if not track and (name == "ZiplineHold" or name == "ZiplineHookUp" or name == "ZiplineFastHookUp") and self._rig and self._rig.Animator then
		local fistsCfg = ViewmodelConfig.Weapons and ViewmodelConfig.Weapons.Fists
		local zipAnim = fistsCfg and fistsCfg.Animations and fistsCfg.Animations[name]
		if isValidAnimId(zipAnim) then
			local animation = Instance.new("Animation")
			animation.AnimationId = zipAnim
			local loaded = self._rig.Animator:LoadAnimation(animation)
			loaded.Priority = Enum.AnimationPriority.Action4
			loaded.Looped = name == "ZiplineHold"
			self._tracks[name] = loaded
			self._trackSettings[name] = self._trackSettings[name] or {}
			track = loaded
		end
	end
	if not track then
		return
	end

	if restart and track.IsPlaying then
		track:Stop(0)
	end

	if not track.IsPlaying then
		local settings = self._trackSettings and self._trackSettings[name] or {}

		-- Use provided fadeTime or fall back to attribute, then default
		local fade = fadeTime or settings.FadeInTime or 0.1
		local weight = settings.Weight or 1
		local speed = settings.Speed or 1

		-- Play with all parameters at once (matching base animation structure)
		track:Play(fade, weight, speed)
	end
end

function ViewmodelAnimator:Stop(name: string, fadeTime: number?)
	local track = self._tracks[name]
	if track and track.IsPlaying then
		local settings = self._trackSettings and self._trackSettings[name] or {}

		-- Use provided fadeTime or fall back to attribute, then default
		local fade = fadeTime or settings.FadeOutTime or 0.1
		track:Stop(fade)
	end
end

function ViewmodelAnimator:GetTrack(name: string)
	local track = self._tracks[name]
	if track then
		return track
	end

	if not self._rig or not self._rig.Animator then
		return nil
	end

	local animInstance = nil
	local anims = resolveViewmodelAnimations(self._weaponId, self._skinId)
	local animRef = anims and anims[name] or nil

	if type(animRef) == "string" and not string.find(animRef, "rbxassetid://") then
		animInstance = getAnimationInstance(self._weaponId, animRef, self._skinId)
	end

	if not animInstance and isValidAnimId(animRef) then
		local animation = Instance.new("Animation")
		animation.AnimationId = animRef
		animInstance = animation
	end

	-- Final fallback: try loading by the requested track name directly.
	if not animInstance and type(name) == "string" and name ~= "" then
		animInstance = getAnimationInstance(self._weaponId, name, self._skinId)
	end

	if not animInstance then
		return nil
	end

	local ok, loadedTrack = pcall(function()
		return self._rig.Animator:LoadAnimation(animInstance)
	end)
	if not ok or not loadedTrack then
		return nil
	end

	loadedTrack.Priority = Enum.AnimationPriority.Action
	loadedTrack.Looped = (name == "Idle" or name == "Walk" or name == "Run" or name == "ADS" or name == "ZiplineHold")

	self._tracks[name] = loadedTrack
	self._trackSettings[name] = self._trackSettings[name] or {}
	return loadedTrack
end

function ViewmodelAnimator:GetTrackSettings(name: string)
	return self._trackSettings and self._trackSettings[name] or {}
end

--[[
	Plays a kit animation on the viewmodel.
	
	@param animIdOrName: Animation name (e.g. "Updraft", "Airborne/Updraft") or rbxassetid
	@param settings: Optional settings table:
		- fadeTime: number (default 0.1)
		- speed: number (default 1)
		- priority: Enum.AnimationPriority (default Action4)
		- looped: boolean (default false)
		- weight: number (default 1)
		- stopOthers: boolean - if true, stops other kit animations first (default false)
	@return AnimationTrack? The playing track, or nil if failed
]]
function ViewmodelAnimator:PlayKitAnimation(animIdOrName: string, settings: {[string]: any}?): AnimationTrack?
	if not self._rig or not self._rig.Animator then
		return nil
	end
	
	settings = settings or {}
	
	-- Stop other kit animations if requested
	if settings.stopOthers then
		self:StopAllKitAnimations(settings.fadeTime or 0.1)
	end
	
	-- Check if we already have this track loaded
	local track = self._kitTracks[animIdOrName]
	local animInstance = nil
	
	if not track then
		-- Get the animation instance
		animInstance = ViewmodelAnimator.GetKitAnimation(animIdOrName)
		if not animInstance then
			return nil
		end
		
		-- Validate animation ID
		local animId = animInstance.AnimationId
		if not animId or animId == "" or animId == "rbxassetid://0" then
			return nil
		end
		
		-- Load the track
		local success, result = pcall(function()
			return self._rig.Animator:LoadAnimation(animInstance)
		end)
		
		if not success or not result then
			return nil
		end
		
		track = result
		self._kitTracks[animIdOrName] = track
	else
		-- Track exists, get the animation instance for attribute reading
		animInstance = ViewmodelAnimator.GetKitAnimation(animIdOrName)
	end
	
	-- Read settings from attributes (fallback to provided settings, then defaults)
	local fadeTime = settings.fadeTime
	local speed = settings.speed
	local priority = settings.priority
	local looped = settings.looped
	local weight = settings.weight
	
	-- Read from Animation instance attributes if not provided in settings
	if animInstance then
		if fadeTime == nil then
			local fadeAttr = animInstance:GetAttribute("FadeInTime") or animInstance:GetAttribute("FadeTime")
			if type(fadeAttr) == "number" then
				fadeTime = fadeAttr
			end
		end
		
		if speed == nil then
			local speedAttr = animInstance:GetAttribute("Speed")
			if type(speedAttr) == "number" then
				speed = speedAttr
			end
		end
		
		if priority == nil then
			local priorityAttr = animInstance:GetAttribute("Priority")
			if type(priorityAttr) == "string" and Enum.AnimationPriority[priorityAttr] then
				priority = Enum.AnimationPriority[priorityAttr]
			elseif typeof(priorityAttr) == "EnumItem" then
				priority = priorityAttr
			end
		end
		
		if looped == nil then
			local loopAttr = animInstance:GetAttribute("Loop") or animInstance:GetAttribute("Looped")
			if type(loopAttr) == "boolean" then
				looped = loopAttr
			end
		end
		
		if weight == nil then
			local weightAttr = animInstance:GetAttribute("Weight")
			if type(weightAttr) == "number" then
				weight = weightAttr
			end
		end
	end
	
	-- Apply final defaults
	fadeTime = fadeTime or 0.1
	speed = speed or 1
	priority = priority or Enum.AnimationPriority.Action4
	looped = looped or false
	weight = weight or 1
	
	track.Priority = priority
	track.Looped = looped
	
	-- Stop if playing and we want to restart
	if track.IsPlaying then
		track:Stop(0)
	end
	
	-- Play the track
	track:Play(fadeTime, weight, speed)
	replicateKitTrackAction(animIdOrName, true)
	self:_watchKitReplicatedStop(animIdOrName, track)
	
	if DEBUG_VIEWMODEL then
	end
	
	return track
end

--[[
	Stops a specific kit animation.
	
	@param animIdOrName: The animation name or ID that was used to play it
	@param fadeTime: Optional fade out time (default 0.1)
]]
function ViewmodelAnimator:StopKitAnimation(animIdOrName: string, fadeTime: number?)
	local track = self._kitTracks[animIdOrName]
	if track and track.IsPlaying then
		self:_clearKitReplicatedStopWatch(tostring(animIdOrName))
		track:Stop(fadeTime or 0.1)
		replicateKitTrackAction(animIdOrName, false)
	end
end

--[[
	Stops all currently playing kit animations.
	
	@param fadeTime: Optional fade out time (default 0.1)
]]
function ViewmodelAnimator:StopAllKitAnimations(fadeTime: number?)
	local fade = fadeTime or 0.1
	for name, track in pairs(self._kitTracks) do
		self:_clearKitReplicatedStopWatch(tostring(name))
		if track and track.IsPlaying then
			track:Stop(fade)
			replicateKitTrackAction(name, false)

		end
	end
end

--[[
	Gets a kit animation track if it's been loaded.
	
	@param animIdOrName: The animation name or ID
	@return AnimationTrack? The track if loaded
]]
function ViewmodelAnimator:GetKitTrack(animIdOrName: string): AnimationTrack?
	return self._kitTracks[animIdOrName]
end

--[[
	Checks if a kit animation is currently playing.
	
	@param animIdOrName: The animation name or ID
	@return boolean
]]
function ViewmodelAnimator:IsKitAnimationPlaying(animIdOrName: string): boolean
	local track = self._kitTracks[animIdOrName]
	return track ~= nil and track.IsPlaying
end

--[[
	Resets the viewmodel rig to its original bind pose.
	Call this after kit animations end to clear any residual pose.
	Useful for Fists viewmodel which has no Idle animation to blend back to.
]]
function ViewmodelAnimator:ResetToBindPose()
	if not self._rig or not self._bindPose then
		return
	end
	
	-- Stop all kit animations first
	self:StopAllKitAnimations(0)
	
	-- Reset all Motor6Ds to original transforms
	for motor, transforms in pairs(self._bindPose) do
		if motor and motor.Parent then
			motor.C0 = transforms.C0
			motor.C1 = transforms.C1
		end
	end
	
	if DEBUG_VIEWMODEL then
	end
end

function ViewmodelAnimator:_updateMovement(dt: number)
	if not self._rig or not self._initialized then
		return
	end

	local root = getRootPart()
	local vel = root and root.AssemblyLinearVelocity or Vector3.zero
	local horizontalVel = Vector3.new(vel.X, 0, vel.Z)
	local speed = horizontalVel.Magnitude
	dt = dt or (1 / 60)
	local smoothCfg = ViewmodelConfig.Effects and ViewmodelConfig.Effects.MovementSmoothing or {}
	local speedAlpha = math.clamp(expAlpha(dt, smoothCfg.SpeedSmoothness or 12), 0, 1)
	self._smoothedSpeed = self._smoothedSpeed + (speed - self._smoothedSpeed) * speedAlpha

	local grounded = MovementStateManager:GetIsGrounded()
	local state = MovementStateManager:GetCurrentState()

	local target = "Idle"
	local moveStart = smoothCfg.MoveStartSpeed or 1.25
	local moveStop = smoothCfg.MoveStopSpeed or 0.75
	local isMoving = self._smoothedSpeed > moveStart or (self._currentMove ~= "Idle" and self._smoothedSpeed > moveStop)

	if isMoving then
		if state == MovementStateManager.States.Sprinting and self._tracks.Run then
			-- Keep sprint animation even while airborne.
			target = "Run"
		elseif grounded then
			target = "Walk"
		end
	end
	if not self._tracks[target] then
		target = "Idle"
	end

	-- Determine if player is moving backwards (velocity opposite to look direction)
	local isMovingBackward = false
	if speed > 0.5 then
		local camera = workspace.CurrentCamera
		if camera then
			local lookDir = camera.CFrame.LookVector
			local horizontalLook = Vector3.new(lookDir.X, 0, lookDir.Z)
			if horizontalLook.Magnitude > 0.01 then
				horizontalLook = horizontalLook.Unit
				local velDir = horizontalVel.Unit
				local dot = horizontalLook:Dot(velDir)
				-- Moving backward if dot product is negative (velocity opposite to look)
				isMovingBackward = dot < -0.3
			end
		end
	end

	-- Smooth crossfade between idle/walk/run.
	-- Let priority handle layering with action animations - don't suppress movement weights
	local fade = 0.18
	for _, name in ipairs({ "Idle", "Walk", "Run" }) do
		local track = self._tracks[name]
		if track then
			if not track.IsPlaying then
				track:Play(0)
			end
			local weight = (name == target) and 1 or 0
			track:AdjustWeight(weight, fade)
		end
	end

	-- Adjust walk animation speed/direction
	local walkTrack = self._tracks.Walk
	if walkTrack then
		if target == "Walk" then
			-- Reverse animation when walking backwards
			local walkSpeed = isMovingBackward and -1 or 1
			walkTrack:AdjustSpeed(walkSpeed)
		else
			walkTrack:AdjustSpeed(1)
		end
	end

	-- Adjust run animation speed/direction
	local runTrack = self._tracks.Run
	if runTrack then
		if target == "Run" then
			local baseSpeed = (not grounded) and AIRBORNE_SPRINT_SPEED or 1
			-- Reverse animation when running backwards
			local runSpeed = isMovingBackward and -baseSpeed or baseSpeed
			runTrack:AdjustSpeed(runSpeed)
		else
			runTrack:AdjustSpeed(1)
		end
	end
	self._currentMove = target
end

return ViewmodelAnimator
