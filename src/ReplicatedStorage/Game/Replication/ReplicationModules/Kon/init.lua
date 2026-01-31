--[[
	Kon VFX Module
	
	Handles visual effects for Aki's Kon ability.
	
	Functions:
	- User(originUserId, data) - Viewmodel/screen effects for caster only
	- createKon(originUserId, data) - Spawns Kon, animation, bite VFX, smoke, despawn (ALL clients)
	- destroyKon(originUserId, data) - Early cleanup
	
	data for createKon:
	- position: { X, Y, Z } (Kon spawn position)
	- lookVector: { X, Y, Z } (Kon facing direction)
	
	data for User:
	- ViewModel: ViewmodelRig
	- forceAction: "start" | "bite" | "stop"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Util = require(script.Parent.Util)

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local Kon = {}

-- Active Kon instances per player
Kon._activeKons = {}

--------------------------------------------------------------------------------
-- TIMING CONSTANTS (adjust to match animations)
--------------------------------------------------------------------------------

local TIMING = {
	BITE_DELAY = 0.6,       -- Time after spawn when bite VFX triggers
	SMOKE_DELAY = 1.9,      -- Time after spawn when smoke starts
	KON_LIFETIME = 2.5,     -- Total time before Kon is destroyed
	FADE_TIME = 0.3,        -- Fade out duration
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getKonTemplate()
	-- Kon model is a child of this script (Kon folder)
	return script:FindFirstChild("Kon")
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
-- VFX Helpers
--------------------------------------------------------------------------------
local function playspawnVFX(konModel, position)

	task.spawn(function()
		ReplicateFX("kon", "spawn", { Character = game.Players.LocalPlayer.Character, Kon = konModel, Pivot = position})
	end)


	--print("[Kon VFX] Spawn VFX at", position)
end

local function playBiteVFX(konModel, position)
	-- Bite impact particles/sound
	-- TODO: Add your actual bite VFX here
	-- Example:
	-- local biteEmitter = konModel:FindFirstChild("BiteParticles", true)
	-- if biteEmitter and biteEmitter:IsA("ParticleEmitter") then
	--     biteEmitter:Emit(20)
	-- end
	ReplicateFX("kon", "bite", { Character = game.Players.LocalPlayer.Character, Kon = konModel, Pivot = position})
	--print("[Kon VFX] Bite VFX at", position)
end

local function playSmokeVFX(konModel, position)
	-- Smoke/poof particles when Kon disappears
	-- TODO: Add your actual smoke VFX here
	-- Example:
	-- local smokeEmitter = konModel:FindFirstChild("SmokeEmitter", true)
	-- if smokeEmitter and smokeEmitter:IsA("ParticleEmitter") then
	--     smokeEmitter:Emit(30)
	-- end
	ReplicateFX("kon", "smoke", { Character = game.Players.LocalPlayer.Character, Kon = konModel, Pivot = position})
	--print("[Kon VFX] Smoke VFX at", position)
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
	if not localPlayer or localPlayer.UserId ~= originUserId then
		return -- Only run on caster's client
	end

	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	local ViewModel = data.ViewModel or (viewmodelController and viewmodelController:GetActiveRig())

	local action = data.forceAction
	if action == "start" then
		-- Screen shake, viewmodel particles on ability start
		print("[Kon VFX] User: start effects")
		ReplicateFX("kon", "shake", { Character = localPlayer.Character, ViewModel = ViewModel})
		-- TODO: Add screen shake, particles, etc.

	elseif action == "bite" then
		-- Screen shake on bite impact
		print("[Kon VFX] User: bite screen effects")
		-- TODO: Add camera shake for impact
		
	elseif action == "stop" then
		-- Cleanup viewmodel effects
		print("[Kon VFX] User: stop effects")
	end
end

--------------------------------------------------------------------------------
-- createKon - Spawns Kon for ALL clients with full lifecycle
--------------------------------------------------------------------------------

function Kon:createKon(originUserId, data)
	if not data then return end

	local position = parsePosition(data.position)
	if not position then
		warn("[Kon VFX] No position provided")
		return
	end

	local lookVector = parseLookVector(data.lookVector)
	local surfaceNormal = parseNormal(data.surfaceNormal)
	local targetCFrame = buildSurfaceCFrame(position, lookVector, surfaceNormal)

	-- Get template
	local template = getKonTemplate()

	-- Clone and position
	local konModel = template:Clone()
	konModel.Name = "Kon_" .. originUserId

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
	self._activeKons[originUserId] = konModel

	playspawnVFX(konModel, targetCFrame)

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
			print("[Kon VFX] Animation playing")
		end
	end

	----------------------------------------------------------------
	-- BITE VFX - triggers at BITE_DELAY
	----------------------------------------------------------------
	task.delay(TIMING.BITE_DELAY, function()
		if not konModel or not konModel.Parent then return end
		if self._activeKons[originUserId] ~= konModel then return end
		
		playBiteVFX(konModel, targetCFrame)
	end)

	----------------------------------------------------------------
	-- SMOKE VFX - triggers at SMOKE_DELAY
	----------------------------------------------------------------
	task.delay(TIMING.SMOKE_DELAY, function()
		if not konModel or not konModel.Parent then return end
		if self._activeKons[originUserId] ~= konModel then return end
		
		playSmokeVFX(konModel, targetCFrame)
	end)

	----------------------------------------------------------------
	-- DESPAWN - after KON_LIFETIME
	----------------------------------------------------------------
	task.delay(TIMING.KON_LIFETIME - TIMING.FADE_TIME, function()
		if self._activeKons[originUserId] == konModel then
			despawnKon(konModel, TIMING.FADE_TIME)
			self._activeKons[originUserId] = nil
		end
	end)
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
-- Cleanup on player leave
--------------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	local konModel = Kon._activeKons[player.UserId]
	if konModel then
		konModel:Destroy()
		Kon._activeKons[player.UserId] = nil
	end
end)

return Kon
