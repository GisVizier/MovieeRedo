--[[
	KnockbackController.lua
	Client-side knockback system with Rivals-style momentum preservation
	
	Features:
	- Apply knockback to local player
	- Request knockback on other players (server-relayed)
	- Full air control during knockback for momentum redirection
	- Works with existing movement system for natural momentum preservation
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

function KnockbackController:Init(registry, net)
	self._registry = registry
	self._net = net
	
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
	if not data then return end
	
	local direction = Vector3.new(data.direction.X, data.direction.Y, data.direction.Z)
	self:ApplyKnockback(direction, data.magnitude)
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--[[
	Apply knockback to local player
	@param direction Vector3 - Knockback direction (will be normalized)
	@param magnitude number - Knockback strength (studs/sec)
]]
function KnockbackController:ApplyKnockback(direction, magnitude)
	local character = LocalPlayer.Character
	if not character then return end
	
	local root = character:FindFirstChild("Root") or character.PrimaryPart
	if not root then return end
	
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
	
	-- Ensure minimum vertical component for pop-up effect
	local verticalRatio = math.max(direction.Y, KnockbackConfig.MinVerticalRatio)
	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	if horizontal.Magnitude > 0.01 then
		horizontal = horizontal.Unit
	else
		horizontal = Vector3.zero
	end
	local finalDir = (horizontal + Vector3.new(0, verticalRatio, 0)).Unit
	
	-- Calculate knockback velocity
	local knockbackVel = finalDir * magnitude * multiplier
	
	-- Keep small amount of existing horizontal momentum for smoother feel
	local currentVel = root.AssemblyLinearVelocity
	local preserved = Vector3.new(currentVel.X, 0, currentVel.Z) * 0.2
	
	-- Apply knockback (replaces current velocity)
	root.AssemblyLinearVelocity = knockbackVel + preserved
	
	-- Ensure we leave ground if grounded
	if isGrounded and knockbackVel.Y < 10 then
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + Vector3.new(0, 10, 0)
	end
end

--[[
	Apply knockback away from a position (for AoE/explosions)
	@param position Vector3 - Source position to knock away from
	@param magnitude number - Knockback strength
]]
function KnockbackController:ApplyKnockbackFromPosition(position, magnitude)
	local character = LocalPlayer.Character
	if not character then return end
	
	local root = character:FindFirstChild("Root") or character.PrimaryPart
	if not root then return end
	
	local direction = (root.Position - position)
	if direction.Magnitude < 0.1 then
		direction = Vector3.new(0, 1, 0)
	end
	
	self:ApplyKnockback(direction, magnitude)
end

--[[
	Request knockback on another player (sent to server for relay)
	@param targetPlayer Player - The player to knockback
	@param direction Vector3 - Knockback direction
	@param magnitude number - Knockback strength
]]
function KnockbackController:RequestKnockbackOnPlayer(targetPlayer, direction, magnitude)
	if not self._net then return end
	if not targetPlayer then return end
	
	self._net:FireServer("KnockbackRequest", {
		targetUserId = targetPlayer.UserId,
		direction = { X = direction.X, Y = direction.Y, Z = direction.Z },
		magnitude = magnitude,
	})
end

--[[
	Request knockback on players near a position (for AoE)
	@param position Vector3 - Center of the knockback
	@param radius number - Radius to affect
	@param magnitude number - Knockback strength
	@param excludePlayer Player? - Player to exclude (usually self)
]]
function KnockbackController:RequestAoEKnockback(position, radius, magnitude, excludePlayer)
	for _, player in Players:GetPlayers() do
		if player ~= excludePlayer and player.Character then
			local root = player.Character:FindFirstChild("Root") or player.Character.PrimaryPart
			if root then
				local dist = (root.Position - position).Magnitude
				if dist <= radius then
					local direction = (root.Position - position)
					if direction.Magnitude < 0.1 then
						direction = Vector3.new(0, 1, 0)
					end
					self:RequestKnockbackOnPlayer(player, direction, magnitude)
				end
			end
		end
	end
end

return KnockbackController
