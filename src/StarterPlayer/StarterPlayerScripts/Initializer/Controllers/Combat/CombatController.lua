--[[
	CombatController.lua
	Client-side combat event handling and display
	
	Handles:
	- Receiving combat state updates from server
	- Driving local damage UI helpers
	- Status effect visual feedback
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = ReplicatedStorage:WaitForChild("Assets")
local SoundHitmarker = Assets:WaitForChild("Sounds"):WaitForChild("hitmarker")
local SoundHeadshot  = Assets:WaitForChild("Sounds"):WaitForChild("headshot")
local PlayerDataTable = require(ReplicatedStorage:WaitForChild("PlayerDataTable"))
local SettingsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("SettingsConfig"))

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local DamageNumbers = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("DamageNumbers"))
local Tracers = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Tracers"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local LocalPlayer = Players.LocalPlayer
local DAMAGE_NUMBERS_MODE_ADD = "Add"
local DAMAGE_NUMBERS_MODE_DISABLED = "Disabled"
local DAMAGE_NUMBERS_MODE_STACKED = "Stacked"

local function toNumber(value)
	local parsed = tonumber(value)
	if parsed == nil then
		return nil
	end
	if parsed ~= parsed then
		return nil
	end
	return parsed
end

local function toVector3(value)
	if typeof(value) == "Vector3" then
		return value
	end
	if type(value) ~= "table" then
		return nil
	end

	local x = tonumber(value.X or value.x)
	local y = tonumber(value.Y or value.y)
	local z = tonumber(value.Z or value.z)
	if x == nil or y == nil or z == nil then
		return nil
	end

	return Vector3.new(x, y, z)
end

local function getPlayerByUserIdSafe(userId)
	if type(userId) ~= "number" or userId <= 0 then
		return nil
	end

	local ok, player = pcall(Players.GetPlayerByUserId, Players, userId)
	if ok then
		return player
	end

	return nil
end

local function getCharacterPivotPosition(character)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return nil
	end

	local root = character:FindFirstChild("Root")
		or character.PrimaryPart
		or character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChildWhichIsA("BasePart", true)
	return root and root.Position or nil
end

local function normalizeDamageNumbersMode(value)
	if type(value) == "string" then
		local lowered = string.lower(value)
		if lowered == "disabled" or lowered == "off" then
			return DAMAGE_NUMBERS_MODE_DISABLED
		end
		if lowered == "stacked" or lowered == "list" then
			return DAMAGE_NUMBERS_MODE_STACKED
		end
		return DAMAGE_NUMBERS_MODE_ADD
	end

	if type(value) == "boolean" then
		return value and DAMAGE_NUMBERS_MODE_ADD or DAMAGE_NUMBERS_MODE_DISABLED
	end

	if type(value) == "number" then
		if value == 1 then
			return DAMAGE_NUMBERS_MODE_DISABLED
		end
		if value == 3 then
			return DAMAGE_NUMBERS_MODE_STACKED
		end
		return DAMAGE_NUMBERS_MODE_ADD
	end

	return DAMAGE_NUMBERS_MODE_ADD
end

local function resolveDamageNumbersModeFromSettingValue(settingValue)
	local setting = SettingsConfig.getSetting("Gameplay", "DamageNumbers")
	local options = setting and setting.Options
	if typeof(options) == "table" and type(settingValue) == "number" then
		local index = math.clamp(math.floor(settingValue + 0.5), 1, #options)
		local option = options[index]
		if option and option.Value ~= nil then
			return normalizeDamageNumbersMode(option.Value)
		end
	end
	return normalizeDamageNumbersMode(settingValue)
end

local function getDamageNumbersMode()
	if LocalPlayer then
		local attrMode = LocalPlayer:GetAttribute("SettingsDamageNumbersMode")
		if attrMode ~= nil then
			return normalizeDamageNumbersMode(attrMode)
		end
	end

	local storedValue = PlayerDataTable.get("Gameplay", "DamageNumbers")
	return resolveDamageNumbersModeFromSettingValue(storedValue)
end

local CombatController = {}

CombatController._registry = nil
CombatController._net = nil
CombatController._initialized = false
CombatController._damageRad = nil
CombatController._damagedOverlay = nil
CombatController._lastHealth = nil

function CombatController:Init(registry, net)
	self._registry = registry
	self._net = net
	
	ServiceRegistry:RegisterController("Combat", self)
	DamageNumbers:Init()
	DamageNumbers:SetMode(getDamageNumbersMode())

	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal("SettingsDamageNumbersMode"):Connect(function()
			DamageNumbers:SetMode(getDamageNumbersMode())
		end)
	end
	
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

function CombatController:_getDamagedOverlay()
	if self._damagedOverlay then
		return self._damagedOverlay
	end

	local uiController = ServiceRegistry:GetController("UI")
	if not uiController or not uiController.GetCoreUI then
		return nil
	end

	local coreUi = uiController:GetCoreUI()
	if not coreUi then
		return nil
	end

	self._damagedOverlay = coreUi:getModule("Damaged")
	return self._damagedOverlay
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

	local damagedOverlay = self:_getDamagedOverlay()
	if damagedOverlay and damagedOverlay.setHealthState then
		if type(state.health) == "number" then
			if type(self._lastHealth) == "number" then
				local delta = state.health - self._lastHealth
				if delta < 0 and damagedOverlay.onDamageTaken then
					damagedOverlay:onDamageTaken(math.abs(delta))
				elseif delta > 0 and damagedOverlay.onHealed then
					damagedOverlay:onHealed(delta)
				end
			end
			self._lastHealth = state.health
		end

		damagedOverlay:setHealthState(state.health, state.maxHealth)
	end
end

--[[
	Handles damage/heal events for local damage UI helpers
]]
function CombatController:_onDamageDealt(data)
	if not data then return end

	local localUserId = LocalPlayer and LocalPlayer.UserId or nil
	local attackerUserId = toNumber(data.attackerUserId)
	local targetUserId = toNumber(data.targetUserId)
	local isSelfTarget = targetUserId ~= nil and targetUserId == localUserId

	if not data.isHeal and attackerUserId == localUserId and not isSelfTarget then
		local hitPos = toVector3(data.position)
		local targetPivot = toVector3(data.targetPivotPosition)
		local targetPlayer = getPlayerByUserIdSafe(targetUserId)
		local targetCharacter = targetPlayer and targetPlayer.Character

		-- Use server position first (guaranteed when DamageDealt is broadcast),
		-- then live character pivot for smoother tracking, then targetPivotPosition
		local anchorPos = getCharacterPivotPosition(targetCharacter)
			or hitPos
			or targetPivot

		if anchorPos then
			local numbersMode = getDamageNumbersMode()
			DamageNumbers:SetMode(numbersMode)

			local targetKey = targetUserId
			if targetKey == nil then
				targetKey = data.targetEntityKey
			end
			if targetKey == nil then
				targetKey = string.format(
					"pos:%d:%d:%d",
					math.floor(anchorPos.X + 0.5),
					math.floor(anchorPos.Y + 0.5),
					math.floor(anchorPos.Z + 0.5)
				)
			end

			if numbersMode ~= DAMAGE_NUMBERS_MODE_DISABLED then
				DamageNumbers:ShowForTarget(targetKey, anchorPos, tonumber(data.damage) or 0, {
					isHeadshot = data.isHeadshot,
					isCritical = data.isCritical,
					targetUserId = targetKey,
				})
			end
		end

		-- Play hitmarker sound
		self:_playHitSound(data.isHeadshot)

		-- Damage confirmed by server — run tracer HitPlayer effect on the target
		-- Resolve character for dummies/non-player entities by name in workspace
		if not targetCharacter and data.targetCharacterName then
			targetCharacter = Workspace:FindFirstChild(data.targetCharacterName, true)
			if targetCharacter and not targetCharacter:IsA("Model") then
				targetCharacter = nil
			end
		end

		if targetCharacter then
			self:_runHitPlayerEffect(targetCharacter, hitPos)
		end
	end

	if not data.isHeal and isSelfTarget then
		local sourcePosition = nil
		if attackerUserId then
			local attacker = getPlayerByUserIdSafe(attackerUserId)
			local attackerCharacter = attacker and attacker.Character
			sourcePosition = getCharacterPivotPosition(attackerCharacter)
		end
		if not sourcePosition then
			sourcePosition = toVector3(data.sourcePosition)
		end

		if sourcePosition then
			local damageRad = self:_getDamageRad()
			if damageRad and damageRad.reportDamageFromPosition then
				damageRad:reportDamageFromPosition(sourcePosition, tonumber(data.damage))
			end
		end
	elseif not data.isHeal then
		-- While spectating, show the damage radial for hits on the spectated target
		local spectateController = ServiceRegistry:GetController("Spectate")
		if spectateController and spectateController:IsSpectating() then
			if targetUserId == spectateController:GetTargetUserId() then
				local sourcePosition = nil
				if attackerUserId then
					local attacker = getPlayerByUserIdSafe(attackerUserId)
					local attackerCharacter = attacker and attacker.Character
					sourcePosition = getCharacterPivotPosition(attackerCharacter)
				end
				if not sourcePosition then
					sourcePosition = toVector3(data.sourcePosition)
				end
				if sourcePosition then
					local damageRad = self:_getDamageRad()
					if damageRad and damageRad.reportDamageFromPosition then
						damageRad:reportDamageFromPosition(sourcePosition, tonumber(data.damage))
					end
				end
			end
		end
	end
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
		self._lastHealth = nil
	end
end

-- =============================================================================
-- HITMARKER SOUNDS
-- =============================================================================

function CombatController:_playHitSound(isHeadshot)
	local sound = isHeadshot and SoundHeadshot or SoundHitmarker
	if sound then
		sound:Play()
	end
end

-- =============================================================================
-- TRACER HIT PLAYER (damage-confirmed)
-- =============================================================================

--[[
	Runs the tracer HitPlayer effect on a target character.
	Uses the equipped weapon's tracer if it has one, otherwise Default.
]]
function CombatController:_runHitPlayerEffect(targetCharacter, hitPosition)
	if not Tracers._initialized then
		Tracers:Init()
	end

	-- Try to resolve tracer from the currently equipped weapon
	local tracerId = nil
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.GetWeaponInstance then
		local inst = weaponController:GetWeaponInstance()
		-- Weapon instance has Config with the full weapon config
		local cfg = inst and inst.Config
		if cfg and cfg.tracerId then
			tracerId = cfg.tracerId
		end
	end

	-- Get the tracer module (falls back to Default)
	local tracerModule = Tracers:Get(tracerId)
	if not tracerModule or not tracerModule.HitPlayer then
		return
	end

	tracerModule:HitPlayer(hitPosition, nil, targetCharacter, nil, Tracers)
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
