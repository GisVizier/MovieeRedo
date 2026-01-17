local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionManager = require(ReplicatedStorage.CoreUI.ConnectionManager)
local CrosshairSystem = ReplicatedStorage:WaitForChild("Systems"):WaitForChild("Crosshair")
local CrosshairsFolder = CrosshairSystem:WaitForChild("Crosshairs")

local ServiceRegistry = nil
local function getServiceRegistry()
	if not ServiceRegistry then
		ServiceRegistry = require(ReplicatedStorage:WaitForChild("Utils").ServiceRegistry)
	end
	return ServiceRegistry
end

local CrosshairController = {}
CrosshairController.__index = CrosshairController

CrosshairController.Mock = {
	weaponData = {
		spreadX = 2,
		spreadY = 2,
		recoilMultiplier = 1.5,
	},
	customization = {
		showDot = true,
		showTopLine = true,
		showBottomLine = true,
		showLeftLine = true,
		showRightLine = true,
		lineThickness = 2,
		lineLength = 10,
		gapFromCenter = 5,
		dotSize = 2,
		rotation = 0,
		cornerRadius = 0,
		mainColor = Color3.fromRGB(255, 255, 255),
		outlineColor = Color3.fromRGB(0, 0, 0),
		outlineThickness = 1,
		opacity = 1,
		scale = 1,
		dynamicSpreadEnabled = true,
	},
	player = nil,
	character = nil,
}

function CrosshairController.new(player: Player?)
	local self = setmetatable({}, CrosshairController)

	self._player = player or CrosshairController.Mock.player or Players.LocalPlayer
	self._connections = ConnectionManager.new()
	self._module = nil
	self._frame = nil
	self._weaponData = nil
	self._customization = nil
	self._rootPart = nil
	self._updateConnection = nil
	self._screenGui = nil
	self._templateContainer = nil

	self:_bindCharacter()

	return self
end

function CrosshairController:_bindCharacter()
	if not self._player then
		return
	end

	self._connections:track(self._player, "CharacterAdded", function(character)
		self._rootPart = character:FindFirstChild("HumanoidRootPart")
	end, "character")

	local character = self._player.Character or CrosshairController.Mock.character
	if character then
		self._rootPart = character:FindFirstChild("HumanoidRootPart")
	end
end

function CrosshairController:_resolveGui()
	if not self._player then
		warn("[CrosshairController] No player set")
		return nil
	end

	if self._screenGui and self._templateContainer then
		return self._templateContainer
	end

	local playerGui = self._player:FindFirstChild("PlayerGui")
	if not playerGui then
		warn("[CrosshairController] PlayerGui not found")
		return nil
	end

	local screenGui = playerGui:WaitForChild("Crosshair", 5)
	if not screenGui then
		warn("[CrosshairController] Crosshair ScreenGui not found in PlayerGui")
		return nil
	end

	local container = screenGui:WaitForChild("Frame", 5)
	if not container then
		warn("[CrosshairController] Frame container not found in Crosshair ScreenGui")
		return nil
	end

	self._screenGui = screenGui
	self._templateContainer = container

	return container
end

function CrosshairController:_loadModule(crosshairName: string)
	local moduleScript = CrosshairsFolder:FindFirstChild(crosshairName)
	if not moduleScript then
		warn("[CrosshairController] Crosshair module missing:", crosshairName)
		return nil
	end

	local ok, moduleDef = pcall(require, moduleScript)
	if not ok then
		warn("[CrosshairController] Failed to require module:", crosshairName, moduleDef)
		return nil
	end

	return moduleDef
end

function CrosshairController:ApplyCrosshair(crosshairName: string, weaponData: any?, player: Player?)
	if player then
		self._player = player
		self:_bindCharacter()
	end

	self:RemoveCrosshair()

	local container = self:_resolveGui()
	if not container then
		warn("[CrosshairController] Crosshair templates not found.")
		return
	end

	local template = container:FindFirstChild(crosshairName)
	if not template then
		warn("[CrosshairController] Crosshair template missing:", crosshairName)
		return
	end

	local moduleDef = self:_loadModule(crosshairName)
	if not moduleDef then
		return
	end

	local clone = template:Clone()
	clone.Visible = true
	clone.Parent = self._screenGui

	local moduleInstance = moduleDef.new(clone)
	if not moduleInstance then
		clone:Destroy()
		return
	end

	self._frame = clone
	self._module = moduleInstance
	self._weaponData = weaponData or CrosshairController.Mock.weaponData
	self._customization = self._customization or CrosshairController.Mock.customization

	if moduleInstance.ApplyCustomization then
		moduleInstance:ApplyCustomization(self._customization)
	end

	self:_startUpdateLoop()
end

function CrosshairController:RemoveCrosshair()
	if self._updateConnection then
		self._updateConnection:Disconnect()
		self._updateConnection = nil
	end

	if self._frame then
		self._frame:Destroy()
		self._frame = nil
	end

	self._module = nil
	self._weaponData = nil
end

function CrosshairController:_startUpdateLoop()
	if self._updateConnection then
		return
	end

	self._updateConnection = RunService.RenderStepped:Connect(function(dt)
		self:_update(dt)
	end)
end

function CrosshairController:_getVelocity()
	-- Always get PrimaryPart fresh from CharacterController (don't cache - it changes)
	local characterController = getServiceRegistry():GetController("CharacterController")
	
	local rootPart = nil
	if characterController and characterController.PrimaryPart then
		rootPart = characterController.PrimaryPart
	else
		-- Fallback to player.Character
		local character = self._player and self._player.Character
		if character then
			rootPart = character:FindFirstChild("HumanoidRootPart")
		end
	end

	if not rootPart then
		return Vector3.zero, 0
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	return velocity, speed
end

function CrosshairController:_update(dt: number)
	if not self._module then
		return
	end

	local velocity, speed = self:_getVelocity()
	local state = {
		velocity = velocity,
		speed = speed,
		weaponData = self._weaponData,
		customization = self._customization,
		dt = dt,
	}

	self._module:Update(dt, state)
end

function CrosshairController:OnRecoil(recoilData: any)
	if not self._module then
		return
	end

	self._module:OnRecoil(recoilData, self._weaponData)
end

function CrosshairController:SetCustomization(customizationData: any)
	self._customization = customizationData or self._customization
	if self._module and self._module.ApplyCustomization and self._customization then
		self._module:ApplyCustomization(self._customization)
	end
end

function CrosshairController:Destroy()
	self:RemoveCrosshair()
	self._connections:cleanupAll()
	self._connections:destroy()
end

return CrosshairController
