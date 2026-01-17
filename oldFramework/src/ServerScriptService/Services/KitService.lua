local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local KitConfig = require(Locations.Modules.Config.KitConfig)

local KitService = {}
KitService._playerKits = {}
KitService._isInitialized = false

function KitService:Init()
	if self._isInitialized then
		return
	end

	Log:RegisterCategory("KITS", "Kit and ability system")

	self:SetupRemoteEvents()
	self:SetupPlayerConnections()

	self._isInitialized = true
	Log:Info("KITS", "KitService initialized")
end

function KitService:SetupRemoteEvents()
	RemoteEvents:ConnectServer("ActivateAbility", function(player, abilityType, clientData)
		self:OnAbilityRequest(player, abilityType, clientData)
	end)

	RemoteEvents:ConnectServer("RequestKitState", function(player)
		self:SendKitState(player)
	end)
end

function KitService:SetupPlayerConnections()
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)

	for _, player in pairs(Players:GetPlayers()) do
		self:OnPlayerAdded(player)
	end
end

function KitService:OnPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		self:OnCharacterAdded(player, character)
	end)

	if player.Character then
		self:OnCharacterAdded(player, player.Character)
	end

	if not self._playerKits[player] then
		self:AssignKit(player, "WhiteBeard")
	end
end

function KitService:OnPlayerRemoving(player)
	self:RemoveKit(player)
end

function KitService:OnCharacterAdded(player, character)
	local kit = self._playerKits[player]
	if kit then
		kit:UpdateCharacter(character)

		if KitConfig.Global.RespawnResetsCooldowns then
			kit:ResetCooldowns()
		end

		if KitConfig.Global.DeathInterruptsAbilities then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					kit:InterruptAll()
				end)
			end
		end
	end
end

function KitService:AssignKit(player, kitName)
	self:RemoveKit(player)

	local kitPath = KitConfig.Kits[kitName]
	if not kitPath then
		Log:Warn("KITS", "Kit not found in registry", { KitName = kitName })
		return nil
	end

	local success, kitModule = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Kits"):WaitForChild(kitName))
	end)

	if not success then
		Log:Error("KITS", "Failed to load kit module", { KitName = kitName, Error = tostring(kitModule) })
		return nil
	end

	local kit = kitModule.new and kitModule.new() or kitModule
	kit:Initialize(player, player.Character)

	self._playerKits[player] = kit

	RemoteEvents:FireClient("KitAssigned", player, {
		KitName = kitName,
		State = kit:GetState(),
	})

	Log:Info("KITS", "Kit assigned", { Player = player.Name, Kit = kitName })

	return kit
end

function KitService:RemoveKit(player)
	local kit = self._playerKits[player]
	if kit then
		kit:Destroy()
		self._playerKits[player] = nil
		Log:Debug("KITS", "Kit removed", { Player = player.Name })
	end
end

function KitService:GetPlayerKit(player)
	return self._playerKits[player]
end

function KitService:OnAbilityRequest(player, abilityType, clientData)
	local kit = self._playerKits[player]
	if not kit then
		Log:Debug("KITS", "No kit assigned", { Player = player.Name })
		return
	end

	if not player.Character or not player.Character.Parent then
		Log:Debug("KITS", "No character for ability request", { Player = player.Name })
		return
	end

	local ability = nil
	if abilityType == "Ability" then
		ability = kit.Ability
	elseif abilityType == "Ultimate" then
		ability = kit.Ultimate
	end

	if not ability then
		Log:Debug("KITS", "Invalid ability type", { Player = player.Name, Type = abilityType })
		return
	end

	if not ability:IsReady() then
		Log:Debug("KITS", "Ability not ready", { 
			Player = player.Name, 
			Ability = ability.Name,
			State = ability.State,
		})
		return
	end

	local success = false
	if abilityType == "Ability" then
		success = kit:ActivateAbility(clientData)
	elseif abilityType == "Ultimate" then
		success = kit:ActivateUltimate(clientData)
	end

	if success then
		Log:Debug("KITS", "Ability activated", { 
			Player = player.Name, 
			Ability = ability.Name 
		})

		RemoteEvents:FireAllClients("AbilityActivated", {
			PlayerId = player.UserId,
			AbilityName = ability.Name,
			AbilityType = abilityType,
			Position = player.Character.PrimaryPart and player.Character.PrimaryPart.Position,
		})

		if ability.Duration > 0 then
			ability.Ended:once(function()
				RemoteEvents:FireAllClients("AbilityEnded", {
					PlayerId = player.UserId,
					AbilityName = ability.Name,
					AbilityType = abilityType,
				})
			end)

			ability.Interrupted:once(function()
				RemoteEvents:FireAllClients("AbilityInterrupted", {
					PlayerId = player.UserId,
					AbilityName = ability.Name,
					AbilityType = abilityType,
				})
			end)
		end
	end
end

function KitService:OnPlayerKill(killer, victim)
	local kit = self._playerKits[killer]
	if kit then
		kit:OnKill(victim)
	end
end

function KitService:OnDamageDealt(attacker, victim, damage)
	local kit = self._playerKits[attacker]
	if kit and kit.Ultimate then
		kit.Ultimate:OnDamageDealt(damage)
	end
end

function KitService:SendKitState(player)
	local kit = self._playerKits[player]
	if kit then
		RemoteEvents:FireClient("KitStateUpdate", player, kit:GetState())
	end
end

function KitService:BroadcastUltCharge(player)
	local kit = self._playerKits[player]
	if kit and kit.Ultimate then
		RemoteEvents:FireClient("UltimateChargeUpdate", player, {
			Current = kit.Ultimate.CurrentCharge,
			Required = kit.Ultimate.RequiredCharge,
		})
	end
end

return KitService
