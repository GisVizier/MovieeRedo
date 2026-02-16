local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
local ServiceRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("ServiceRegistry"))

-- Load EmoteService from Game/Emotes
local EmotesService = nil
local function getEmotesService()
	if not EmotesService then
		local Game = ReplicatedStorage:FindFirstChild("Game")
		if Game then
			local Emotes = Game:FindFirstChild("Emotes")
			if Emotes then
				EmotesService = require(Emotes)
			end
		end
	end
	return EmotesService
end

local Configs = ReplicatedStorage:WaitForChild("Configs")
local LoadoutConfig = require(Configs.LoadoutConfig)
local Signal = require(ReplicatedStorage.CoreUI.Signal)
local TweenConfig = require(script.TweenConfig)

local module = {}
module.__index = module

local ACTION_RADIAL = "EmotesRadial"
local ACTION_CONFIRM = "EmotesConfirm"
local DEADZONE = 0.025
local DEBUG = false

local function log(...)
	if not DEBUG then
		return
	end
end

local function angleDiff(a, b)
	local diff = math.atan2(math.sin(a - b), math.cos(a - b))
	return math.abs(diff)
end

function module.start(export, ui)
	local self = setmetatable({}, module)
	self._export = export
	self._ui = ui
	self._tween = export.tween
	self._connections = export.connections
	self._initialized = false

	self._slots = {}
	self._slotsByIndex = {}
	self._currentTweens = {}
	self._previewLoops = {}
	self._hoveredIndex = nil
	self._selectedSlot = nil
	self._selectedEmoteId = nil
	self._inputMode = nil

	self.onHover = Signal.new()
	self.onActivated = Signal.new()

	local main = ui:FindFirstChild("Emotes") or ui
	self._main = main
	self._rotate = main and main:FindFirstChild("Rotate", true) or nil
	self._rarityHolder = main and main:FindFirstChild("RarityHolder", true) or nil
	self._vmCamera = self._rarityHolder and self._rarityHolder:FindFirstChild("VMCamera") or nil
	self._infoFrame = main and (main:FindFirstChild("Info", true) or main:FindFirstChild("Name", true)) or nil
	self._infoName = self._infoFrame and self._infoFrame:FindFirstChild("Aim", true) or nil
	self._infoRarity = self._infoFrame and self._infoFrame:FindFirstChild("Rarity", true) or nil
	self._originalRarityColor = self._infoRarity and self._infoRarity.TextColor3 or Color3.fromRGB(255, 255, 255)
	self._rootScale = ui:FindFirstChild("UIScale") or (main and main:FindFirstChild("UIScale", true))
	self._bounceScale = main and main:FindFirstChild("animate", true) or nil
	self._originalRootScale = self._rootScale and self._rootScale.Scale or 1
	self._originalBounceScale = self._bounceScale and self._bounceScale.Scale or 1
	self._originalGroupTransparency = ui.GroupTransparency

	self:_collectSlots()

	return self
end

function module:_collectSlots()
	table.clear(self._slots)
	table.clear(self._slotsByIndex)

	if not self._rarityHolder then
		return
	end

	for i = 1, 8 do
		local frame = self._rarityHolder:FindFirstChild(tostring(i))
		local bar = frame and frame:FindFirstChild("Bar", true) or nil
		local button = frame and frame:FindFirstChild("button", true) or nil
		local viewport = frame and frame:FindFirstChild("ViewportFrame", true) or nil
		local viewportScale = viewport and viewport:FindFirstChild("UIScale", true) or nil
		local worldModel = viewport and viewport:FindFirstChild("WorldModel", true) or nil
		local rig = worldModel and worldModel:FindFirstChild("User", true) or nil
		local barTransparency = bar and bar.ImageTransparency or 1
		local hoverTransparency = math.max(barTransparency - 0.4, 0)
		local barColor = bar and bar.ImageColor3 or Color3.fromRGB(255, 255, 255)

		local slot = {
			index = i,
			frame = frame,
			bar = bar,
			button = button,
			viewport = viewport,
			viewportScale = viewportScale,
			worldModel = worldModel,
			rig = rig,
			barTransparency = barTransparency,
			hoverTransparency = hoverTransparency,
			barColor = barColor,
			angle = nil,
			emoteId = nil,
			previewActive = false,
		}

		self._slotsByIndex[i] = slot
		if frame then
			table.insert(self._slots, slot)
		end
	end
end

function module:_getCenter()
	local target = self._rotate or self._main or self._ui
	if not target then
		return nil
	end

	local pos = target.AbsolutePosition
	local size = target.AbsoluteSize
	return pos + (size / 2)
end

function module:_getRadius()
	local target = self._rotate or self._main or self._ui
	if not target then
		return 0
	end

	local size = target.AbsoluteSize
	return math.min(size.X, size.Y) * 0.5
end

function module:_refreshSlotAngles()
	local center = self:_getCenter()
	if not center then
		return
	end

	for _, slot in ipairs(self._slots) do
		if slot.frame then
			local pos = slot.frame.AbsolutePosition
			local size = slot.frame.AbsoluteSize
			local slotCenter = pos + (size / 2)
			slot.angle = math.atan2(slotCenter.Y - center.Y, slotCenter.X - center.X)
		end
	end
end

function module:_getClosestSlot(angle)
	local bestIndex = nil
	local bestDiff = math.huge

	for _, slot in ipairs(self._slots) do
		if slot.angle then
			local diff = angleDiff(angle, slot.angle)
			if diff < bestDiff then
				bestDiff = diff
				bestIndex = slot.index
			end
		end
	end

	return bestIndex
end

function module:_cancelTweens(key)
	local tweens = self._currentTweens[key]
	if tweens then
		for _, tween in tweens do
			tween:Cancel()
		end
	end
	self._currentTweens[key] = nil
end

function module:_cancelAllTweens()
	for key, tweens in self._currentTweens do
		for _, tween in tweens do
			tween:Cancel()
		end
		self._currentTweens[key] = nil
	end
end

function module:_tweenBar(slot, targetTransparency)
	if not slot or not slot.bar then
		return
	end

	local key = "bar_" .. slot.index
	self:_cancelTweens(key)

	local animType = targetTransparency < slot.barTransparency and "hover" or "unhover"
	local tween = TweenService:Create(slot.bar, TweenConfig.get("Bar", animType), {
		ImageTransparency = targetTransparency,
	})
	tween:Play()

	self._currentTweens[key] = {tween}
end

function module:_tweenViewportScale(slot, targetScale)
	if not slot or not slot.viewportScale then
		return
	end

	local key = "viewport_scale_" .. slot.index
	self:_cancelTweens(key)

	local tween = TweenService:Create(slot.viewportScale, TweenConfig.get("Scale", "show"), {
		Scale = targetScale,
	})
	tween:Play()

	self._currentTweens[key] = {tween}
end

function module:_setRotate(angle)
	if self._rotate then
		self._rotate.Rotation = math.deg(angle)
	end
end

function module:_applyViewportCamera(slot)
	if slot and slot.viewport and self._vmCamera then
		slot.viewport.CurrentCamera = self._vmCamera
	end
end

function module:_stopPreview(slot)
	local service = getEmotesService()
	if not slot or not slot.rig or not slot.emoteId or not service then
		return
	end
	if type(service.stopOnRig) == "function" then
		service.stopOnRig(slot.emoteId, slot.rig)
	end
end

function module:_startPreviewLoop(slot)
	local service = getEmotesService()
	if not slot or not slot.rig or not slot.emoteId or not service then
		return
	end
	self._previewLoops[slot.index] = true
	local currentEmoteId = slot.emoteId
	local rig = slot.rig

	task.spawn(function()
		local RESTART_DELAY = 1.5

		while self._previewLoops[slot.index] and slot.emoteId == currentEmoteId and rig.Parent do
			if type(service.stopOnRig) == "function" then
				service.stopOnRig(currentEmoteId, rig)
			end
			
			local played = false
			if type(service.playOnRig) == "function" then
				played = service.playOnRig(currentEmoteId, rig)
			end
			if not played then
				break
			end

			while self._previewLoops[slot.index] and slot.emoteId == currentEmoteId and rig.Parent do
				local bucket = service._activeByRig and service._activeByRig[rig]
				if not bucket or not bucket[currentEmoteId] then
					break
				end
				task.wait(0.05)
			end

			task.wait(RESTART_DELAY)
		end
	end)
end

function module:_stopPreviewLoop(slot)
	if not slot then
		return
	end
	self._previewLoops[slot.index] = nil
	local service = getEmotesService()
	if slot.emoteId and slot.rig and service and type(service.stopOnRig) == "function" then
		service.stopOnRig(slot.emoteId, slot.rig)
	end
end

function module:_updateInfo(emoteId)
	if not self._infoName or not self._infoRarity then
		return
	end

	if not emoteId then
		self._infoName.Text = "NONE"
		self._infoRarity.Text = ""
		self._infoRarity.TextColor3 = self._originalRarityColor
		return
	end

	local service = getEmotesService()
	local info = nil
	if service and type(service.getEmoteInfo) == "function" then
		local ok, result = pcall(service.getEmoteInfo, emoteId)
		if ok and result then
			info = result
		end
	end
	self._infoName.Text = info and info.displayName or tostring(emoteId)
	local rarity = info and info.rarity or self:getEmoteRarity(emoteId)
	self._infoRarity.Text = rarity or "RARITY"
	if rarity then
		self._infoRarity.TextColor3 = LoadoutConfig.getRarityColor(rarity)
	else
		self._infoRarity.TextColor3 = self._originalRarityColor
	end
end

function module:getEmoteRarity(emoteId)
	if not emoteId then
		return nil
	end
	local service = getEmotesService()
	if service and type(service.getEmoteRarity) == "function" then
		local ok, rarity = pcall(service.getEmoteRarity, emoteId)
		if ok then
			return rarity
		end
	end
	return nil
end

function module:_populateSlots()
	local equipped = {}
	if type(PlayerDataTable.getEquippedEmotes) == "function" then
		local ok, result = pcall(PlayerDataTable.getEquippedEmotes)
		if ok and typeof(result) == "table" then
			equipped = result
		end
	elseif type(PlayerDataTable.getData) == "function" then
		local ok, result = pcall(PlayerDataTable.getData, "EQUIPPED_EMOTES")
		if ok and typeof(result) == "table" then
			equipped = result
		end
	end

	local service = getEmotesService()

	for i = 1, 8 do
		local slot = self._slotsByIndex[i]
		if slot then
			local emoteId = equipped["Slot" .. i] or equipped[i]
			slot.emoteId = emoteId
			self:_applyViewportCamera(slot)

			local hasEmote = emoteId ~= nil
				and emoteId ~= ""
				and service
				and type(service.getEmoteClass) == "function"
				and service.getEmoteClass(emoteId) ~= nil
				and slot.rig ~= nil

			if slot.viewport then
				slot.viewport.Visible = hasEmote
			end
			if slot.frame then
				slot.frame.Visible = hasEmote
			end

			if hasEmote then
				self:_startPreviewLoop(slot)
			else
				self:_stopPreviewLoop(slot)
			end
		end
	end
end

function module:_setHover(index)
	if self._hoveredIndex == index then
		return
	end

	if self._hoveredIndex then
		local prevSlot = self._slotsByIndex[self._hoveredIndex]
		if prevSlot then
			self:_tweenBar(prevSlot, prevSlot.barTransparency)
			if prevSlot.viewportScale then
				self:_tweenViewportScale(prevSlot, 1)
			end
		end
	end

	self._hoveredIndex = index

	if not index then
		log("hover", "none")
		self._selectedSlot = nil
		self._selectedEmoteId = nil
		self:_updateInfo(nil)
		return
	end

	local slot = self._slotsByIndex[index]
	if not slot then
		return
	end

	self._selectedSlot = index
	self._selectedEmoteId = slot.emoteId
	log("hover", index, slot.emoteId)
	self:_tweenBar(slot, slot.hoverTransparency)
	if slot.bar then
		local rarity = self:getEmoteRarity(slot.emoteId)
		if rarity then
			slot.bar.ImageColor3 = LoadoutConfig.getRarityColor(rarity)
		end
	end
	if slot.viewportScale then
		self:_tweenViewportScale(slot, 1.35)
	end
	self:_updateInfo(slot.emoteId)
	self.onHover:fire(slot.emoteId, index)
end

function module:_updateFromMouse()
	local center = self:_getCenter()
	if not center then
		return
	end

	local mousePos = UserInputService:GetMouseLocation()
	local vec = mousePos - center
	local distance = vec.Magnitude
	local radius = self:_getRadius()

	if distance < radius * 0.2 then
		self:_setHover(nil)
		return
	end

	local angle = math.atan2(vec.Y, vec.X)
	local index = self:_getClosestSlot(angle)
	self:_setRotate(angle)
	self:_setHover(index)
end

function module:_updateFromStick(stickVector)
	local magnitude = stickVector.Magnitude
	if magnitude < DEADZONE then
		self:_setHover(nil)
		return
	end

	local angle = math.atan2(stickVector.Y, stickVector.X)
	local index = self:_getClosestSlot(angle)
	self:_setRotate(angle)
	self:_setHover(index)
end

function module:_activateHovered()
	if not self._hoveredIndex then
		log("activate", "none")
		return
	end

	local slot = self._slotsByIndex[self._hoveredIndex]
	local emoteId = slot and slot.emoteId or nil

	self._selectedSlot = self._hoveredIndex
	self._selectedEmoteId = emoteId
	log("activate", self._hoveredIndex, emoteId)
	
	-- Play the emote on the actual player
	local service = getEmotesService()
	if emoteId and service and type(service.play) == "function" then
		local success = service.play(emoteId)
	else
	end
	
	self.onActivated:fire(emoteId, self._hoveredIndex)
	self._export:emit("EmoteSelected", emoteId, self._hoveredIndex)
	self._export:hide("Emotes")
end

function module:_setupInputs()
	ContextActionService:BindAction(ACTION_RADIAL, function(_, _, inputObject)
		if inputObject and inputObject.Position then
			self._inputMode = "gamepad"
			self:_updateFromStick(inputObject.Position)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Thumbstick2)

	ContextActionService:BindAction(ACTION_CONFIRM, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:_activateHovered()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonA, Enum.KeyCode.Return)

	self._connections:track(UserInputService, "InputChanged", function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self._inputMode = "mouse"
			self:_updateFromMouse()
			return
		end

		if gameProcessed then
			return
		end
	end, "input")

	self._connections:track(UserInputService, "InputBegan", function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_activateHovered()
		end
	end, "input")
end

function module:_setupSlotButtons()
	for _, slot in ipairs(self._slots) do
		local button = slot.button
		if button then
			if button:IsA("GuiButton") then
				self._connections:track(button, "Activated", function()
					self:_setHover(slot.index)
					self:_activateHovered()
				end, "buttons")
			else
				self._connections:track(button, "InputBegan", function(input)
					if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
						self:_setHover(slot.index)
						self:_activateHovered()
					end
				end, "buttons")
			end
		end
	end
end

function module:_startBounce()
	return
end

function module:_stopBounce()
	return
end

function module:_init()
	if self._initialized then
		self:_refreshSlotAngles()
		return
	end

	self._initialized = true
	pcall(PlayerDataTable.init)
	
	local service = getEmotesService()
	if service and type(service.init) == "function" then
		pcall(service.init)
	end
	
	self:_refreshSlotAngles()
	self:_setupInputs()
	self:_setupSlotButtons()
end

function module:show()
	self._ui.Visible = true
	self:_init()
	self:_populateSlots()
	
	-- Unlock mouse for selection
	self._savedMouseBehavior = UserInputService.MouseBehavior
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	
	-- Hide crosshair while emote wheel is open
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.HideCrosshair then
		weaponController:HideCrosshair()
	end

	self:_cancelAllTweens()
	self:_setHover(nil)
	self:_updateInfo(nil)

	self._ui.GroupTransparency = 1
	if self._rootScale then
		self._rootScale.Scale = self._originalRootScale * 0.9
	end

	local fadeTween = TweenService:Create(self._ui, TweenConfig.get("Root", "show"), {
		GroupTransparency = self._originalGroupTransparency,
	})
	fadeTween:Play()

	if self._rootScale then
		local scaleTween = TweenService:Create(self._rootScale, TweenConfig.get("Scale", "show"), {
			Scale = self._originalRootScale,
		})
		scaleTween:Play()
		self._currentTweens["root_scale"] = {scaleTween}
	end

	self._currentTweens["root_fade"] = {fadeTween}

	return true
end

function module:hide()
	-- Restore mouse behavior
	if self._savedMouseBehavior then
		UserInputService.MouseBehavior = self._savedMouseBehavior
		self._savedMouseBehavior = nil
	end
	
	-- Restore crosshair visibility
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.RestoreCrosshair then
		weaponController:RestoreCrosshair()
	end
	
	self:_cancelAllTweens()
	for _, slot in self._slotsByIndex do
		self:_stopPreviewLoop(slot)
	end

	local fadeTween = TweenService:Create(self._ui, TweenConfig.get("Root", "hide"), {
		GroupTransparency = 1,
	})
	fadeTween:Play()
	self._currentTweens["root_fade"] = {fadeTween}

	if self._rootScale then
		local scaleTween = TweenService:Create(self._rootScale, TweenConfig.get("Scale", "hide"), {
			Scale = self._originalRootScale * 0.9,
		})
		scaleTween:Play()
		self._currentTweens["root_scale"] = {scaleTween}
	end

	fadeTween.Completed:Wait()
	self._ui.Visible = false

	return true
end

function module:_cleanup()
	self._initialized = false

	ContextActionService:UnbindAction(ACTION_RADIAL)
	ContextActionService:UnbindAction(ACTION_CONFIRM)

	self._connections:cleanupAll()
	self:_cancelAllTweens()
	self:_setHover(nil)
	for _, slot in self._slotsByIndex do
		self:_stopPreviewLoop(slot)
	end
end

return module
