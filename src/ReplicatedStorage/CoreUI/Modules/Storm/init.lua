--[[
	Storm CoreUI Module
	
	Client-side UI module for the storm system.
	Shows warning overlay when player is in the storm zone,
	plays ambient sounds, and handles enter/leave sound effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TweenConfig = require(script.TweenConfig)

local module = {}
module.__index = module

local currentTweens = {}

-- Continuous storm mesh shrink settings
local STORM_MIN_SHRINK_DURATION = 0.05
local STORM_RADIUS_RECONCILE_SPEED = 8

-- Cloud settings for storm atmosphere (client-side only)
local STORM_CLOUD_START_COVER = 0.669
local STORM_CLOUD_START_DENSITY = 0.63
local STORM_CLOUD_COLOR = Color3.fromRGB(122, 15, 255)
local STORM_CLOUD_FINAL_COVER = 1

-- Storm mesh settings
local STORM_Y_OFFSET = -200 -- Offset mesh downward
local STORM_MESH_TRANSPARENCY = 0.3
local STORM_FADE_IN_TIME = 2

local function cancelTweens(key)
	if currentTweens[key] then
		for _, tween in currentTweens[key] do
			pcall(function() tween:Cancel() end)
		end
		currentTweens[key] = nil
	end
end

function module.start(export, ui)
	local self = setmetatable({}, module)
	
	self._export = export
	self._ui = ui
	self._connections = export.connections
	self._tween = export.tween
	self._initialized = false
	self._isInStorm = false
	self._isVisible = false
	
	-- Cache sound references (sounds are expected to be in the UI or sounds folder)
	self._sounds = {}
	self:_cacheSounds()
	
	-- Cache UI elements
	self._elements = {}
	self:_cacheElements()
	
	return self
end

function module:_cacheSounds()
	-- Look for sounds in the UI itself
	local soundsFolder = self._ui:FindFirstChild("sounds") or self._ui:FindFirstChild("Sounds")
	if soundsFolder then
		self._sounds.ambience = soundsFolder:FindFirstChild("stormambience")
		self._sounds.enter = soundsFolder:FindFirstChild("stormenter")
		self._sounds.forming = soundsFolder:FindFirstChild("stormforming")
		self._sounds.leave = soundsFolder:FindFirstChild("stormleave")
	else
		-- Try to find sounds as direct children
		for _, child in self._ui:GetDescendants() do
			if child:IsA("Sound") then
				local name = child.Name:lower()
				if name:find("ambience") or name:find("ambient") then
					self._sounds.ambience = child
				elseif name:find("enter") then
					self._sounds.enter = child
				elseif name:find("forming") or name:find("start") then
					self._sounds.forming = child
				elseif name:find("leave") or name:find("exit") then
					self._sounds.leave = child
				end
			end
		end
	end
	
	-- Setup ambience as looped and store original volume
	if self._sounds.ambience then
		self._sounds.ambience.Looped = true
		self._originalAmbienceVolume = self._sounds.ambience.Volume
	end
end

function module:_cacheElements()
	-- Cache any UI elements we need to animate
	-- The Storm UI structure may vary, but we handle common patterns
	
	-- Look for main frame/canvas group
	self._elements.mainFrame = self._ui:FindFirstChildWhichIsA("Frame") 
		or self._ui:FindFirstChildWhichIsA("CanvasGroup")
	
	-- Look for warning text
	for _, desc in self._ui:GetDescendants() do
		if desc:IsA("TextLabel") then
			if desc.Name:lower():find("warning") or desc.Text:lower():find("storm") then
				self._elements.warningText = desc
				break
			end
		end
	end
	
	-- Look for damage indicator/vignette
	for _, desc in self._ui:GetDescendants() do
		if desc:IsA("ImageLabel") or desc:IsA("Frame") then
			if desc.Name:lower():find("vignette") or desc.Name:lower():find("damage") or desc.Name:lower():find("overlay") then
				self._elements.vignette = desc
				break
			end
		end
	end
end

function module:_init()
	if self._initialized then
		return
	end
	self._initialized = true
end

function module:show()
	if self._isVisible then return true end
	self._isVisible = true
	self._isInStorm = true
	
	self:_init()
	
	-- Make UI visible
	self._ui.Visible = true
	
	-- Setup initial state - fully transparent
	if self._ui:IsA("CanvasGroup") then
		self._ui.GroupTransparency = 1
	end
	
	-- Cancel any ongoing hide tweens
	cancelTweens("main")
	cancelTweens("ambience_fade")
	
	-- Play enter sound
	if self._sounds.enter then
		self._sounds.enter:Play()
	end
	
	-- Start ambience loop with fade-in
	if self._sounds.ambience then
		local ambience = self._sounds.ambience
		local targetVolume = self._originalAmbienceVolume or ambience.Volume
		ambience.Volume = 0
		ambience:Play()
		
		-- Fade in the ambience
		local fadeInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeTween = TweenService:Create(ambience, fadeInfo, { Volume = targetVolume })
		currentTweens["ambience_fade"] = { fadeTween }
		fadeTween:Play()
	end
	
	-- Tween GroupTransparency to 0.3 (so UI is at 70% visible / 0.7 opacity)
	local tweenInfo = TweenConfig.get("Main", "show")
	local showTweens = {}
	
	if self._ui:IsA("CanvasGroup") then
		local t = TweenService:Create(self._ui, tweenInfo, {
			GroupTransparency = 0.3,
		})
		t:Play()
		table.insert(showTweens, t)
	end
	
	currentTweens["main"] = showTweens
	
	-- Start damage pulse effect if we have a vignette
	self:_startDamagePulse()
	
	self._export:emit("StormUIShown")
	
	return true
end

function module:hide()
	if not self._isVisible then return false end
	self._isVisible = false
	self._isInStorm = false
	
	-- Cancel any ongoing show tweens or pulse
	cancelTweens("main")
	cancelTweens("pulse")
	cancelTweens("ambience_fade")
	
	-- Play leave sound
	if self._sounds.leave then
		self._sounds.leave:Play()
	end
	
	-- Fade out ambience smoothly instead of abrupt stop
	if self._sounds.ambience and self._sounds.ambience.IsPlaying then
		local ambience = self._sounds.ambience
		local originalVolume = self._originalAmbienceVolume or ambience.Volume
		local fadeInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeTween = TweenService:Create(ambience, fadeInfo, { Volume = 0 })
		currentTweens["ambience_fade"] = { fadeTween }
		fadeTween:Play()
		
		-- Stop and reset volume after fade completes
		task.spawn(function()
			task.wait(0.85)
			if ambience then
				ambience:Stop()
				ambience.Volume = originalVolume -- Reset for next time
			end
		end)
	end
	
	-- Tween GroupTransparency back to 1 (fully transparent)
	local tweenInfo = TweenConfig.get("Main", "hide")
	local hideTweens = {}
	
	if self._ui:IsA("CanvasGroup") then
		local t = TweenService:Create(self._ui, tweenInfo, {
			GroupTransparency = 1,
		})
		t:Play()
		table.insert(hideTweens, t)
	end
	
	currentTweens["main"] = hideTweens
	
	-- Wait for tween to complete then hide
	task.spawn(function()
		task.wait(tweenInfo.Time)
		if not self._isVisible then
			self._ui.Visible = false
		end
	end)
	
	self._export:emit("StormUIHidden")
	
	-- Return false to prevent CoreUI from calling _cleanup()
	-- Storm mesh and clouds should persist until match/round ends
	return false
end

--[[
	Starts a pulsing damage effect on the vignette.
]]
function module:_startDamagePulse()
	if not self._elements.vignette then return end
	
	cancelTweens("pulse")
	
	task.spawn(function()
		local vignette = self._elements.vignette
		local pulseIn = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local pulseOut = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		
		while self._isInStorm and vignette and vignette.Parent do
			-- Pulse in (more visible)
			local tIn
			if vignette:IsA("ImageLabel") then
				tIn = TweenService:Create(vignette, pulseIn, { ImageTransparency = 0.3 })
			else
				tIn = TweenService:Create(vignette, pulseIn, { BackgroundTransparency = 0.3 })
			end
			currentTweens["pulse"] = { tIn }
			tIn:Play()
			tIn.Completed:Wait()
			
			if not self._isInStorm then break end
			
			-- Pulse out (less visible)
			local tOut
			if vignette:IsA("ImageLabel") then
				tOut = TweenService:Create(vignette, pulseOut, { ImageTransparency = 0.6 })
			else
				tOut = TweenService:Create(vignette, pulseOut, { BackgroundTransparency = 0.6 })
			end
			currentTweens["pulse"] = { tOut }
			tOut:Play()
			tOut.Completed:Wait()
		end
	end)
end

--[[
	Plays the storm forming sound (called when storm phase starts).
	Also initializes storm clouds.
]]
function module:playFormingSound()
	if self._sounds.forming then
		self._sounds.forming:Play()
	end
	
	-- Initialize storm clouds on client
	self:_initializeStormClouds()
end

--[[
	Initializes storm clouds on the client (only affects this player's view).
]]
function module:_initializeStormClouds()
	local terrain = workspace:FindFirstChild("Terrain")
	if not terrain then return end
	
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = terrain
	end
	
	-- Store original values for cleanup
	self._originalCloudState = {
		cover = clouds.Cover,
		density = clouds.Density,
		color = clouds.Color,
		enabled = clouds.Enabled,
	}
	
	self._clouds = clouds
	
	-- Set storm cloud appearance
	clouds.Enabled = true
	clouds.Color = STORM_CLOUD_COLOR
	clouds.Density = STORM_CLOUD_START_DENSITY
	clouds.Cover = STORM_CLOUD_START_COVER
	
	print("[STORM UI] Storm clouds initialized on client")
end

--[[
	Restores clouds to original state.
]]
function module:_restoreStormClouds()
	if not self._clouds or not self._originalCloudState then return end
	
	local clouds = self._clouds
	local original = self._originalCloudState
	
	-- Tween back to original cover smoothly
	local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local restoreTween = TweenService:Create(clouds, tweenInfo, {
		Cover = original.cover,
		Density = original.density,
	})
	restoreTween:Play()
	
	-- After tween, restore color and enabled state
	task.delay(1.5, function()
		if clouds and clouds.Parent then
			clouds.Color = original.color
			clouds.Enabled = original.enabled
		end
	end)
	
	self._clouds = nil
	self._originalCloudState = nil
	
	print("[STORM UI] Storm clouds restored on client")
end

--[[
	Creates the local storm mesh based on server data.
	Called when StormStart event is received.
]]
function module:createStormMesh(data)
	-- Clean up any existing storm mesh first
	self:destroyStormMesh()
	
	if not data or not data.center or not data.initialRadius then
		warn("[STORM UI] Invalid storm data for mesh creation")
		return
	end
	
	-- Get the storm model template
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local stormTemplate = assetsFolder and assetsFolder:FindFirstChild("Strom")
	if not stormTemplate then
		warn("[STORM UI] Storm template not found in ReplicatedStorage.Assets.Strom")
		return
	end
	
	-- Clone the storm model
	local stormClone = stormTemplate:Clone()
	local stormMesh = stormClone:FindFirstChild("Storm")
	local rootPart = stormClone:FindFirstChild("Root")
	
	if not stormMesh or not stormMesh:IsA("BasePart") then
		warn("[STORM UI] Storm MeshPart not found in template")
		stormClone:Destroy()
		return
	end
	
	-- Store original size for scaling calculations
	local originalSize = stormMesh.Size
	local originalDiameter = math.max(originalSize.X, originalSize.Z)
	local targetDiameter = data.initialRadius * 2
	local scaleFactor = targetDiameter / originalDiameter
	
	-- Position root at center
	if rootPart then
		rootPart.Position = data.center
		rootPart.Anchored = true
		rootPart.CanCollide = false
	end
	
	-- Scale mesh X and Z
	stormMesh.Size = Vector3.new(
		originalSize.X * scaleFactor,
		originalSize.Y,
		originalSize.Z * scaleFactor
	)
	
	-- Position mesh with Y offset
	local meshHeight = stormMesh.Size.Y
	stormMesh.Position = Vector3.new(
		data.center.X,
		data.center.Y + STORM_Y_OFFSET + (meshHeight / 2),
		data.center.Z
	)
	stormMesh.Anchored = true
	stormMesh.CanCollide = false
	stormMesh.CanQuery = false
	stormMesh.CanTouch = false
	
	-- Start transparent, will fade in
	stormMesh.Transparency = 1
	
	-- Parent to workspace (local only - this is client-side)
	stormClone.Name = "LocalStorm"
	stormClone.Parent = workspace
	
	-- Store references for updates
	self._stormMesh = stormMesh
	self._stormModel = stormClone
	self._stormData = {
		center = data.center,
		initialRadius = data.initialRadius,
		targetRadius = data.targetRadius or 0,
		originalSizeX = originalSize.X,
		originalSizeZ = originalSize.Z,
		scaleFactor = scaleFactor,
	}

	-- Run a local timeline so shrink is continuous instead of step-updated by network ticks.
	self._stormVisualState = {
		startTime = os.clock(),
		duration = math.max(STORM_MIN_SHRINK_DURATION, tonumber(data.shrinkDuration) or 0),
		startRadius = data.initialRadius,
		targetRadius = data.targetRadius or 0,
		serverRadius = data.initialRadius,
		visualRadius = data.initialRadius,
	}
	
	-- Start the continuous visual update loop.
	self:_startStormLerpLoop()
	
	-- Fade in the mesh
	local fadeInfo = TweenInfo.new(STORM_FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTween = TweenService:Create(stormMesh, fadeInfo, { Transparency = STORM_MESH_TRANSPARENCY })
	fadeTween:Play()
	
	print("[STORM UI] Local storm mesh created - radius:", data.initialRadius)
end

--[[
	Applies a radius value directly to the local storm mesh scale.
]]
function module:_applyStormMeshRadius(radius)
	if not self._stormMesh or not self._stormMesh.Parent then return end
	if not self._stormData then return end

	local data = self._stormData
	local initialRadius = math.max(data.initialRadius or 0, 0.001)
	local clampedRadius = math.max(data.targetRadius or 0, radius or 0)
	local radiusRatio = clampedRadius / initialRadius
	local newScaleFactor = data.scaleFactor * radiusRatio

	self._stormMesh.Size = Vector3.new(
		data.originalSizeX * newScaleFactor,
		self._stormMesh.Size.Y,
		data.originalSizeZ * newScaleFactor
	)
end

--[[
	Starts a continuous loop that animates the storm radius every frame.
]]
function module:_startStormLerpLoop()
	-- Clean up existing loop if any
	if self._stormLerpConnection then
		self._stormLerpConnection:Disconnect()
		self._stormLerpConnection = nil
	end
	
	self._stormLerpConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not self._stormMesh or not self._stormMesh.Parent then
			-- Mesh was destroyed, stop the loop
			if self._stormLerpConnection then
				self._stormLerpConnection:Disconnect()
				self._stormLerpConnection = nil
			end
			return
		end
		
		local state = self._stormVisualState
		if not state then return end

		local elapsed = os.clock() - state.startTime
		local alpha = math.clamp(elapsed / state.duration, 0, 1)
		local timelineRadius = state.startRadius + ((state.targetRadius - state.startRadius) * alpha)

		-- Follow the local timeline, then softly reconcile toward server-authoritative radius.
		local reconcileFactor = math.clamp(deltaTime * STORM_RADIUS_RECONCILE_SPEED, 0, 1)
		local desiredRadius = timelineRadius
		if type(state.serverRadius) == "number" then
			desiredRadius = desiredRadius + ((state.serverRadius - desiredRadius) * reconcileFactor)
		end

		state.visualRadius = state.visualRadius + ((desiredRadius - state.visualRadius) * reconcileFactor)
		self:_applyStormMeshRadius(state.visualRadius)
	end)
end

--[[
	Receives server radius updates and uses them only for correction.
]]
function module:updateStormMesh(currentRadius)
	if not self._stormVisualState then
		self:_applyStormMeshRadius(currentRadius)
		return
	end

	self._stormVisualState.serverRadius = currentRadius
end

--[[
	Destroys the local storm mesh.
]]
function module:destroyStormMesh()
	-- Stop the lerp loop
	if self._stormLerpConnection then
		self._stormLerpConnection:Disconnect()
		self._stormLerpConnection = nil
	end
	self._stormVisualState = nil
	
	if self._stormModel and self._stormModel.Parent then
		self._stormModel:Destroy()
	end
	self._stormMesh = nil
	self._stormModel = nil
	self._stormData = nil
end

--[[
	Called when storm radius updates (can be used for UI indicator).
]]
function module:updateRadius(currentRadius, targetRadius, initialRadius)
	-- This can be extended to update a minimap indicator or progress bar
	-- showing how much the storm has closed in
	local progress = 1 - ((currentRadius - targetRadius) / (initialRadius - targetRadius))
	progress = math.clamp(progress, 0, 1)
	
	-- Update cloud coverage based on storm progress
	if self._clouds then
		local newCover = STORM_CLOUD_START_COVER + (STORM_CLOUD_FINAL_COVER - STORM_CLOUD_START_COVER) * progress
		self._clouds.Cover = math.min(1, newCover)
	end
	
	-- Update local storm mesh size
	self:updateStormMesh(currentRadius)
	
	-- Emit event for any listeners
	self._export:emit("StormRadiusUpdate", {
		currentRadius = currentRadius,
		targetRadius = targetRadius,
		initialRadius = initialRadius,
		progress = progress,
	})
end

function module:_cleanup()
	self._initialized = false
	self._isInStorm = false
	self._isVisible = false
	
	-- Stop the storm lerp loop
	if self._stormLerpConnection then
		self._stormLerpConnection:Disconnect()
		self._stormLerpConnection = nil
	end
	self._stormVisualState = nil
	
	-- Cancel all tweens
	cancelTweens("main")
	cancelTweens("pulse")
	cancelTweens("ambience_fade")
	
	-- Stop all sounds and reset ambience volume
	for name, sound in self._sounds do
		if sound then
			pcall(function() 
				sound:Stop()
				-- Reset ambience volume
				if name == "ambience" and self._originalAmbienceVolume then
					sound.Volume = self._originalAmbienceVolume
				end
			end)
		end
	end
	
	-- Restore clouds to original state
	self:_restoreStormClouds()
	
	-- Destroy local storm mesh
	self:destroyStormMesh()
	
	self._connections:cleanupAll()
end

return module
