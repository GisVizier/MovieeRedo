--[[
	Kon VFX Module
	
	Handles visual effects for Aki's Kon ability.
	
	Functions:
	- User(originUserId, data) - Viewmodel/screen effects for caster only
	- createKon(originUserId, data) - Spawns Kon, animation, bite VFX, smoke, despawn (ALL clients)
	- destroyKon(originUserId, data) - Early cleanup
	- placeTrap(originUserId, data) - Clones the "Placed" model visual with fade in/out
	- triggerTrap(originUserId, data) - Triggers trap: spawns Kon, plays VFX, despawns
	- destroyTrap(originUserId, data) - Cleans up trap marker
	
	data for createKon:
	- position: { X, Y, Z } (Kon spawn position)
	- lookVector: { X, Y, Z } (Kon facing direction)
	
	data for placeTrap:
	- position: { X, Y, Z } (trap placement position)
	- ownerId: number (UserId of the Aki player who placed the trap)
	
	data for triggerTrap:
	- position: { X, Y, Z } (trap position)
	
	data for User:
	- ViewModel: ViewmodelRig
	- forceAction: "start" | "bite" | "stop"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Util = require(script.Parent.Util)

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local Kon = {}

-- Active Kon instances per player
Kon._activeKons = {}

-- Active trap instances per player (only one per match)
Kon._activeTraps = {}

--------------------------------------------------------------------------------
-- TIMING CONSTANTS (adjust to match animations)
--------------------------------------------------------------------------------

local TIMING = {
	BITE_DELAY = 0.6,       -- Time after spawn when bite VFX triggers
	SMOKE_DELAY = 1.9,      -- Time after spawn when smoke starts
	KON_LIFETIME = 2.5,     -- Total time before Kon is destroyed
	FADE_TIME = 0.3,        -- Fade out duration
	TRAP_INDICATOR_TIME = 1, -- Red outline visible to all clients for this long
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getKonTemplate()
	-- Kon model is a child of this script (Kon folder)
	return script:FindFirstChild("Kon")
end

local function getKonnyTemplate()
	-- Konny model is a child of this script (moved from workspace)
	return script:FindFirstChild("konny")
end

local function getKonAnimation()
	-- Kon animation is a child of this script (Kon folder)
	return script:FindFirstChild("konanim")
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

-- Build a CFrame where Kon stands ON the surface (UpVector = surface normal)
-- Works for floors, walls, ceilings, and slopes
local function buildSurfaceCFrame(position, lookVector, surfaceNormal)
	-- Project lookVector onto the surface plane
	-- Remove the component of lookVector that's parallel to the normal
	local projectedLook = lookVector - surfaceNormal * lookVector:Dot(surfaceNormal)

	-- If projected vector is too small (looking directly at/away from surface), pick a fallback
	if projectedLook.Magnitude < 0.01 then
		-- Use world forward projected onto surface
		local worldForward = Vector3.new(0, 0, 1)
		projectedLook = worldForward - surfaceNormal * worldForward:Dot(surfaceNormal)

		-- If still too small (surface is horizontal), use world right
		if projectedLook.Magnitude < 0.01 then
			local worldRight = Vector3.new(1, 0, 0)
			projectedLook = worldRight - surfaceNormal * worldRight:Dot(surfaceNormal)
		end
	end

	projectedLook = projectedLook.Unit

	-- Build CFrame: UpVector = surface normal, LookVector = projected direction
	-- CFrame.lookAt uses the 3rd param as the UpVector hint
	local baseCFrame = CFrame.lookAt(position, position + projectedLook, surfaceNormal)

	-- Rotate to align Kon's model orientation
	return baseCFrame * CFrame.Angles(math.rad(90), 0, 0)
end

--------------------------------------------------------------------------------
-- VFX Helpers (reusable by both main variant and trap variant)
--------------------------------------------------------------------------------

-- Play a sound at a position using an invisible anchored part
local function playSoundAtPosition(soundName: string, position: Vector3)
	local soundsFolder = script:FindFirstChild("Sounds")
	if not soundsFolder then return end
	
	local soundTemplate = soundsFolder:FindFirstChild(soundName)
	if not soundTemplate then return end
	
	-- Create invisible anchored part at position
	local soundPart = Instance.new("Part")
	soundPart.Name = "SoundEmitter_" .. soundName
	soundPart.Size = Vector3.new(1, 1, 1)
	soundPart.Position = position
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.CanQuery = false
	soundPart.Transparency = 1
	soundPart.Parent = getEffectsFolder()
	
	-- Clone and play sound
	local sound = soundTemplate:Clone()
	sound.Parent = soundPart
	sound:Play()
	
	-- Destroy after 10 seconds
	task.delay(10, function()
		if soundPart and soundPart.Parent then
			soundPart:Destroy()
		end
	end)
end

local function playspawnVFX(konModel, position)
	task.spawn(function()
		ReplicateFX("kon", "spawn", { Character = game.Players.LocalPlayer.Character, Kon = konModel, Pivot = position})
	end)
end

local function playBiteVFX(konModel, position)
	ReplicateFX("kon", "bite", { Character = game.Players.LocalPlayer.Character, Kon = konModel, Pivot = position})
	
	-- Play bite sound at position
	local pos = typeof(position) == "CFrame" and position.Position or position
	--playSoundAtPosition("bite", pos)
end

local function playSmokeVFX(konModel, position)
	ReplicateFX("kon", "smoke", { Character = game.Players.LocalPlayer.Character, Kon = konModel, Pivot = position})
	
	-- Play smoke sound at position
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
		if konModel and konModel.Parent then
			konModel:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------
-- Reusable: Spawn and position a Kon model at a CFrame
-- Used by both createKon (main variant) and triggerTrap (trap variant)
--------------------------------------------------------------------------------

local function spawnKonModel(targetCFrame, originUserId, useKonny)
	local template = useKonny and getKonnyTemplate() or getKonTemplate()
	if not template then return nil end
	
	local konModel = template:Clone()
	konModel.Name = "Kon_" .. tostring(originUserId)
	
	-- Offset so the "Center" part lands at target position
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

--------------------------------------------------------------------------------
-- Reusable: Play an animation on a Kon model by asset ID
-- Used for Kon model animations (spawn, loop, shoot)
--------------------------------------------------------------------------------

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
	if looped then
		track.Looped = true
	end
	track:Play()
	
	return track
end

--------------------------------------------------------------------------------
-- Reusable: Full Kon lifecycle (spawn → bite VFX → smoke VFX → despawn)
-- Used by both createKon and triggerTrap
--------------------------------------------------------------------------------

local function runKonLifecycle(self, konModel, targetCFrame, originUserId)
	self._activeKons[originUserId] = konModel
	
	playspawnVFX(konModel, targetCFrame)
	playSoundAtPosition("bite", targetCFrame.Position)
	
	-- Play Kon animation (use stored animation object)
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
	
	-- BITE VFX - triggers at BITE_DELAY
	task.delay(TIMING.BITE_DELAY, function()
		if not konModel or not konModel.Parent then return end
		if self._activeKons[originUserId] ~= konModel then return end
		playBiteVFX(konModel, targetCFrame)
	end)
	
	-- SMOKE VFX - triggers at SMOKE_DELAY
	task.delay(TIMING.SMOKE_DELAY, function()
		if not konModel or not konModel.Parent then return end
		if self._activeKons[originUserId] ~= konModel then return end
		playSmokeVFX(konModel, targetCFrame)
	end)
	
	-- DESPAWN - after KON_LIFETIME
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
	if not position then
		return
	end

	local lookVector = parseLookVector(data.lookVector)
	local surfaceNormal = parseNormal(data.surfaceNormal)
	local targetCFrame = buildSurfaceCFrame(position, lookVector, surfaceNormal)

	-- Spawn Kon model using reusable helper
	local konModel = spawnKonModel(targetCFrame, originUserId, false)
	if not konModel then return end
	
	-- Run the full lifecycle (animation, bite, smoke, despawn)
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
		
		-- If this client is NOT the owner, fade out the entire visual
		if localPlayer.UserId ~= ownerId then
			fadeOutElements(elements, FADE_OUT_TIME)
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
	
	-- Build a proper surface-aligned CFrame (same as createKon)
	local lookVector = parseLookVector(data.lookVector)
	local surfaceNormal = parseNormal(data.surfaceNormal)
	local targetCFrame = buildSurfaceCFrame(position, lookVector, surfaceNormal)
	
	-- Spawn the Kon model (use konny template for trap variant)
	local konModel = spawnKonModel(targetCFrame, originUserId, true)
	if not konModel then
		-- Fallback to regular Kon template if konny isn't available
		konModel = spawnKonModel(targetCFrame, originUserId, false)
	end
	if not konModel then return end
	
	-- Run the full Kon lifecycle (spawn VFX, bite VFX, smoke VFX, despawn)
	runKonLifecycle(self, konModel, targetCFrame, originUserId)
end

--[[
	destroyTrap - Clean up trap marker and any active Kon model
	
	Called when:
	- Aki uses self-launch
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
end)

return Kon
