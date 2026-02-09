--[[
	KnockbackController.lua
	Client-side knockback system with Rivals-style momentum preservation
	
	Features:
	- Config-based API: ApplyKnockback(character, sourcePosition, config)
	- Preset-based API: ApplyKnockbackPreset(character, "Fling", sourcePosition)
	- Raw API: ApplyKnockbackToCharacter(character, direction, magnitude)
	- Handles local player, other players, and dummies/NPCs automatically
	- Full air control during knockback for momentum redirection
	
	Usage:
		local kb = ServiceRegistry:GetController("Knockback")
		
		-- Using custom config (no preset required)
		kb:ApplyKnockback(targetCharacter, myPosition, {
			upwardVelocity = 80,
			outwardVelocity = 180,
			preserveMomentum = 0.1,
		})
		
		-- Using presets
		kb:ApplyKnockbackPreset(targetCharacter, "Fling", myPosition)
		kb:ApplyKnockbackPreset(targetCharacter, "Launch", myPosition)
		kb:ApplyKnockbackPreset(targetCharacter, "Blast", myPosition)
		
		-- Raw direction/magnitude API
		kb:ApplyKnockbackToCharacter(targetCharacter, direction, magnitude)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local KnockbackConfig = require(Locations.Shared:WaitForChild("Knockback"):WaitForChild("KnockbackConfig"))

local LocalPlayer = Players.LocalPlayer

local KnockbackController = {}

KnockbackController._registry = nil
KnockbackController._net = nil
KnockbackController._movementController = nil
KnockbackController._initialized = false
KnockbackController._knockbackEvent = nil

function KnockbackController:Init(registry, net)
	self._registry = registry
	self._net = net
	self._knockbackEvent = Instance.new("BindableEvent")

	ServiceRegistry:RegisterController("Knockback", self)

	-- Listen for knockback from server
	self._net:ConnectClient("Knockback", function(data)
		self:_onKnockbackReceived(data)
	end)

	self._initialized = true
end

function KnockbackController:Start()
	-- Get movement controller reference
	self._movementController = ServiceRegistry:GetController("Movement")
end

-- =============================================================================
-- SERVER EVENT HANDLER
-- =============================================================================

function KnockbackController:_onKnockbackReceived(data)
	if not data then
		return
	end

	local preserveMomentum = data.preserveMomentum or 0.0

	-- Check for new velocity-based format
	if data.velocity then
		local velocity = Vector3.new(data.velocity.X, data.velocity.Y, data.velocity.Z)
		self:_applyVelocityToLocalPlayer(velocity, preserveMomentum, data.sourceUserId)
		return
	end

	-- Legacy direction+magnitude format
	if data.direction then
		local direction = Vector3.new(data.direction.X, data.direction.Y, data.direction.Z)
		self:_applyKnockbackToLocalPlayer(direction, data.magnitude, preserveMomentum, data.sourceUserId)
	end
end

function KnockbackController:GetKnockbackSignal()
	if not self._knockbackEvent then
		self._knockbackEvent = Instance.new("BindableEvent")
	end
	return self._knockbackEvent.Event
end

function KnockbackController:_emitLocalKnockbackApplied(data)
	if self._knockbackEvent then
		self._knockbackEvent:Fire(data)
	end
end

-- =============================================================================
-- INTERNAL: Apply knockback to local player
-- =============================================================================

function KnockbackController:_applyKnockbackToLocalPlayer(direction, magnitude, preserveMomentum, sourceUserId)
	local character = LocalPlayer.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("Root") or character.PrimaryPart
	if not root then
		return
	end

	-- Default preserve momentum
	preserveMomentum = preserveMomentum or 0.2

	-- Normalize direction
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(0, 1, 0)
	else
		direction = direction.Unit
	end

	-- Clamp magnitude
	magnitude = math.min(magnitude, KnockbackConfig.MaxMagnitude)

	-- Check grounded state for multiplier
	local isGrounded = self._movementController and self._movementController.IsGrounded
	local multiplier = isGrounded and KnockbackConfig.GroundedMultiplier or KnockbackConfig.AirborneMultiplier

	-- Calculate knockback velocity
	local knockbackVel = direction * magnitude * multiplier

	-- Keep some existing horizontal momentum based on preset
	local currentVel = root.AssemblyLinearVelocity
	local preserved = Vector3.new(currentVel.X, 0, currentVel.Z) * preserveMomentum

	-- Apply knockback (replaces current velocity)
	root.AssemblyLinearVelocity = knockbackVel + preserved

	-- Ensure we leave ground if grounded
	if isGrounded and knockbackVel.Y < 15 then
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + Vector3.new(0, 15, 0)
	end

	self:_emitLocalKnockbackApplied({
		kind = "direction",
		sourceUserId = sourceUserId,
	})
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--[[
	PRESET API: Apply knockback using a preset configuration
	This is the recommended way to apply knockback.
	
	Uses DIRECT VELOCITY COMPONENTS (like JumpPads) - no normalization!
	
	@param character Model - The character to knockback
	@param presetName string - Preset name: "Fling", "Launch", "Blast", "Uppercut", etc.
	@param sourcePosition Vector3 - Position to knock away from
	@param overrides table? - Optional config overrides: { upwardVelocity?, outwardVelocity?, preserveMomentum? }
	
	Examples:
		kb:ApplyKnockbackPreset(char, "Fling", pos)
		kb:ApplyKnockbackPreset(char, "Fling", pos, { upwardVelocity = 120 })
		kb:ApplyKnockbackPreset(char, "Fling", pos, { outwardVelocity = 250 })
]]
function KnockbackController:ApplyKnockbackPreset(character, presetName, sourcePosition, overrides)
	if not character then
		return
	end

	local preset = KnockbackConfig.Presets[presetName]
	if not preset then
		warn("[KnockbackController] Unknown preset:", presetName)
		preset = KnockbackConfig.Presets.Standard
	end

	-- Apply overrides if provided
	local upwardVelocity = preset.upwardVelocity
	local outwardVelocity = preset.outwardVelocity
	local preserveMomentum = preset.preserveMomentum

	if overrides then
		if overrides.upwardVelocity then
			upwardVelocity = overrides.upwardVelocity
		end
		if overrides.outwardVelocity then
			outwardVelocity = overrides.outwardVelocity
		end
		if overrides.preserveMomentum then
			preserveMomentum = overrides.preserveMomentum
		end
	end

	-- Get target root
	local targetRoot = character:FindFirstChild("Root") or character.PrimaryPart
	if not targetRoot then
		return
	end

	-- Calculate horizontal direction from source to target (unit vector)
	local toTarget = (targetRoot.Position - sourcePosition)
	local horizontalDir = Vector3.new(toTarget.X, 0, toTarget.Z)
	if horizontalDir.Magnitude < 0.1 then
		horizontalDir = Vector3.new(0, 0, 1)
	else
		horizontalDir = horizontalDir.Unit
	end

	-- Build velocity directly: horizontal direction * outward speed + vertical
	local velocity = (horizontalDir * outwardVelocity) + Vector3.new(0, upwardVelocity, 0)

	-- Send with velocity-based data
	self:_sendKnockbackVelocity(character, velocity, preserveMomentum)
end

--[[
	Internal: Send velocity-based knockback to appropriate target
]]
function KnockbackController:_sendKnockbackVelocity(character, velocity, preserveMomentum)
	if not self._net then
		return
	end

	-- Is it the local player's character? Apply directly
	if character == LocalPlayer.Character then
		self:_applyVelocityToLocalPlayer(velocity, preserveMomentum)
		return
	end

	-- Is it another player's character?
	local targetPlayer = Players:GetPlayerFromCharacter(character)
	if targetPlayer then
		self._net:FireServer("KnockbackRequest", {
			targetType = "player",
			targetUserId = targetPlayer.UserId,
			velocity = { X = velocity.X, Y = velocity.Y, Z = velocity.Z },
			preserveMomentum = preserveMomentum,
		})
		return
	end

	-- It's a dummy/NPC - send to server to apply directly
	self._net:FireServer("KnockbackRequest", {
		targetType = "dummy",
		targetName = character.Name,
		velocity = { X = velocity.X, Y = velocity.Y, Z = velocity.Z },
	})
end

--[[
	Internal: Apply velocity directly to local player (no normalization)
]]
function KnockbackController:_applyVelocityToLocalPlayer(velocity, preserveMomentum, sourceUserId)
	local character = LocalPlayer.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("Root") or character.PrimaryPart
	if not root then
		return
	end

	preserveMomentum = preserveMomentum or 0.0

	-- Keep some existing horizontal momentum if requested
	local currentVel = root.AssemblyLinearVelocity
	local preserved = Vector3.new(currentVel.X, 0, currentVel.Z) * preserveMomentum

	-- Apply velocity directly (like JumpPad does)
	root.AssemblyLinearVelocity = velocity + preserved

	self:_emitLocalKnockbackApplied({
		kind = "velocity",
		sourceUserId = sourceUserId,
	})
end

--[[
	RAW API: Apply knockback to any character with explicit direction/magnitude
	
	@param character Model - The character to knockback
	@param direction Vector3 - Knockback direction (will be normalized)
	@param magnitude number - Knockback strength (studs/sec)
	@param preserveMomentum number? - How much existing velocity to keep (0-1)
]]
function KnockbackController:ApplyKnockbackToCharacter(character, direction, magnitude, preserveMomentum)
	if not character then
		return
	end

	-- Normalize direction
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(0, 1, 0)
	else
		direction = direction.Unit
	end

	self:_sendKnockback(character, direction, magnitude, preserveMomentum or 0.2)
end

--[[
	Internal: Send knockback to appropriate target
]]
function KnockbackController:_sendKnockback(character, direction, magnitude, preserveMomentum)
	if not self._net then
		return
	end

	-- Is it the local player's character? Apply directly
	if character == LocalPlayer.Character then
		self:_applyKnockbackToLocalPlayer(direction, magnitude, preserveMomentum)
		return
	end

	-- Is it another player's character?
	local targetPlayer = Players:GetPlayerFromCharacter(character)
	if targetPlayer then
		self._net:FireServer("KnockbackRequest", {
			targetType = "player",
			targetUserId = targetPlayer.UserId,
			direction = { X = direction.X, Y = direction.Y, Z = direction.Z },
			magnitude = magnitude,
			preserveMomentum = preserveMomentum,
		})
		return
	end

	-- It's a dummy/NPC - send to server to apply directly
	self._net:FireServer("KnockbackRequest", {
		targetType = "dummy",
		targetName = character.Name,
		direction = { X = direction.X, Y = direction.Y, Z = direction.Z },
		magnitude = magnitude,
	})
end

--[[
	Apply knockback - supports multiple signatures:
	
	1. Local player with direction/magnitude (legacy):
		kb:ApplyKnockback(direction, magnitude)
	
	2. Any character with config (no preset required):
		kb:ApplyKnockback(character, sourcePosition, config)
		config = { upwardVelocity, outwardVelocity, preserveMomentum? }
	
	Examples:
		kb:ApplyKnockback(Vector3.new(1, 0.5, 0), 100)  -- Local player, direction-based
		kb:ApplyKnockback(targetChar, myPosition, { upwardVelocity = 80, outwardVelocity = 180 })
]]
function KnockbackController:ApplyKnockback(arg1, arg2, arg3)
	-- Detect which signature is being used
	if typeof(arg1) == "Vector3" then
		-- Legacy: ApplyKnockback(direction, magnitude) for local player
		local direction = arg1
		local magnitude = arg2
		self:_applyKnockbackToLocalPlayer(direction, magnitude, 0.2)
		return
	end

	-- New: ApplyKnockback(character, sourcePosition, config)
	local character = arg1
	local sourcePosition = arg2
	local config = arg3

	if not character then
		return
	end
	if not config or type(config) ~= "table" then
		return
	end

	local upwardVelocity = config.upwardVelocity or 50
	local outwardVelocity = config.outwardVelocity or 60
	local preserveMomentum = config.preserveMomentum or 0.0

	-- Get target root
	local targetRoot = character:FindFirstChild("Root") or character.PrimaryPart
	if not targetRoot then
		return
	end

	-- Calculate horizontal direction from source to target (unit vector)
	local toTarget = (targetRoot.Position - sourcePosition)
	local horizontalDir = Vector3.new(toTarget.X, 0, toTarget.Z)
	if horizontalDir.Magnitude < 0.1 then
		horizontalDir = Vector3.new(0, 0, 1)
	else
		horizontalDir = horizontalDir.Unit
	end

	-- Build velocity directly: horizontal direction * outward speed + vertical
	local velocity = (horizontalDir * outwardVelocity) + Vector3.new(0, upwardVelocity, 0)

	-- Send with velocity-based data
	self:_sendKnockbackVelocity(character, velocity, preserveMomentum)
end

--[[
	Apply knockback away from a position (for AoE/explosions) to local player
	@param position Vector3 - Source position to knock away from
	@param magnitude number - Knockback strength
]]
function KnockbackController:ApplyKnockbackFromPosition(position, magnitude)
	local character = LocalPlayer.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("Root") or character.PrimaryPart
	if not root then
		return
	end

	local direction = (root.Position - position)
	if direction.Magnitude < 0.1 then
		direction = Vector3.new(0, 1, 0)
	end

	self:ApplyKnockback(direction, magnitude)
end

return KnockbackController
