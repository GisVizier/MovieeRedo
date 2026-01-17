local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local KitConfig = require(Locations.Modules.Config.KitConfig)
local Signal = require(Locations.Modules.Utils.Signal)

local KitController = {}
KitController._currentKit = nil
KitController._isInitialized = false
KitController._connections = {}

KitController.KitAssigned = Signal.new()
KitController.AbilityActivated = Signal.new()
KitController.AbilityEnded = Signal.new()
KitController.UltimateChargeChanged = Signal.new()

function KitController:Init()
	if self._isInitialized then
		return
	end

	self:SetupInput()
	self:SetupRemoteEvents()

	self._isInitialized = true
	Log:Debug("KITS", "KitController initialized")
end

function KitController:SetupInput()
	local inputBeganConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == KitConfig.Input.AbilityKey then
			self:RequestAbility("Ability", input.UserInputState)
		elseif input.KeyCode == KitConfig.Input.UltimateKey then
			self:RequestAbility("Ultimate", input.UserInputState)
		end
	end)

	local inputEndedConn = UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == KitConfig.Input.AbilityKey then
			self:RequestAbility("Ability", input.UserInputState)
		elseif input.KeyCode == KitConfig.Input.UltimateKey then
			self:RequestAbility("Ultimate", input.UserInputState)
		end
	end)

	table.insert(self._connections, inputBeganConn)
	table.insert(self._connections, inputEndedConn)
end

function KitController:SetupRemoteEvents()
	local kitAssignedConn = RemoteEvents:ConnectClient("KitAssigned", function(data)
		self:OnKitAssigned(data)
	end)

	local abilityActivatedConn = RemoteEvents:ConnectClient("AbilityActivated", function(data)
		self:OnAbilityActivated(data)
	end)

	local abilityEndedConn = RemoteEvents:ConnectClient("AbilityEnded", function(data)
		self:OnAbilityEnded(data)
	end)

	local abilityInterruptedConn = RemoteEvents:ConnectClient("AbilityInterrupted", function(data)
		self:OnAbilityInterrupted(data)
	end)

	local ultChargeConn = RemoteEvents:ConnectClient("UltimateChargeUpdate", function(data)
		self:OnUltimateChargeUpdate(data)
	end)

	table.insert(self._connections, kitAssignedConn)
	table.insert(self._connections, abilityActivatedConn)
	table.insert(self._connections, abilityEndedConn)
	table.insert(self._connections, abilityInterruptedConn)
	table.insert(self._connections, ultChargeConn)
end

function KitController:RequestAbility(abilityType, inputState)
	-- CHECK FOR CLIENT-SIDE LOGIC (Hitboxes, Prediction)
	local kitName = self._currentKit and self._currentKit.KitName
	local clientData = nil
	local shouldSendToServer = true -- Default to true if no client module

	if kitName then
		-- Try to find Client module for this kit
		local kitFolder = ReplicatedStorage:FindFirstChild("Kits") and ReplicatedStorage.Kits:FindFirstChild(kitName)
		local clientModule = kitFolder and kitFolder:FindFirstChild("Client")
		
		if clientModule then
			local success, kitClient = pcall(require, clientModule)
			if success and kitClient then
				if abilityType == "Ability" and kitClient.OnAbility then
					-- Execute Client Logic
					local shouldContinue, data = kitClient.OnAbility(inputState)
					if shouldContinue == false then
						shouldSendToServer = false
					end
					clientData = data
				elseif abilityType == "Ultimate" and kitClient.OnUltimate then
					-- Execute Client Logic
					local shouldContinue, data = kitClient.OnUltimate(inputState)
					if shouldContinue == false then
						shouldSendToServer = false
					end
					clientData = data
				end
			end
		end
	end

	if not shouldSendToServer then
		return
	end

	if KitConfig.Debugging.LogAbilityActivations then
		Log:Debug("KITS", "Requesting ability activation", { Type = abilityType, HasData = clientData ~= nil })
	end

	RemoteEvents:FireServer("ActivateAbility", abilityType, clientData)
end

function KitController:OnKitAssigned(data)
	self._currentKit = data

	Log:Info("KITS", "Kit assigned to local player", { Kit = data.KitName })

	self.KitAssigned:fire(data)
end

function KitController:OnAbilityActivated(data)
	local localPlayer = Players.LocalPlayer

	if data.PlayerId == localPlayer.UserId then
		if KitConfig.Debugging.LogAbilityActivations then
			Log:Debug("KITS", "Local ability activated", {
				Ability = data.AbilityName,
				Type = data.AbilityType,
			})
		end
	end

	self.AbilityActivated:fire(data)
end

function KitController:OnAbilityEnded(data)
	self.AbilityEnded:fire(data)
end

function KitController:OnAbilityInterrupted(data)
	self.AbilityEnded:fire(data)
end

function KitController:OnUltimateChargeUpdate(data)
	if self._currentKit then
		self._currentKit.UltimateCharge = data
	end

	self.UltimateChargeChanged:fire(data.Current, data.Required)
end

function KitController:GetCurrentKit()
	return self._currentKit
end

function KitController:GetUltimateCharge()
	if self._currentKit and self._currentKit.UltimateCharge then
		return self._currentKit.UltimateCharge.Current, self._currentKit.UltimateCharge.Required
	end
	return 0, 100
end

function KitController:GetUltimateChargePercent()
	local current, required = self:GetUltimateCharge()
	return current / required
end

function KitController:IsUltimateReady()
	local current, required = self:GetUltimateCharge()
	return current >= required
end

function KitController:Cleanup()
	for _, conn in pairs(self._connections) do
		if conn and conn.disconnect then
			conn:disconnect()
		end
	end
	self._connections = {}

	self.KitAssigned:destroy()
	self.AbilityActivated:destroy()
	self.AbilityEnded:destroy()
	self.UltimateChargeChanged:destroy()
end

return KitController
