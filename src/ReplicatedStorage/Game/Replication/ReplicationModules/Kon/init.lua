--[[
	Kon VFX Module
	
	Handles visual effects for Aki's Kon ability.
	Routes to two Client modules:
	  - Clients/kon  : low-level trap/Kon lifecycle VFX (spawn, bite, smoke, shake)
	  - Clients/User : viewmodel/caster FX for projectile variant (windfX, charge, spawn,
	                   kon, fire, ReplicateProjectile, smoke, start)
	
	== Trap Variant ==
	- placeTrap(data) - Clones "Placed" model visual with fade in/out
	- triggerTrap(data) - Spawns Kon, runs bite/smoke lifecycle
	- selfLaunch(data) - Signals kit via attribute for self-launch (ME only)
	- trapHitVoice(data) - Plays voice line on trap activation (ME only)
	- destroyTrap(data) - Cleans up trap visual
	
	== Main / Projectile Variant ==
	- fxWind(data) → User.windfX  (wind aura / mesh FX on viewmodel)
	- fxCharge(data) → User.charge  (flipbook charge on arms)
	- fxSpawn(data) → User.spawn  (FOV punch, highlight, meshspin on Kon)
	- fxKon(data) → User.kon  (viewport mesh FX, white highlight on Kon)
	- fxFire(data) → User.fire  (throw burst, meshes, rock debris)
	- fxProjectile(data) → User.ReplicateProjectile  (soaring trail on projectile)
	- fxSmoke(data) → User.smoke  (impact smoke)
	- fireProjectile(data) - Spectator: creates Kon, simulates trajectory, attaches soaring FX
	- projectileImpact(data) - All: signals hit on spectator Kon, plays impact smoke
	
	== Legacy ==
	- User(data) - Old viewmodel shake dispatcher (start/bite/stop)
	- createKon(data) - Spawns Kon with full lifecycle (ALL clients)
	- destroyKon(data) - Early cleanup
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Util = require(script.Parent.Util)

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local Kon = {}

-- Active Kon instances per player (trap variant lifecycle)
Kon._activeKons = {}

-- Active trap instances per player (only one per match)
Kon._activeTraps = {}

-- Active spectator projectile models per player (for other clients watching the Kon fly)
Kon._activeProjectiles = {}

--------------------------------------------------------------------------------
-- Lazy-require the Aki client kit — all Kon MODEL logic lives there now.
-- This module is a thin routing layer for VFXRep calls.
--------------------------------------------------------------------------------

local _akiKit
local function getAkiKit()
	if not _akiKit then
		pcall(function()
			_akiKit = require(ReplicatedStorage:WaitForChild("KitSystem"):WaitForChild("ClientKits"):WaitForChild("Aki"))
		end)
	end
	return _akiKit
end

-- Eagerly pre-require in background so it's ready for first VFX call
task.spawn(function()
	getAkiKit()
end)

--------------------------------------------------------------------------------
-- Helpers (data parsing, FX routing — NOT model logic)
--------------------------------------------------------------------------------

local function getEffectsFolder()
	local folder = Workspace:FindFirstChild("Effects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder
end

local function parsePosition(posData)
	if typeof(posData) == "Vector3" then
		return posData
	elseif typeof(posData) == "table" then
		return Vector3.new(posData.X or 0, posData.Y or 0, posData.Z or 0)
	end
	return nil
end

local function ReplicateFX(module, action, fxData)
	local clientsFolder = script:FindFirstChild("Clients")
	if not clientsFolder then return end
	local nmodule = clientsFolder:FindFirstChild(module)
	if nmodule then
		local mod = require(nmodule)
		return mod[action](nil, fxData)
	end
end

local function parseLookVector(lookData)
	if typeof(lookData) == "Vector3" then
		return lookData.Unit
	elseif typeof(lookData) == "table" then
		return Vector3.new(lookData.X or 0, lookData.Y or 0, lookData.Z or 1).Unit
	end
	return Vector3.new(0, 0, 1)
end

local function parseNormal(normalData)
	if typeof(normalData) == "Vector3" then
		return normalData.Unit
	elseif typeof(normalData) == "table" then
		return Vector3.new(normalData.X or 0, normalData.Y or 1, normalData.Z or 0).Unit
	end
	return Vector3.new(0, 1, 0)
end

--------------------------------------------------------------------------------
-- Trap / Legacy Kon model helpers
-- These run on ALL clients and must live in the rep mod for replication.
-- (Projectile-variant caster logic lives in ClientKits/Aki/init.lua.)
--------------------------------------------------------------------------------

local TIMING = {
	BITE_DELAY = 0.6,
	SMOKE_DELAY = 1.9,
	KON_LIFETIME = 2.5,
	FADE_TIME = 0.3,
}

local function getKonTemplate()
	return script:FindFirstChild("Kon")
end

local function getKonnyTemplate()
	return script:FindFirstChild("konny")
end

local function getKonAnimation()
	return script:FindFirstChild("konanim")
end

-- Build a CFrame where Kon stands ON the surface (UpVector = surface normal)
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

local function playSoundAtPosition(soundName, position)
	local soundsFolder = script:FindFirstChild("Sounds")
	if not soundsFolder then return end
	local soundTemplate = soundsFolder:FindFirstChild(soundName)
	if not soundTemplate then return end

	local soundPart = Instance.new("Part")
	soundPart.Name = "SoundEmitter_" .. soundName
	soundPart.Size = Vector3.new(1, 1, 1)
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

local function playspawnVFX(konModel, position)
	task.spawn(function()
		ReplicateFX("kon", "spawn", { Character = game.Players.LocalPlayer.Character, Kon = konModel, Pivot = position })
	end)
end

local function playBiteVFX(konModel, position)
	ReplicateFX("kon", "bite", { Character = game.Players.LocalPlayer.Character, Kon = konModel, Pivot = position })
end

local function playSmokeVFX(konModel, position)
	ReplicateFX("kon", "smoke", { Character = game.Players.LocalPlayer.Character, Kon = konModel, Pivot = position })
	local pos = typeof(position) == "CFrame" and position.Position or position
	playSoundAtPosition("smoke", pos)
end

local function despawnKon(konModel, fadeTime)
	if not konModel or not konModel.Parent then return end
	for _, part in ipairs(konModel:GetDescendants()) do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(fadeTime), { Transparency = 1 }):Play()
		end
	end
	task.delay(fadeTime, function()
		if konModel and konModel.Parent then konModel:Destroy() end
	end)
end

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

local function playKonAnimationById(konModel, animId, looped)
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
	if looped then track.Looped = true end
	track:Play()
	return track
end

-- Full Kon lifecycle: spawn → animation → bite VFX → smoke VFX → despawn
local function runKonLifecycle(self, konModel, targetCFrame, originUserId)
	self._activeKons[originUserId] = konModel

	playspawnVFX(konModel, targetCFrame)
	playSoundAtPosition("bite", targetCFrame.Position)

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

	task.delay(TIMING.BITE_DELAY, function()
		if not konModel or not konModel.Parent then return end
		if self._activeKons[originUserId] ~= konModel then return end
		playBiteVFX(konModel, targetCFrame)
	end)

	task.delay(TIMING.SMOKE_DELAY, function()
		if not konModel or not konModel.Parent then return end
		if self._activeKons[originUserId] ~= konModel then return end
		playSmokeVFX(konModel, targetCFrame)
	end)

	task.delay(TIMING.KON_LIFETIME - TIMING.FADE_TIME, function()
		if self._activeKons[originUserId] == konModel then
			despawnKon(konModel, TIMING.FADE_TIME)
			self._activeKons[originUserId] = nil
		end
	end)
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

function Kon:Validate(_player, data)
	return typeof(data) == "table"
end

--------------------------------------------------------------------------------
-- User - Viewmodel/screen effects for CASTER only
--------------------------------------------------------------------------------

function Kon:User(originUserId, data)
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end

	local isLocal = localPlayer.UserId == originUserId
	local isSpectate = data and data._spectate == true
	if not isLocal and not isSpectate then
		return
	end

	local character = data.Character or localPlayer.Character
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	local ViewModel = data.ViewModel or (viewmodelController and viewmodelController:GetActiveRig())

	local action = data.forceAction
	if action == "start" then
		ReplicateFX("kon", "shake", { Character = character, ViewModel = ViewModel })

	elseif action == "bite" then
		-- Camera shake on bite impact

	elseif action == "stop" then
		-- Cleanup viewmodel effects
	end
end

--------------------------------------------------------------------------------
-- createKon - Spawns Kon for ALL clients with full lifecycle
--------------------------------------------------------------------------------

function Kon:createKon(originUserId, data)
	if not data then return end

	local position = parsePosition(data.position)
	if not position then return end

	local lookVector = parseLookVector(data.lookVector)
	local surfaceNormal = parseNormal(data.surfaceNormal)
	local targetCFrame = buildSurfaceCFrame(position, lookVector, surfaceNormal)

	local konModel = spawnKonModel(targetCFrame, originUserId, false)
	if not konModel then return end

	runKonLifecycle(self, konModel, targetCFrame, originUserId)
end

--------------------------------------------------------------------------------
-- destroyKon - Early cleanup
--------------------------------------------------------------------------------

function Kon:destroyKon(originUserId, data)
	local konModel = self._activeKons[originUserId]
	if konModel then
		despawnKon(konModel, 0.1)
		self._activeKons[originUserId] = nil
	end
end

--------------------------------------------------------------------------------
-- TRAP VARIANT VFX
--------------------------------------------------------------------------------

-- Helper: get the "Placed" template model from the Aki ClientKit module
local function getPlacedTemplate()
	local kitSystem = ReplicatedStorage:FindFirstChild("KitSystem")
	if not kitSystem then return nil end
	local clientKits = kitSystem:FindFirstChild("ClientKits")
	if not clientKits then return nil end
	local akiModule = clientKits:FindFirstChild("Aki")
	if not akiModule then return nil end
	return akiModule:FindFirstChild("Placed")
end

-- Helper: fade all visual elements in a Placed model clone
-- Returns { parts = {{part, originalTransparency}}, beams = {}, lights = {}, guis = {} }
local function collectVisualElements(model)
	local elements = { parts = {}, beams = {}, lights = {}, guis = {} }
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(elements.parts, { part = desc, original = desc.Transparency })
		elseif desc:IsA("Beam") then
			table.insert(elements.beams, desc)
		elseif desc:IsA("Light") then
			table.insert(elements.lights, { light = desc, originalBrightness = desc.Brightness })
		elseif desc:IsA("SurfaceGui") or desc:IsA("BillboardGui") then
			table.insert(elements.guis, desc)
		end
	end
	-- Check top-level if model itself is a BasePart
	if model:IsA("BasePart") then
		table.insert(elements.parts, { part = model, original = model.Transparency })
	end
	return elements
end

-- Helper: set all visual elements to invisible (pre-fade-in state)
local function hideAllElements(elements)
	for _, pd in ipairs(elements.parts) do
		pd.part.Transparency = 1
		pd.part.CanCollide = false
		pd.part.CanQuery = false
		pd.part.Anchored = true
	end
	for _, beam in ipairs(elements.beams) do
		beam.Enabled = false
	end
	for _, ld in ipairs(elements.lights) do
		ld.light.Brightness = 0
	end
	for _, gui in ipairs(elements.guis) do
		gui.Enabled = false
	end
end

-- Helper: fade in all visual elements
local function fadeInElements(elements, duration)
	-- Tween parts to their original transparency
	for _, pd in ipairs(elements.parts) do
		TweenService:Create(pd.part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = pd.original,
		}):Play()
	end
	-- Enable beams after a small delay (looks better when parts are partially faded in)
	task.delay(duration * 0.3, function()
		for _, beam in ipairs(elements.beams) do
			if beam and beam.Parent then
				beam.Enabled = true
			end
		end
	end)
	-- Tween lights to their original brightness
	for _, ld in ipairs(elements.lights) do
		TweenService:Create(ld.light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = ld.originalBrightness,
		}):Play()
	end
	-- Enable GUIs
	task.delay(duration * 0.3, function()
		for _, gui in ipairs(elements.guis) do
			if gui and gui.Parent then
				gui.Enabled = true
			end
		end
	end)
end

-- Helper: fade out all visual elements (for non-owner clients)
local function fadeOutElements(elements, duration)
	-- Tween parts to fully transparent
	for _, pd in ipairs(elements.parts) do
		if pd.part and pd.part.Parent then
			TweenService:Create(pd.part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			}):Play()
		end
	end
	-- Disable beams
	for _, beam in ipairs(elements.beams) do
		if beam and beam.Parent then
			beam.Enabled = false
		end
	end
	-- Fade out lights
	for _, ld in ipairs(elements.lights) do
		if ld.light and ld.light.Parent then
			TweenService:Create(ld.light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Brightness = 0,
			}):Play()
		end
	end
	-- Disable GUIs
	for _, gui in ipairs(elements.guis) do
		if gui and gui.Parent then
			gui.Enabled = false
		end
	end
end

--[[
	placeTrap - Creates the trap visual using the "Placed" model from the Aki module
	
	- Clones the Placed model and positions it at the trap location
	- Fades in all parts (BaseParts, Beams, Lights, GUIs) for ALL clients
	- After 1.5 seconds, fades out for non-owner clients (only Aki can still see it)
	- Destroyed when trap triggers, self-launch, or kit destroy
	
	data:
	- position: { X, Y, Z } (trap placement position)
	- ownerId: number (UserId of the Aki player who placed the trap)
]]
function Kon:placeTrap(originUserId, data)
	if not data then return end
	
	local position = parsePosition(data.position)
	if not position then return end
	
	local ownerId = data.ownerId or originUserId
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end
	
	-- Clean up any existing trap visual for this player
	if self._activeTraps[originUserId] then
		local oldMarker = self._activeTraps[originUserId]
		if oldMarker and oldMarker.Parent then
			oldMarker:Destroy()
		end
		self._activeTraps[originUserId] = nil
	end
	
	-- Get the "Placed" template model from the Aki ClientKit module
	local placedTemplate = getPlacedTemplate()
	if not placedTemplate then
		warn("[Kon VFX] placeTrap: 'Placed' model not found under Aki module")
		return
	end
	
	-- Clone and position the model, preserving the template's rotation
	-- (The template is oriented so the Center part faces upward — flat on the ground)
	local trapModel = placedTemplate:Clone()
	trapModel.Name = "KonTrap_" .. tostring(originUserId)
	local templateRotation = placedTemplate:GetPivot() - placedTemplate:GetPivot().Position
	trapModel:PivotTo(CFrame.new(position) * templateRotation)
	
	-- Collect all visual elements and hide them for fade-in
	local elements = collectVisualElements(trapModel)
	hideAllElements(elements)
	
	-- Parent to Effects folder
	trapModel.Parent = getEffectsFolder()
	
	-- Store the trap model
	self._activeTraps[originUserId] = trapModel
	
	-- Fade IN all visual elements (0.4s)
	local FADE_IN_TIME = 0.4
	fadeInElements(elements, FADE_IN_TIME)
	
	-- After 1.5 seconds, fade out for non-owner clients
	local FADE_OUT_DELAY = 1.5
	local FADE_OUT_TIME = 0.5
	task.delay(FADE_OUT_DELAY, function()
		if not trapModel or not trapModel.Parent then return end
		if self._activeTraps[originUserId] ~= trapModel then return end
		
		-- If this client is NOT the owner, fade out then destroy the model
		if localPlayer.UserId ~= ownerId then
			fadeOutElements(elements, FADE_OUT_TIME)
			-- Actually remove the model after the fade completes
			task.delay(FADE_OUT_TIME + 0.1, function()
				if trapModel and trapModel.Parent then
					if self._activeTraps[originUserId] == trapModel then
						self._activeTraps[originUserId] = nil
					end
					trapModel:Destroy()
				end
			end)
		end
	end)
end

--[[
	triggerTrap - Trap has been triggered by a nearby character
	
	- Removes the trap marker
	- Spawns Kon at the trap position (same flow as createKon: rise from ground, bite, smoke)
	- Uses buildSurfaceCFrame for proper ground orientation
	
	data:
	- position: { X, Y, Z } (trap position)
	- lookVector: { X, Y, Z } (direction Kon faces — toward the trigger target)
	- surfaceNormal: { X, Y, Z } (ground normal, typically 0,1,0)
]]
function Kon:triggerTrap(originUserId, data)
	if not data then return end

	local position = parsePosition(data.position)
	if not position then return end

	-- Remove the trap marker
	local trapMarker = self._activeTraps[originUserId]
	if trapMarker and trapMarker.Parent then
		trapMarker:Destroy()
	end
	self._activeTraps[originUserId] = nil

	local lookVector = parseLookVector(data.lookVector)
	local surfaceNormal = parseNormal(data.surfaceNormal)
	local targetCFrame = buildSurfaceCFrame(position, lookVector, surfaceNormal)

	-- Spawn the Kon model (prefer konny, fallback to regular)
	local konModel = spawnKonModel(targetCFrame, originUserId, true)
	if not konModel then
		konModel = spawnKonModel(targetCFrame, originUserId, false)
	end
	if not konModel then return end

	runKonLifecycle(self, konModel, targetCFrame, originUserId)
end

--[[
	selfLaunch - Signal for server-triggered self-launch
	
	Called via BroadcastVFX("Me") when the unified _triggerTrap detects Aki in the trap radius,
	or when projectile impact validates self-hit on the server.
	Sets _KonSelfLaunchTick attribute on LocalPlayer — actual movement/launch logic
	lives in ClientKits/Aki/init.lua (doSelfLaunch).
	
	data:
	- position: { X, Y, Z } (trap/impact position, for reference)
]]
function Kon:selfLaunch(originUserId, data)
	local localPlayer = Players.LocalPlayer
	if not localPlayer or localPlayer.UserId ~= originUserId then return end
	-- Signal the kit via attribute — actual launch logic lives in ClientKits/Aki/init.lua
	localPlayer:SetAttribute("_KonSelfLaunchTick", tick())
end

--[[
	destroyTrap - Clean up trap marker and any active Kon model
	
	Called when:
	- Trap triggers (server calls destroyTrap before createKon)
	- Kit is destroyed (death/round end)
	- Kit is unequipped
]]
function Kon:destroyTrap(originUserId, data)
	-- Remove the trap marker
	local trapMarker = self._activeTraps[originUserId]
	if trapMarker and trapMarker.Parent then
		trapMarker:Destroy()
	end
	self._activeTraps[originUserId] = nil
	
	-- Also clean up any active Kon model from a triggered trap
	local konModel = self._activeKons[originUserId]
	if konModel then
		despawnKon(konModel, 0.1)
		self._activeKons[originUserId] = nil
	end
end

--------------------------------------------------------------------------------
-- Cleanup on player leave
--------------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	local konModel = Kon._activeKons[player.UserId]
	if konModel then
		konModel:Destroy()
		Kon._activeKons[player.UserId] = nil
	end
	
	local trapMarker = Kon._activeTraps[player.UserId]
	if trapMarker then
		trapMarker:Destroy()
		Kon._activeTraps[player.UserId] = nil
	end
	
	local projModel = Kon._activeProjectiles[player.UserId]
	if projModel and typeof(projModel) == "Instance" and projModel.Parent then
		projModel:Destroy()
	end
	Kon._activeProjectiles[player.UserId] = nil
end)

--------------------------------------------------------------------------------
-- Cleanup when spectating ends (Kon User "shake" is one-shot; no-op for now)
--------------------------------------------------------------------------------

function Kon:CleanupSpectateEffects()
	-- Kon's spectate effects (User "start" shake) are one-shot; nothing to clean
end

--------------------------------------------------------------------------------
-- PROJECTILE REPLICATION (for spectator / other clients)
-- fireProjectile: creates a Kon model on OTHER clients, simulates trajectory,
--   plays fly animation, and attaches soaring FX from User module.
-- projectileImpact: signals the spectator Kon hit something → plays impact FX.
--------------------------------------------------------------------------------

-- Projectile physics constants (match client kit values)
local SPEC_PROJ_SPEED = 130
local SPEC_PROJ_GRAVITY = 80
local SPEC_PROJ_DRAG = 0.005
local SPEC_PROJ_SCALE = 4
local SPEC_PROJ_TIMEOUT = 8

--[[
	fireProjectile - Replicate Kon projectile for OTHER clients (spectators)
	
	Called via VFXRep:Fire("Others", "Kon", data, "fireProjectile")
	Creates a Kon model on each spectator, simulates the trajectory locally,
	and attaches the "Soaring" trail FX via Clients/User.ReplicateProjectile.
	
	data:
	- startPosition: { X, Y, Z }
	- direction: { X, Y, Z } (unit vector)
	- ownerId: number
]]
function Kon:fireProjectile(originUserId, data)
	if not data then return end

	local startPosition = parsePosition(data.startPosition)
	local direction = parseLookVector(data.direction)
	if not startPosition or not direction then return end

	-- Clean up any existing spectator projectile for this player
	if self._activeProjectiles[originUserId] then
		local old = self._activeProjectiles[originUserId]
		if typeof(old) == "Instance" and old.Parent then old:Destroy() end
		self._activeProjectiles[originUserId] = nil
	end

	-- Throw sound — heard at the launch position by all spectators
	playSoundAtPosition("shoot", startPosition)

	-- Clone konny model, scale, orient
	local template = getKonnyTemplate()
	if not template then return end

	local konModel = template:Clone()
	konModel.Name = "KonProjectile_" .. tostring(originUserId)
	konModel:ScaleTo(SPEC_PROJ_SCALE)
	konModel:PivotTo(CFrame.lookAt(startPosition, startPosition + direction) * CFrame.Angles(0, math.pi, 0))
	konModel.Parent = getEffectsFolder()

	self._activeProjectiles[originUserId] = konModel

	-- Play looped fly animation
	playKonAnimationById(konModel, "138478054902806", true)

	-- Attach soaring trail FX from User module
	ReplicateFX("User", "ReplicateProjectile", { Projectile = konModel })

	-- Simulate trajectory with simple Euler integration
	local velocity = direction * SPEC_PROJ_SPEED
	local gravity = Vector3.new(0, -SPEC_PROJ_GRAVITY, 0)
	local pos = startPosition
	local elapsed = 0

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not konModel or not konModel.Parent then
			if conn then conn:Disconnect() end
			return
		end

		-- Stop movement when impact is signaled by projectileImpact
		if konModel:GetAttribute("Hit") then
			if conn then conn:Disconnect() end
			return
		end

		elapsed += dt
		if elapsed > SPEC_PROJ_TIMEOUT then
			konModel:Destroy()
			if conn then conn:Disconnect() end
			self._activeProjectiles[originUserId] = nil
			return
		end

		-- Euler integration (matches client kit physics)
		velocity = velocity + gravity * dt
		velocity = velocity * (1 - SPEC_PROJ_DRAG * dt)
		pos = pos + velocity * dt

		konModel:PivotTo(CFrame.lookAt(pos, pos + velocity.Unit) * CFrame.Angles(0, math.pi, 0))
	end)
end

--[[
	projectileImpact - Impact VFX for ALL clients
	
	Called via VFXRep:Fire("All", "Kon", data, "projectileImpact")
	- Signals the spectator Kon model (if any) as "Hit" so soaring FX transitions
	- Plays impact smoke FX at the position
	
	data:
	- position: { X, Y, Z }
	- ownerId: number
]]
function Kon:projectileImpact(originUserId, data)
	if not data then return end

	local position = parsePosition(data.position)
	if not position then return end

	-- Stop + clean up spectator projectile
	if self._activeProjectiles[originUserId] then
		local konModel = self._activeProjectiles[originUserId]
		if typeof(konModel) == "Instance" and konModel.Parent then
			-- Signal Hit — stops the Heartbeat movement loop & soaring FX
			konModel:SetAttribute("Hit", true)

			-- Snap to impact position so it doesn't linger mid-air
			pcall(function()
				konModel:PivotTo(CFrame.new(position) * konModel:GetPivot().Rotation)
			end)

			-- Fade out + destroy after a short delay
			task.delay(0.5, function()
				if konModel and konModel.Parent then
					konModel:Destroy()
				end
			end)
		end
		self._activeProjectiles[originUserId] = nil
	end

	-- Play impact smoke VFX via Clients/User module
	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	if character then
		ReplicateFX("User", "smoke", {
			Character = character,
			Pivot = CFrame.new(position),
		})
	end

	-- Impact smoke sound — positional, heard by all clients at impact spot
	playSoundAtPosition("smoke", position)
end

--[[
	trapHitVoice - Plays Kon voice line when trap activates (owner only)
	
	Called via BroadcastVFX("Me") from server when trap triggers.
]]
local HIT_VOICE_LINE = "rbxassetid://138015603446992"
function Kon:trapHitVoice(originUserId, data)
	local localPlayer = Players.LocalPlayer
	if not localPlayer or localPlayer.UserId ~= originUserId then return end

	local character = localPlayer.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
	if not root then return end

	local sound = Instance.new("Sound")
	sound.SoundId = HIT_VOICE_LINE
	sound.Volume = 1
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, 5)
end

--------------------------------------------------------------------------------
-- MAIN VARIANT FX (routed to Clients/User module)
-- These are the viewmodel/caster FX for the projectile variant.
-- Called via VFXRep:Fire("Me", { Module="Kon", Function="fxCharge" }, data) etc.
-- Data is passed straight through to the User module functions.
--------------------------------------------------------------------------------

function Kon:fxWind(originUserId, data)
	ReplicateFX("User", "windfX", data)
end

function Kon:fxSpawn(originUserId, data)
	ReplicateFX("User", "spawn", data)
end

function Kon:fxCharge(originUserId, data)
	ReplicateFX("User", "charge", data)
end

function Kon:fxKon(originUserId, data)
	ReplicateFX("User", "kon", data)
end

function Kon:fxStart(originUserId, data)
	ReplicateFX("User", "start", data)
end

function Kon:fxFire(originUserId, data)
	ReplicateFX("User", "fire", data)
end

function Kon:fxSmoke(originUserId, data)
	ReplicateFX("User", "smoke", data)
end

function Kon:fxProjectile(originUserId, data)
	ReplicateFX("User", "ReplicateProjectile", data)
end

return Kon
