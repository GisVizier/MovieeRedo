--[[
	Default.lua
	Default tracer VFX - attaches effects to the projectile attachment
	
	The projectile system moves the attachment along the path.
	This module just provides the visual effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CharacterLocations = require(ReplicatedStorage:WaitForChild("Game"):WaitForChild("Character"):WaitForChild("CharacterLocations"))

local Default = {}
Default.Id = "Default"
Default.Name = "Default Tracer"

-- Highlight config
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 100, 100)
local HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 50, 50)
local HIGHLIGHT_DURATION = 0.15
local HIGHLIGHT_FADE_TIME = 0.1

--[[
	Muzzle flash effect
	@param origin Vector3 - Barrel position
	@param gunModel Model? - The weapon model
	@param attachment Attachment - Tracer attachment for VFX
]]
function Default:Muzzle(origin: Vector3, gunModel: Model?, attachment: Attachment)
	-- TODO: Add muzzle flash ParticleEmitter/PointLight to attachment
end

--[[
	Finds the appearance rig to highlight for a character
	- Dummies: rig is character:FindFirstChild("Rig")
	- Players: rig is in workspace.Rigs/<PlayerName>_Rig
]]
local function findRigToHighlight(character: Model): Instance?
	if not character then return nil end
	
	-- Check for dummy rig (directly on character)
	local dummyRig = character:FindFirstChild("Rig")
	if dummyRig then
		return dummyRig
	end
	
	-- For players: use CharacterLocations to get the proper appearance rig
	local playerRig = CharacterLocations.GetRigFromCharacter(character)
	if playerRig then
		return playerRig
	end
	
	-- Fallback: check workspace.Rigs manually by name
	local rigsFolder = Workspace:FindFirstChild("Rigs")
	if rigsFolder then
		local ownerName = character:GetAttribute("OwnerName") or character.Name
		local rigName = ownerName .. "_Rig"
		local foundRig = rigsFolder:FindFirstChild(rigName)
		if foundRig then return foundRig end
	end
	
	-- Last fallback: the character itself
	return character
end

--[[
	Hit player effect - highlight with smooth tween
	@param hitPosition Vector3
	@param hitPart BasePart
	@param targetCharacter Model
	@param attachment Attachment
]]
function Default:HitPlayer(hitPosition: Vector3, hitPart: BasePart, targetCharacter: Model, attachment: Attachment)
	if not targetCharacter then return end

	local rigToHighlight = findRigToHighlight(targetCharacter)
	if not rigToHighlight then return end

	local existingHighlight = rigToHighlight:FindFirstChildOfClass("Highlight")
	if existingHighlight then
		existingHighlight:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Adornee = rigToHighlight
	highlight.FillColor = HIGHLIGHT_COLOR
	highlight.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = rigToHighlight

	local tweenIn = TweenService:Create(
		highlight,
		TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 0.5, OutlineTransparency = 0 }
	)
	tweenIn:Play()

	task.delay(HIGHLIGHT_DURATION, function()
		if not highlight or not highlight.Parent then return end

		local tweenOut = TweenService:Create(
			highlight,
			TweenInfo.new(HIGHLIGHT_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ FillTransparency = 1, OutlineTransparency = 1 }
		)
		tweenOut:Play()
		tweenOut.Completed:Once(function()
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
		end)
	end)
	
	-- TODO: Add impact particle to attachment
end

--[[
	Hit world effect - impact VFX
	@param hitPosition Vector3
	@param hitNormal Vector3
	@param hitPart BasePart
	@param attachment Attachment
]]
function Default:HitWorld(hitPosition: Vector3, hitNormal: Vector3, hitPart: BasePart, attachment: Attachment)
	-- TODO: Add impact particles/decal to attachment
end

return Default
