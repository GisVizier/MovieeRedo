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
	BITE_DELAY = 0.8,       -- Time after spawn when bite VFX triggers
	SMOKE_DELAY = 2.0,      -- Time after spawn when smoke starts
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

local function parseLookVector(lookData)
	if typeof(lookData) == "Vector3" then
		return lookData.Unit
	elseif typeof(lookData) == "table" then
		return Vector3.new(lookData.X or 0, lookData.Y or 0, lookData.Z or 1).Unit
	end
	return Vector3.new(0, 0, 1)
end

--------------------------------------------------------------------------------
-- VFX Helpers
--------------------------------------------------------------------------------

local function playBiteVFX(konModel, position)
	-- Bite impact particles/sound
	-- TODO: Add your actual bite VFX here
	-- Example:
	-- local biteEmitter = konModel:FindFirstChild("BiteParticles", true)
	-- if biteEmitter and biteEmitter:IsA("ParticleEmitter") then
	--     biteEmitter:Emit(20)
	-- end
	
	print("[Kon VFX] Bite VFX at", position)
end

local function playSmokeVFX(konModel, position)
	-- Smoke/poof particles when Kon disappears
	-- TODO: Add your actual smoke VFX here
	-- Example:
	-- local smokeEmitter = konModel:FindFirstChild("SmokeEmitter", true)
	-- if smokeEmitter and smokeEmitter:IsA("ParticleEmitter") then
	--     smokeEmitter:Emit(30)
	-- end
	
	print("[Kon VFX] Smoke VFX at", position)
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
	local targetCFrame = CFrame.lookAt(position, position + lookVector)

	-- Get template
	local template = getKonTemplate()
	if not template then
		warn("[Kon VFX] Kon model not found! Add it as a child of this script.")
		-- Create debug placeholder
		local placeholder = Instance.new("Part")
		placeholder.Name = "Kon_DEBUG_" .. originUserId
		placeholder.Size = Vector3.new(4, 4, 4)
		placeholder.CFrame = targetCFrame
		placeholder.Anchored = true
		placeholder.CanCollide = false
		placeholder.CanQuery = false
		placeholder.Transparency = 0.3
		placeholder.Color = Color3.fromRGB(255, 100, 0)
		placeholder.Shape = Enum.PartType.Ball
		placeholder.Parent = getEffectsFolder()
		
		-- Auto-cleanup placeholder
		task.delay(TIMING.KON_LIFETIME, function()
			if placeholder and placeholder.Parent then
				placeholder:Destroy()
			end
		end)
		return
	end

	-- Clone and position
	local konModel = template:Clone()
	konModel.Name = "Kon_" .. originUserId

	if konModel.PrimaryPart then
		konModel:SetPrimaryPartCFrame(targetCFrame)
	else
		konModel:PivotTo(targetCFrame)
	end

	konModel.Parent = getEffectsFolder()
	self._activeKons[originUserId] = konModel

	print("[Kon VFX] Spawned Kon for", originUserId, "at", position)

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
		
		playBiteVFX(konModel, position)
	end)

	----------------------------------------------------------------
	-- SMOKE VFX - triggers at SMOKE_DELAY
	----------------------------------------------------------------
	task.delay(TIMING.SMOKE_DELAY, function()
		if not konModel or not konModel.Parent then return end
		if self._activeKons[originUserId] ~= konModel then return end
		
		playSmokeVFX(konModel, position)
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
