--[[
	CombatController.lua
	Client-side combat event handling and display
	
	Handles:
	- Receiving combat state updates from server
	- Displaying damage numbers
	- Status effect visual feedback
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local DamageNumbers = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("DamageNumbers"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local LocalPlayer = Players.LocalPlayer

local CombatController = {}

CombatController._registry = nil
CombatController._net = nil
CombatController._initialized = false
CombatController._damageRad = nil

function CombatController:Init(registry, net)
	self._registry = registry
	self._net = net
	
	ServiceRegistry:RegisterController("Combat", self)
	
	-- Initialize damage numbers
	DamageNumbers:Init()
	
	-- Connect to combat events
	self._net:ConnectClient("CombatStateUpdate", function(state)
		self:_onCombatStateUpdate(state)
	end)
	
	self._net:ConnectClient("DamageDealt", function(data)
		self:_onDamageDealt(data)
	end)
	
	self._net:ConnectClient("StatusEffectUpdate", function(effects)
		self:_onStatusEffectUpdate(effects)
	end)
	
	self._net:ConnectClient("PlayerKilled", function(data)
		self:_onPlayerKilled(data)
	end)
	
	self._initialized = true
end

function CombatController:Start()
end

function CombatController:_getDamageRad()
	if self._damageRad then
		return self._damageRad
	end

	local uiController = ServiceRegistry:GetController("UI")
	if not uiController or not uiController.GetCoreUI then
		return nil
	end

	local coreUi = uiController:GetCoreUI()
	if not coreUi then
		return nil
	end

	self._damageRad = coreUi:getModule("DamageRad")
	return self._damageRad
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

--[[
	Handles combat state updates from server
]]
function CombatController:_onCombatStateUpdate(state)
	if not state then return end
	
	-- Update local player attributes for UI
	if LocalPlayer then
		LocalPlayer:SetAttribute("Health", state.health)
		LocalPlayer:SetAttribute("MaxHealth", state.maxHealth)
		LocalPlayer:SetAttribute("Shield", state.shield)
		LocalPlayer:SetAttribute("Overshield", state.overshield)
		LocalPlayer:SetAttribute("Ultimate", state.ultimate)
		LocalPlayer:SetAttribute("MaxUltimate", state.maxUltimate)
	end
end

--[[
	Handles damage dealt events - shows damage numbers
]]
function CombatController:_onDamageDealt(data)
	if not data then return end
	
	-- Don't show damage numbers for damage we deal to ourselves
	-- (but do show healing on ourselves)
	if data.attackerUserId == LocalPlayer.UserId and data.targetUserId == LocalPlayer.UserId and not data.isHeal then
		return
	end
	
	-- Get position
	local position = data.position
	if not position then
		-- Try to get from character
		local targetPlayer = Players:GetPlayerByUserId(data.targetUserId)
		if targetPlayer and targetPlayer.Character then
			local head = targetPlayer.Character:FindFirstChild("Head")
			position = head and head.Position or targetPlayer.Character.PrimaryPart and targetPlayer.Character.PrimaryPart.Position
			if position then
				position = position + Vector3.new(0, 1, 0)
			end
		end
	end
	
	if not position then return end

	if not data.isHeal and data.targetUserId == LocalPlayer.UserId then
		local sourcePosition = data.sourcePosition
		if not sourcePosition and data.attackerUserId then
			local attacker = Players:GetPlayerByUserId(data.attackerUserId)
			local attackerCharacter = attacker and attacker.Character
			local attackerRoot = attackerCharacter and (attackerCharacter.PrimaryPart or attackerCharacter:FindFirstChild("HumanoidRootPart"))
			sourcePosition = attackerRoot and attackerRoot.Position or nil
		end

		if sourcePosition then
			local damageRad = self:_getDamageRad()
			if damageRad and damageRad.reportDamageFromPosition then
				damageRad:reportDamageFromPosition(sourcePosition)
			end
		end
	end
	
	-- Show damage number
	DamageNumbers:Show(position, data.damage, {
		isHeadshot = data.isHeadshot,
		isCritical = data.isCritical,
		isHeal = data.isHeal,
	})
end

--[[
	Handles status effect updates
]]
function CombatController:_onStatusEffectUpdate(effects)
	if not effects then return end
	
	-- Update character attributes for VFX systems
	local character = LocalPlayer and LocalPlayer.Character
	if not character then return end
	
	-- The actual VFX would be handled by VFX controllers listening to these attributes
	-- Status effects set attributes like "BurnVFX", "FrozenVFX" etc. on the character
end

--[[
	Handles player killed events
]]
function CombatController:_onPlayerKilled(data)
	if not data then return end
	
	-- Could show kill feed entry here
	-- Could play kill sound if local player was the killer
	
	if data.killerUserId == LocalPlayer.UserId then
		-- We got a kill - could play sound, show notification, etc.
	end
	
	if data.victimUserId == LocalPlayer.UserId then
		-- We died
	end
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--[[
	Gets current health from attributes
	@return number
]]
function CombatController:GetHealth(): number
	return LocalPlayer and LocalPlayer:GetAttribute("Health") or 0
end

--[[
	Gets max health from attributes
	@return number
]]
function CombatController:GetMaxHealth(): number
	return LocalPlayer and LocalPlayer:GetAttribute("MaxHealth") or 150
end

--[[
	Gets current shield from attributes
	@return number
]]
function CombatController:GetShield(): number
	return LocalPlayer and LocalPlayer:GetAttribute("Shield") or 0
end

--[[
	Gets current overshield from attributes
	@return number
]]
function CombatController:GetOvershield(): number
	return LocalPlayer and LocalPlayer:GetAttribute("Overshield") or 0
end

--[[
	Gets current ultimate from attributes
	@return number
]]
function CombatController:GetUltimate(): number
	return LocalPlayer and LocalPlayer:GetAttribute("Ultimate") or 0
end

--[[
	Gets max ultimate from attributes
	@return number
]]
function CombatController:GetMaxUltimate(): number
	return LocalPlayer and LocalPlayer:GetAttribute("MaxUltimate") or 100
end

--[[
	Checks if ultimate is full
	@return boolean
]]
function CombatController:IsUltFull(): boolean
	return self:GetUltimate() >= self:GetMaxUltimate()
end

return CombatController
