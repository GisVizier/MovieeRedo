--[[
	ADSOverlay.lua

	Manages ADS (Aim Down Sights) GUI overlay frames.
	Shows/hides children inside StarterGui > Ads > Frame when the player enters/exits ADS.

	Structure expected in StarterGui:
		Ads (ScreenGui)
		  └─ Frame (container)
		       ├─ Default (ImageLabel / CanvasGroup, Visible=false)
		       ├─ Sniper  (CanvasGroup, Visible=false)
		       └─ ...

	Usage:
		ADSOverlay:Start(weaponId, skinId)  -- show overlay
		ADSOverlay:End()                    -- hide overlay

	Lookup order for overlay key:
		1. ViewmodelConfig.Skins[weaponId][skinId].ADSOverlay
		2. ViewmodelConfig.Weapons[weaponId].ADSOverlay
		3. ViewmodelConfig.ADSOverlayDefault
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

local LocalPlayer = Players.LocalPlayer

local FADE_IN_TIME = 0.15
local FADE_OUT_TIME = 0.1
local SCOPE_SWAY_TIME = 0.85
local SCOPE_SWAY_OFFSET = 0.5 -- max random offset in scale
local DEBUG = false

local ADSOverlay = {}
ADSOverlay._activeFrame = nil
ADSOverlay._container = nil -- Ads > Frame
ADSOverlay._activeTween = nil
ADSOverlay._scopeSwayTween = nil
ADSOverlay._scopeSwayFrame = nil

-- =====================================================================
-- PRIVATE
-- =====================================================================

local function log(...)
	if DEBUG then
		warn("[ADSOverlay]", ...)
	end
end

function ADSOverlay:_getContainer()
	if self._container and self._container.Parent then
		log("Container cached:", self._container:GetFullName())
		return self._container
	end

	local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		log("FAIL: No PlayerGui found")
		return nil
	end

	-- Look for the ScreenGui named "Ads", then the container Frame inside it
	local adsGui = playerGui:FindFirstChild("Ads")
	log("PlayerGui.Ads found:", adsGui ~= nil)

	-- If not in PlayerGui yet, clone from StarterGui
	if not adsGui then
		log("Not in PlayerGui, trying to clone from StarterGui...")
		local starterGui = game:GetService("StarterGui")
		local template = starterGui:FindFirstChild("Ads")
		log("StarterGui.Ads template found:", template ~= nil)
		if template then
			adsGui = template:Clone()
			adsGui.Parent = playerGui
			log("Cloned Ads to PlayerGui")
		end
	end

	if not adsGui then
		log("FAIL: Could not find or clone Ads ScreenGui")
		return nil
	end

	local container = adsGui:FindFirstChild("Frame")
	log("Ads.Frame container found:", container ~= nil)
	if container then
		log("Container children:")
		for _, child in container:GetChildren() do
			if child:IsA("GuiObject") then
				log("  -", child.Name, "(" .. child.ClassName .. ") Visible=" .. tostring(child.Visible))
			else
				log("  -", child.Name, "(" .. child.ClassName .. ")")
			end
		end
	end

	self._container = container
	return container
end

function ADSOverlay:_resolveOverlayKey(weaponId, skinId)
	log("Resolving overlay for weaponId=", tostring(weaponId), "skinId=", tostring(skinId))

	-- 1. Skin-specific override
	if skinId and skinId ~= "" and ViewmodelConfig.Skins then
		local weaponSkins = ViewmodelConfig.Skins[weaponId]
		local skinCfg = weaponSkins and weaponSkins[skinId]
		if skinCfg and skinCfg.ADSOverlay then
			log("Resolved via skin override:", skinCfg.ADSOverlay)
			return skinCfg.ADSOverlay
		end
	end

	-- 2. Weapon-specific
	local weaponCfg = ViewmodelConfig.Weapons and ViewmodelConfig.Weapons[weaponId]
	if weaponCfg and weaponCfg.ADSOverlay then
		log("Resolved via weapon config:", weaponCfg.ADSOverlay)
		return weaponCfg.ADSOverlay
	end

	-- 3. Global default
	local defaultKey = ViewmodelConfig.ADSOverlayDefault or "Default"
	log("Resolved via default:", defaultKey)
	return defaultKey
end

function ADSOverlay:_cancelTween()
	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end
	if self._scopeSwayTween then
		self._scopeSwayTween:Cancel()
		self._scopeSwayTween = nil
	end
	-- Reset scope sway frame to center if it was mid-tween
	if self._scopeSwayFrame then
		self._scopeSwayFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		self._scopeSwayFrame = nil
	end
end

function ADSOverlay:_playScopeSway(overlayFrame)
	-- Look for a child Frame inside the overlay to sway (the reticle/scope content)
	local scopeFrame = overlayFrame:FindFirstChild("Frame")
	if not scopeFrame or not scopeFrame:IsA("GuiObject") then
		return
	end

	-- Random offset from center
	local offsetX = (math.random() * 2 - 1) * SCOPE_SWAY_OFFSET
	local offsetY = (math.random() * 2 - 1) * SCOPE_SWAY_OFFSET

	-- Start at random offset
	scopeFrame.Position = UDim2.new(0.5 + offsetX, 0, 0.5 + offsetY, 0)
	self._scopeSwayFrame = scopeFrame

	-- Bounce back to center
	local tweenInfo = TweenInfo.new(SCOPE_SWAY_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	self._scopeSwayTween = TweenService:Create(scopeFrame, tweenInfo, {
		Position = UDim2.new(0.5, 0, 0.5, 0),
	})
	self._scopeSwayTween:Play()
end

function ADSOverlay:_fadeIn(frame)
	self:_cancelTween()
	frame.Visible = true
	log("FadeIn:", frame.Name, "(" .. frame.ClassName .. ")")

	-- CanvasGroup: tween GroupTransparency for smooth fade
	if frame:IsA("CanvasGroup") then
		frame.GroupTransparency = 1
		local tweenInfo = TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		self._activeTween = TweenService:Create(frame, tweenInfo, { GroupTransparency = 0 })
		self._activeTween:Play()

		-- Scope sway: random offset → bounce to center
		self:_playScopeSway(frame)
	elseif frame:IsA("ImageLabel") then
		-- ImageLabel: tween ImageTransparency
		local targetTransparency = tonumber(frame:GetAttribute("TargetImageTransparency")) or frame.ImageTransparency
		log("ImageLabel target transparency:", targetTransparency)
		frame.ImageTransparency = 1
		local tweenInfo = TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		self._activeTween = TweenService:Create(frame, tweenInfo, { ImageTransparency = targetTransparency })
		self._activeTween:Play()
	else
		log("Unknown frame type, just toggled Visible")
	end
end

function ADSOverlay:_fadeOut(frame)
	self:_cancelTween()
	log("FadeOut:", frame.Name, "(" .. frame.ClassName .. ")")

	if frame:IsA("CanvasGroup") then
		local tweenInfo = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		self._activeTween = TweenService:Create(frame, tweenInfo, { GroupTransparency = 1 })
		self._activeTween.Completed:Once(function()
			frame.Visible = false
		end)
		self._activeTween:Play()
	elseif frame:IsA("ImageLabel") then
		local tweenInfo = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		self._activeTween = TweenService:Create(frame, tweenInfo, { ImageTransparency = 1 })
		self._activeTween.Completed:Once(function()
			frame.Visible = false
		end)
		self._activeTween:Play()
	else
		frame.Visible = false
	end
end

function ADSOverlay:_hideActive()
	if self._activeFrame then
		self:_fadeOut(self._activeFrame)
		self._activeFrame = nil
	else
		self:_cancelTween()
	end
end

-- =====================================================================
-- PUBLIC API
-- =====================================================================

function ADSOverlay:Start(weaponId, skinId)
	log("=== Start called ===  weaponId=", tostring(weaponId), "skinId=", tostring(skinId))
	self:_hideActive()

	local container = self:_getContainer()
	if not container then
		log("FAIL: No container, aborting Start")
		return
	end

	local overlayKey = self:_resolveOverlayKey(weaponId, skinId)
	if not overlayKey then
		log("FAIL: No overlay key resolved, aborting Start")
		return
	end

	local frame = container:FindFirstChild(overlayKey)
	log("Looking for child '" .. overlayKey .. "' in container:", frame ~= nil)
	if not frame then
		-- Fall back to Default if the specific frame doesn't exist
		if overlayKey ~= "Default" then
			frame = container:FindFirstChild("Default")
			log("Fell back to Default:", frame ~= nil)
		end
	end

	if not frame then
		log("FAIL: No frame found for key '" .. overlayKey .. "', aborting Start")
		return
	end

	self._activeFrame = frame
	self:_fadeIn(frame)
	return overlayKey
end

function ADSOverlay:End()
	log("=== End called ===")
	self:_hideActive()
end

return ADSOverlay
