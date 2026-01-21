local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Signal = require(script.Signal)
local ConnectionManager = require(script.ConnectionManager)
local TweenLibrary = require(script.TweenLibrary)

local CoreUI = {}
CoreUI.__index = CoreUI

local PROPERTY_MAP = {
	GuiObject = {"Size", "Position", "Rotation", "AnchorPoint", "Visible", "BackgroundTransparency", "BackgroundColor3"},
	CanvasGroup = {"GroupTransparency", "GroupColor3"},
	ImageLabel = {"ImageTransparency", "ImageColor3"},
	ImageButton = {"ImageTransparency", "ImageColor3"},
	TextLabel = {"TextTransparency", "TextColor3"},
	TextButton = {"TextTransparency", "TextColor3"},
	UIScale = {"Scale"},
	UIStroke = {"Transparency", "Color", "Thickness"},
	UIGradient = {"Offset", "Rotation"},
	ScrollingFrame = {"CanvasPosition", "ScrollBarImageTransparency"},
}

local NON_TWEENABLE = {
	Visible = true,
	AnchorPoint = true,
}

local function getPropertiesForInstance(instance)
	local properties = {}

	for className, props in PROPERTY_MAP do
		if instance:IsA(className) then
			for _, prop in props do
				if not table.find(properties, prop) then
					table.insert(properties, prop)
				end
			end
		end
	end

	return properties
end

local function captureOriginals(instance)
	local originals = {}
	local properties = getPropertiesForInstance(instance)

	for _, prop in properties do
		local success, value = pcall(function()
			return instance[prop]
		end)

		if success then
			originals[prop] = value
		end
	end

	return originals
end

local function applyOriginals(instance, originals, tweenInfo)
	if not originals or not next(originals) then
		return nil
	end

	if tweenInfo then
		local tweenableProps = {}
		local instantProps = {}

		for prop, value in originals do
			if NON_TWEENABLE[prop] then
				instantProps[prop] = value
			else
				tweenableProps[prop] = value
			end
		end

		for prop, value in instantProps do
			pcall(function()
				instance[prop] = value
			end)
		end

		if next(tweenableProps) then
			local tween = TweenService:Create(instance, tweenInfo, tweenableProps)
			tween:Play()
			return tween
		end
	else
		for prop, value in originals do
			pcall(function()
				instance[prop] = value
			end)
		end
	end

	return nil
end

local function shouldCapture(instance)
	return instance:IsA("GuiObject") 
		or instance:IsA("UIScale") 
		or instance:IsA("UIStroke") 
		or instance:IsA("UIGradient")
end

function CoreUI.new(screenGui)
	local self = setmetatable({}, CoreUI)

	self._screenGui = screenGui
	self._modules = {}
	self._moduleStates = {}
	self._events = {}
	self._connections = ConnectionManager.new()
	self._tween = TweenLibrary.new(self._connections)
	self._originals = {}
	self._elementData = {}

	self.onModuleShow = Signal.new()
	self.onModuleHide = Signal.new()
	self.onModuleReady = Signal.new()

	return self
end

function CoreUI:_captureElement(instance, path)
	local captured = captureOriginals(instance)
	self._originals[path] = captured
	self._elementData[path] = {
		instance = instance,
		originals = captured,
	}
end

function CoreUI:_captureDeep(root, basePath)
	local path = basePath or root.Name

	self:_captureElement(root, path)

	for _, child in root:GetDescendants() do
		if shouldCapture(child) then
			local childPath = path .. "." .. self:_getRelativePath(root, child)
			self:_captureElement(child, childPath)
		end
	end
end

function CoreUI:_getRelativePath(root, descendant)
	local parts = {}
	local current = descendant

	while current and current ~= root do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end

	return table.concat(parts, ".")
end

function CoreUI:_captureUI(ui, moduleName)
	self:_captureElement(ui, moduleName)

	for _, child in ui:GetChildren() do
		if shouldCapture(child) then
			self:_captureDeep(child, moduleName .. "." .. child.Name)
		end
	end
end

function CoreUI:getOriginals(path)
	return self._originals[path]
end

function CoreUI:getElementData(path)
	return self._elementData[path]
end

function CoreUI:resetToOriginals(path, tweenInfo)
	local data = self._elementData[path]
	if not data then
		warn("[CoreUI] No originals found for path:", path)
		return nil
	end

	return applyOriginals(data.instance, data.originals, tweenInfo)
end

function CoreUI:resetGroupToOriginals(groupPrefix, tweenInfo)
	local tweens = {}

	for path, data in self._elementData do
		if string.sub(path, 1, #groupPrefix) == groupPrefix then
			local tween = applyOriginals(data.instance, data.originals, tweenInfo)
			if tween then
				table.insert(tweens, tween)
			end
		end
	end

	return tweens
end

function CoreUI:resetModuleToOriginals(moduleName, tweenInfo)
	return self:resetGroupToOriginals(moduleName .. ".", tweenInfo)
end

function CoreUI:updateOriginals(path, properties)
	if not self._originals[path] then
		self._originals[path] = {}
	end

	for prop, value in properties do
		self._originals[path][prop] = value
	end

	local data = self._elementData[path]
	if data then
		data.originals = self._originals[path]
	end
end

function CoreUI:recaptureOriginals(path)
	local data = self._elementData[path]
	if not data then
		return
	end

	local captured = captureOriginals(data.instance)
	self._originals[path] = captured
	data.originals = captured
end

function CoreUI:recaptureModule(moduleName)
	local moduleData = self._modules[moduleName]
	if not moduleData then
		return
	end

	self:_captureUI(moduleData.ui, moduleName)
end

function CoreUI:applyToElement(path, properties, tweenInfo)
	local data = self._elementData[path]
	if not data then
		warn("[CoreUI] Element not found:", path)
		return nil
	end

	return applyOriginals(data.instance, properties, tweenInfo)
end

function CoreUI:getInstance(path)
	local data = self._elementData[path]
	return data and data.instance
end

function CoreUI:_discoverModules()
	local modulesFolder = script:FindFirstChild("Modules")
	if not modulesFolder then
		warn("[CoreUI] No Modules folder found")
		return {}
	end

	local discovered = {}
	for _, moduleScript in modulesFolder:GetChildren() do
		if moduleScript:IsA("ModuleScript") then
			discovered[moduleScript.Name] = moduleScript
		elseif moduleScript:IsA("Folder") then
			local initScript = moduleScript:FindFirstChild("init")
			if initScript and initScript:IsA("ModuleScript") then
				discovered[moduleScript.Name] = initScript
			end
		end
	end

	return discovered
end

function CoreUI:_findUI(name)
	return self._screenGui:FindFirstChild(name, true)
end

function CoreUI:_createExport(moduleName)
	local moduleConnections = ConnectionManager.new()

	return {
		tween = self._tween,
		connections = moduleConnections,

		emit = function(_, eventName, ...)
			self:emit(eventName, ...)
		end,

		on = function(_, eventName, callback)
			return self:on(eventName, callback)
		end,

		getModule = function(_, name)
			return self._modules[name] and self._modules[name].instance
		end,

		isOpen = function(_, name)
			local targetName = name or moduleName
			return self._moduleStates[targetName] == true
		end,

		show = function(_, name, force)
			self:show(name or moduleName, force)
		end,

		hide = function(_, name)
			self:hide(name or moduleName)
		end,

		setModuleState = function(_, name, state)
			local targetName = name or moduleName
			self:setModuleState(targetName, state)
		end,

		getOriginals = function(_, path)
			local fullPath = moduleName .. "." .. path
			return self:getOriginals(fullPath)
		end,

		getOriginalsRaw = function(_, path)
			return self:getOriginals(path)
		end,

		resetToOriginals = function(_, path, tweenInfo)
			local fullPath = moduleName .. "." .. path
			return self:resetToOriginals(fullPath, tweenInfo)
		end,

		resetGroupToOriginals = function(_, groupPrefix, tweenInfo)
			local fullPath = moduleName .. "." .. groupPrefix
			return self:resetGroupToOriginals(fullPath, tweenInfo)
		end,

		resetModuleToOriginals = function(_, tweenInfo)
			return self:resetModuleToOriginals(moduleName, tweenInfo)
		end,

		updateOriginals = function(_, path, properties)
			local fullPath = moduleName .. "." .. path
			self:updateOriginals(fullPath, properties)
		end,

		recaptureOriginals = function(_, path)
			local fullPath = moduleName .. "." .. path
			self:recaptureOriginals(fullPath)
		end,

		applyToElement = function(_, path, properties, tweenInfo)
			local fullPath = moduleName .. "." .. path
			return self:applyToElement(fullPath, properties, tweenInfo)
		end,

		getInstance = function(_, path)
			local fullPath = moduleName .. "." .. path
			return self:getInstance(fullPath)
		end,
	}
end

function CoreUI:init()
	local discovered = self:_discoverModules()

	for name, moduleScript in discovered do
		local ui = self:_findUI(name)
		if not ui then
			warn("[CoreUI] No UI found for module:", name)
			continue
		end

		self:_captureUI(ui, name)

		local success, moduleData = pcall(require, moduleScript)
		if not success then
			warn("[CoreUI] Failed to require module:", name, moduleData)
			continue
		end

		local export = self:_createExport(name)
		local instance = moduleData.start(export, ui)

		self._modules[name] = {
			instance = instance,
			ui = ui,
			export = export,
			connections = export.connections,
		}

		self._moduleStates[name] = false
		self.onModuleReady:fire(name, instance)
	end

	return self
end

function CoreUI:on(eventName, callback)
	if not self._events[eventName] then
		self._events[eventName] = Signal.new()
	end

	return self._events[eventName]:connect(callback)
end

function CoreUI:emit(eventName, ...)
	local event = self._events[eventName]
	if event then
		event:fire(...)
	end
end

function CoreUI:setModuleState(moduleName, state)
	if not moduleName then
		return
	end

	if self._modules[moduleName] then
		self._moduleStates[moduleName] = state
	end
end

function CoreUI:show(moduleName, force)
	local moduleData = self._modules[moduleName]
	if not moduleData then
		warn("[CoreUI] Module not found:", moduleName)
		return
	end

	if self._moduleStates[moduleName] and not force then
		return
	end
	
	self._moduleStates[moduleName] = true

	local instance = moduleData.instance
	if instance.show then
		task.spawn(instance.show, instance)
	end

	self.onModuleShow:fire(moduleName, instance)
	self:emit("Show" .. moduleName)
end

function CoreUI:hide(moduleName)
	local moduleData = self._modules[moduleName]
	if not moduleData then
		warn("[CoreUI] Module not found:", moduleName)
		return
	end

	if not self._moduleStates[moduleName] then
		return
	end

	local instance = moduleData.instance
	if instance.hide then
		local completed = instance:hide()

		if completed == true or completed == nil then
			self:_cleanupModule(moduleName)
		end
	else
		self:_cleanupModule(moduleName)
	end
end

function CoreUI:_cleanupModule(moduleName)
	local moduleData = self._modules[moduleName]
	if not moduleData then
		return
	end

	self._moduleStates[moduleName] = false

	moduleData.connections:cleanupAll()

	local instance = moduleData.instance
	if instance._cleanup then
		instance:_cleanup()
	end

	self.onModuleHide:fire(moduleName, instance)
	self:emit("Hide" .. moduleName)
end

function CoreUI:isOpen(moduleName)
	return self._moduleStates[moduleName] == true
end

function CoreUI:getModule(moduleName)
	local moduleData = self._modules[moduleName]
	return moduleData and moduleData.instance
end

function CoreUI:getUI(moduleName)
	local moduleData = self._modules[moduleName]
	return moduleData and moduleData.ui
end

function CoreUI:hideAll()
	for name in self._modules do
		if self._moduleStates[name] then
			self:hide(name)
		end
	end
end

function CoreUI:cleanAll()
	for name in self._modules do
		if self._moduleStates[name] then
			self:_cleanup(name)
		end
	end
end

function CoreUI:destroy()
	self:hideAll()
	self:cleanAll()

	for _, event in self._events do
		event:destroy()
	end

	self.onModuleShow:destroy()
	self.onModuleHide:destroy()
	self.onModuleReady:destroy()

	self._connections:destroy()
	self._tween:destroy()

	table.clear(self._modules)
	table.clear(self._events)
	table.clear(self._originals)
	table.clear(self._elementData)

	setmetatable(self, nil)
end

return CoreUI
