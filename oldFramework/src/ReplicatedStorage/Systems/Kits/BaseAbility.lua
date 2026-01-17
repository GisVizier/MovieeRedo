local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Signal = require(Locations.Modules.Utils.Signal)
local Log = require(Locations.Modules.Systems.Core.LogService)

local AbilityState = {
	Ready = "Ready",
	Active = "Active",
	OnCooldown = "OnCooldown",
	Disabled = "Disabled",
}

local BaseAbility = {}
BaseAbility.__index = BaseAbility
BaseAbility.AbilityState = AbilityState

function BaseAbility.new(config)
	local self = setmetatable({}, BaseAbility)

	self.Name = config.Name or "UnnamedAbility"
	self.Type = config.Type or "Active"
	self.Cooldown = config.Cooldown or 0
	self.Duration = config.Duration or 0
	self.Charges = config.Charges or 1
	self.MaxCharges = config.Charges or 1

	self.State = AbilityState.Ready
	self.Owner = nil
	self.Character = nil
	self.CooldownEndTime = 0
	self.ActiveStartTime = 0
	self.LastActivationTime = 0
	self.DebounceTime = config.DebounceTime or 0.1
	self.IsServer = game:GetService("RunService"):IsServer()

	self._onStart = config.OnStart
	self._onEnd = config.OnEnd
	self._onInterrupt = config.OnInterrupt
	self._onKill = config.OnKill

	self.StateChanged = Signal.new()
	self.Activated = Signal.new()
	self.Ended = Signal.new()
	self.Interrupted = Signal.new()

	self._connections = {}
	self._activeThread = nil

	return self
end

function BaseAbility:Initialize(player, character)
	self.Owner = player
	self.Character = character

	Log:Debug("KITS", "Ability initialized", {
		Ability = self.Name,
		Player = player.Name,
	})
end

function BaseAbility:Cleanup()
	for _, conn in pairs(self._connections) do
		if conn and conn.disconnect then
			conn:disconnect()
		end
	end
	self._connections = {}

	if self._activeThread then
		task.cancel(self._activeThread)
		self._activeThread = nil
	end

	self.StateChanged:destroy()
	self.Activated:destroy()
	self.Ended:destroy()
	self.Interrupted:destroy()
end

function BaseAbility:SetState(newState)
	local oldState = self.State
	self.State = newState
	self.StateChanged:fire(oldState, newState)
end

function BaseAbility:IsReady()
	if self.State == AbilityState.Disabled then
		return false
	end
	if self.State == AbilityState.Active then
		return false
	end
	if self.Charges <= 0 then
		return false
	end
	if self.State == AbilityState.OnCooldown and os.clock() < self.CooldownEndTime then
		return false
	end
	if os.clock() - self.LastActivationTime < self.DebounceTime then
		return false
	end
	return true
end

function BaseAbility:GetCooldownRemaining()
	if self.State ~= AbilityState.OnCooldown then
		return 0
	end
	return math.max(0, self.CooldownEndTime - os.clock())
end

function BaseAbility:GetCooldownPercent()
	if self.Cooldown <= 0 then
		return 1
	end
	local remaining = self:GetCooldownRemaining()
	return 1 - (remaining / self.Cooldown)
end

function BaseAbility:Activate(data)
	if not self:IsReady() then
		Log:Debug("KITS", "Ability not ready", {
			Ability = self.Name,
			State = self.State,
			Charges = self.Charges,
		})
		return false
	end

	self.Charges = self.Charges - 1
	self.ActiveStartTime = os.clock()
	self.LastActivationTime = os.clock()
	self:SetState(AbilityState.Active)

	Log:Debug("KITS", "Ability activated", {
		Ability = self.Name,
		Player = self.Owner and self.Owner.Name,
		HasData = data ~= nil
	})

	if self._onStart then
		local success, err = pcall(function()
			self._onStart(self, data)
		end)
		if not success then
			Log:Error("KITS", "OnStart error", { Ability = self.Name, Error = err })
		end
	end

	self.Activated:fire()

	if self.Duration > 0 then
		self._activeThread = task.delay(self.Duration, function()
			if self.State == AbilityState.Active then
				self:End()
			end
		end)
	end

	return true
end

function BaseAbility:End()
	if self.State ~= AbilityState.Active then
		return false
	end

	if self._activeThread then
		task.cancel(self._activeThread)
		self._activeThread = nil
	end

	Log:Debug("KITS", "Ability ended", {
		Ability = self.Name,
		Duration = os.clock() - self.ActiveStartTime,
	})

	if self._onEnd then
		local success, err = pcall(function()
			self._onEnd(self)
		end)
		if not success then
			Log:Error("KITS", "OnEnd error", { Ability = self.Name, Error = err })
		end
	end

	self.Ended:fire()
	self:StartCooldown()

	return true
end

function BaseAbility:Interrupt()
	if self.State ~= AbilityState.Active then
		return false
	end

	if self._activeThread then
		task.cancel(self._activeThread)
		self._activeThread = nil
	end

	Log:Debug("KITS", "Ability interrupted", { Ability = self.Name })

	if self._onInterrupt then
		local success, err = pcall(function()
			self._onInterrupt(self)
		end)
		if not success then
			Log:Error("KITS", "OnInterrupt error", { Ability = self.Name, Error = err })
		end
	end

	self.Interrupted:fire()
	self:StartCooldown()

	return true
end

function BaseAbility:StartCooldown()
	if self.Cooldown <= 0 then
		self:SetState(AbilityState.Ready)
		self.Charges = math.min(self.Charges + 1, self.MaxCharges)
		return
	end

	self.CooldownEndTime = os.clock() + self.Cooldown
	self:SetState(AbilityState.OnCooldown)

	task.delay(self.Cooldown, function()
		if self.State == AbilityState.OnCooldown and os.clock() >= self.CooldownEndTime then
			self.Charges = math.min(self.Charges + 1, self.MaxCharges)
			if self.Charges > 0 then
				self:SetState(AbilityState.Ready)
			end
		end
	end)
end

function BaseAbility:OnKillTriggered(victim)
	if self._onKill then
		local success, err = pcall(function()
			self._onKill(self, victim)
		end)
		if not success then
			Log:Error("KITS", "OnKill error", { Ability = self.Name, Error = err })
		end
	end
end

function BaseAbility:GetPosition(maxDistance)
	maxDistance = maxDistance or 1000

	if not self.Owner then
		return nil
	end

	local character = self.Character or self.Owner.Character
	if not character then
		return nil
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * maxDistance

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(origin, direction, rayParams)

	if result then
		return result.Position, result.Normal, result.Instance
	end

	return origin + direction, Vector3.yAxis, nil
end

function BaseAbility:GetTargetsInRadius(origin, radius, filterFunc)
	local targets = {}

	for _, player in pairs(Players:GetPlayers()) do
		if player ~= self.Owner and player.Character then
			local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
				or player.Character:FindFirstChild("Root")
			if humanoidRootPart then
				local distance = (humanoidRootPart.Position - origin).Magnitude
				if distance <= radius then
					if not filterFunc or filterFunc(player) then
						table.insert(targets, {
							Player = player,
							Character = player.Character,
							Distance = distance,
						})
					end
				end
			end
		end
	end

	table.sort(targets, function(a, b)
		return a.Distance < b.Distance
	end)

	return targets
end

function BaseAbility:HealOwner(amount)
	if not self.Owner or not self.Character then
		return
	end

	local humanoid = self.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = math.min(humanoid.Health + amount, humanoid.MaxHealth)
	end
end

function BaseAbility:PlayVFX(effectName, position, params)
	local RemoteEvents = require(Locations.Modules.RemoteEvents)
	position = position or (self.Character and self.Character.PrimaryPart and self.Character.PrimaryPart.Position)

	if self.IsServer then
		RemoteEvents:FireAllClients("PlayVFX", {
			Effect = effectName,
			Position = position,
			Params = params,
			Owner = self.Owner and self.Owner.UserId,
		})
	else
		RemoteEvents:FireServer("PlayVFXRequest", {
			Effect = effectName,
			Position = position,
			Params = params,
		})
	end
end

function BaseAbility:PlaySound(soundName, position)
	local RemoteEvents = require(Locations.Modules.RemoteEvents)
	position = position or (self.Character and self.Character.PrimaryPart and self.Character.PrimaryPart.Position)

	if self.IsServer then
		RemoteEvents:FireAllClients("PlaySound", {
			Sound = soundName,
			Position = position,
			Owner = self.Owner and self.Owner.UserId,
		})
	else
		RemoteEvents:FireServer("PlaySoundRequest", {
			Sound = soundName,
			Position = position,
		})
	end
end

function BaseAbility:Teleport(targetPosition)
	if not self.Character then
		return false
	end

	local root = self.Character.PrimaryPart or self.Character:FindFirstChild("Root")
	if not root then
		return false
	end

	local newCFrame = CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(root.Orientation.Y), 0)
	self.Character:PivotTo(newCFrame)

	return true
end

function BaseAbility:Enable()
	if self.State == AbilityState.Disabled then
		self:SetState(AbilityState.Ready)
	end
end

function BaseAbility:Disable()
	if self.State == AbilityState.Active then
		self:Interrupt()
	end
	self:SetState(AbilityState.Disabled)
end

function BaseAbility:ResetCooldown()
	self.Charges = self.MaxCharges
	self.CooldownEndTime = 0
	if self.State == AbilityState.OnCooldown then
		self:SetState(AbilityState.Ready)
	end
end

return BaseAbility
