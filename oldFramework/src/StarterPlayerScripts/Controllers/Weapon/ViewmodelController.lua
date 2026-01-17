local ViewmodelController = {}

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)
local Log = require(Locations.Modules.Systems.Core.LogService)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

ViewmodelController.CurrentViewmodel = nil
ViewmodelController.CurrentWeaponName = nil
ViewmodelController.Config = nil
ViewmodelController.RenderConnection = nil

ViewmodelController.ViewmodelEffects = nil
ViewmodelController.ViewmodelAnimator = nil
ViewmodelController.ViewmodelAppearance = nil
ViewmodelController.ArmReplicator = nil

ViewmodelController.CurrentViewmodelCFrame = nil

function ViewmodelController:Init()
	Log:RegisterCategory("VIEWMODEL", "Viewmodel rendering and management")

	local systemsFolder = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Systems")
	local viewmodelFolder = systemsFolder:WaitForChild("Viewmodel")

	self.ViewmodelEffects = require(viewmodelFolder:WaitForChild("ViewmodelEffects"))
	self.ViewmodelAnimator = require(viewmodelFolder:WaitForChild("ViewmodelAnimator"))
	self.ViewmodelAppearance = require(viewmodelFolder:WaitForChild("ViewmodelAppearance"))
	self.ArmReplicator = require(viewmodelFolder:WaitForChild("ArmReplicator"))

	self.ViewmodelEffects:Init(self)
	self.ViewmodelAnimator:Init(self)
	self.ViewmodelAppearance:Init()
	self.ArmReplicator:Init()

	Log:Info("VIEWMODEL", "ViewmodelController initialized")
end

function ViewmodelController:Create(player, weaponName)
	print("[VIEWMODEL DEBUG] Create called with weaponName:", weaponName)
	
	-- Debug: List all available weapons
	print("[VIEWMODEL DEBUG] Available weapons in ViewmodelConfig.Weapons:")
	for name, _ in pairs(ViewmodelConfig.Weapons) do
		print("  -", name)
	end
	
	if self.CurrentViewmodel then
		self:DestroyViewmodel()
	end

	local config = ViewmodelConfig:GetResolvedConfig(weaponName, "Default")
	if not config then
		print("[VIEWMODEL DEBUG] No config found for weapon:", weaponName)
		Log:Error("VIEWMODEL", "No config found for weapon", { Weapon = weaponName })
		return nil
	end

	local viewmodel = self:LoadViewmodel(config.ModelPath)
	if not viewmodel then
		return nil
	end

	self.ViewmodelAppearance:ApplyPlayerAppearance(viewmodel, player)

	viewmodel.Parent = Camera

	self:ApplyHighlight(viewmodel)

	self.CurrentViewmodel = viewmodel
	self.CurrentWeaponName = weaponName
	self.Config = config
	self.CurrentViewmodelCFrame = nil

	self.ViewmodelEffects:Reset()
	self.ViewmodelAnimator:SetupAnimations(viewmodel, config)

	self:StartRenderLoop()

	Log:Info("VIEWMODEL", "Viewmodel created", { Weapon = weaponName })

	return viewmodel
end

function ViewmodelController:LoadViewmodel(modelPath)
	local viewmodelsFolder = ReplicatedFirst:FindFirstChild("ViewModels")
	if not viewmodelsFolder then
		Log:Error("VIEWMODEL", "ViewModels folder not found in ReplicatedFirst")
		return nil
	end

	local pathParts = string.split(modelPath, "/")
	local currentFolder = viewmodelsFolder

	for i = 1, #pathParts - 1 do
		currentFolder = currentFolder:FindFirstChild(pathParts[i])
		if not currentFolder then
			Log:Error("VIEWMODEL", "Viewmodel folder not found", { Path = modelPath })
			return nil
		end
	end

	local modelName = pathParts[#pathParts]
	local viewmodelTemplate = currentFolder:FindFirstChild(modelName)

	if not viewmodelTemplate then
		Log:Error("VIEWMODEL", "Viewmodel model not found", { Path = modelPath })
		return nil
	end

	local viewmodel = viewmodelTemplate:Clone()

	local humanoid = viewmodel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end

	local animController = viewmodel:FindFirstChildOfClass("AnimationController")
	if not animController then
		animController = Instance.new("AnimationController")
		animController.Parent = viewmodel
	end

	return viewmodel
end

function ViewmodelController:ApplyHighlight(viewmodel)
	local highlightConfig = ViewmodelConfig.Highlight
	if not highlightConfig or not highlightConfig.Enabled then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "ViewmodelHighlight"
	highlight.FillColor = highlightConfig.FillColor
	highlight.FillTransparency = highlightConfig.FillTransparency
	highlight.OutlineColor = highlightConfig.OutlineColor
	highlight.OutlineTransparency = highlightConfig.OutlineTransparency
	highlight.DepthMode = highlightConfig.DepthMode
	highlight.Parent = viewmodel
end

function ViewmodelController:DestroyViewmodel()
	self:StopRenderLoop()

	if self.CurrentViewmodel then
		self.ViewmodelAnimator:StopAllAnimations()
		self.CurrentViewmodel:Destroy()
		self.CurrentViewmodel = nil
	end

	self.CurrentWeaponName = nil
	self.Config = nil
	self.CurrentViewmodelCFrame = nil

	Log:Info("VIEWMODEL", "Viewmodel destroyed")
end

function ViewmodelController:StartRenderLoop()
	if self.RenderConnection then
		return
	end

	self.RenderConnection = RunService.RenderStepped:Connect(function(deltaTime)
		self:UpdateViewmodel(deltaTime)
	end)
end

function ViewmodelController:StopRenderLoop()
	if self.RenderConnection then
		self.RenderConnection:Disconnect()
		self.RenderConnection = nil
	end
end

function ViewmodelController:UpdateViewmodel(deltaTime)
	if not self.CurrentViewmodel or not self.CurrentViewmodel.Parent then
		self:StopRenderLoop()
		return
	end

	local config = self.Config
	if not config then
		return
	end

	local effectsOffset = self.ViewmodelEffects:GetCombinedOffset(deltaTime, 0, config)

	local cameraPart = self.CurrentViewmodel:FindFirstChild("Camera")
	if not cameraPart then
		Log:Warn("VIEWMODEL", "Camera part not found in viewmodel")
		return
	end

	-- Direct camera follow - NO LERP for instant response
	-- Sway/bob effects from ViewmodelEffects provide the smooth movement feel
	local targetCFrame = Camera.CFrame
		* self.CurrentViewmodel:GetPivot():ToObjectSpace(cameraPart:GetPivot()):Inverse()
		* config.Offset
		* effectsOffset

	self.CurrentViewmodel:PivotTo(targetCFrame)
end

function ViewmodelController:GetGun()
	if not self.CurrentViewmodel then
		return nil
	end

	local weaponModel = self.CurrentViewmodel:FindFirstChild(self.CurrentWeaponName)

	if not weaponModel then
		for _, child in ipairs(self.CurrentViewmodel:GetChildren()) do
			if child:IsA("Model") and not child.Name:find("Arm") then
				return child
			end
		end
	end

	return weaponModel
end

function ViewmodelController:GetCurrentViewmodel()
	return self.CurrentViewmodel
end

function ViewmodelController:GetCurrentConfig()
	return self.Config
end

function ViewmodelController:IsViewmodelActive()
	return self.CurrentViewmodel ~= nil
end

function ViewmodelController:GetCurrentWeight()
	if self.Config then
		return self.Config.Weight or 1.0
	end
	return 1.0
end

function ViewmodelController:PlayAnimation(animationName)
	self.ViewmodelAnimator:PlayAnimation(animationName)
end

function ViewmodelController:StopAnimation(animationName)
	self.ViewmodelAnimator:StopAnimation(animationName)
end

return ViewmodelController
