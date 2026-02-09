--[[
	KnockbackService.lua
	Server-side knockback handling
	
	Handles knockback requests from clients for:
	- Other players (relays to their client)
	- Dummies/NPCs (applies velocity directly since server owns them)
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local KnockbackService = {}

KnockbackService._registry = nil
KnockbackService._net = nil

local MAX_KNOCKBACK_MAGNITUDE = 500  -- Increased for strong knockbacks like Fling
local DEFAULT_PLAYER_ROOT_MASS = 70
local NPC_MASS_SCALE_MIN = 1
local NPC_MASS_SCALE_MAX = 8

function KnockbackService:Init(registry, net)
	self._registry = registry
	self._net = net
	
	-- Listen for knockback requests from clients
	self._net:ConnectServer("KnockbackRequest", function(player, data)
		self:_handleKnockbackRequest(player, data)
	end)
end

function KnockbackService:Start()
	-- Nothing to do on start
end

local function getRootFromCharacter(character: Model?)
	if not character then return nil end
	return character:FindFirstChild("Root") or character.PrimaryPart
end

local function getRootMass(root: BasePart?)
	if not root then
		return 0
	end

	local mass = root.AssemblyMass
	if typeof(mass) ~= "number" or mass <= 0 then
		return 0
	end

	return mass
end

local function getSourcePlayerMass(sourcePlayer: Player)
	local character = sourcePlayer and sourcePlayer.Character
	local root = getRootFromCharacter(character)
	local mass = getRootMass(root)
	if mass > 0 then
		return mass
	end
	return DEFAULT_PLAYER_ROOT_MASS
end

local function getNpcKnockbackScale(sourcePlayer: Player, npcRoot: BasePart)
	local npcMass = getRootMass(npcRoot)
	if npcMass <= 0 then
		return NPC_MASS_SCALE_MIN
	end

	local playerMass = getSourcePlayerMass(sourcePlayer)
	local scale = playerMass / npcMass
	return math.clamp(scale, NPC_MASS_SCALE_MIN, NPC_MASS_SCALE_MAX)
end

--[[
	Handle knockback request from a client
	
	Data format (velocity-based - new):
	{
		targetType = "player" | "dummy",
		targetUserId = number (for players),
		targetName = string (for dummies),
		velocity = { X, Y, Z },  -- Direct velocity to apply
		preserveMomentum = number,
	}
	
	Data format (direction-based - legacy):
	{
		targetType = "player" | "dummy",
		targetUserId = number (for players),
		targetName = string (for dummies),
		direction = { X, Y, Z },
		magnitude = number,
		preserveMomentum = number,
	}
]]
function KnockbackService:_handleKnockbackRequest(sourcePlayer: Player, data)
	if not data then return end
	
	local targetType = data.targetType or "player"
	local preserveMomentum = data.preserveMomentum or 0.0
	
	-- Check if using new velocity-based format
	if data.velocity then
		local velocity = data.velocity
		if not velocity.X or not velocity.Y or not velocity.Z then return end
		
		-- Cap velocity magnitude
		local vel = Vector3.new(velocity.X, velocity.Y, velocity.Z)
		if vel.Magnitude > MAX_KNOCKBACK_MAGNITUDE then
			vel = vel.Unit * MAX_KNOCKBACK_MAGNITUDE
		end
		
		if targetType == "player" then
			self:_handlePlayerKnockbackVelocity(sourcePlayer, data.targetUserId, vel, preserveMomentum)
		elseif targetType == "dummy" then
			self:_handleDummyKnockbackVelocity(sourcePlayer, data.targetName, vel, preserveMomentum)
		end
		return
	end
	
	-- Legacy direction+magnitude format
	local direction = data.direction
	if not direction or type(direction) ~= "table" then return end
	if not direction.X or not direction.Y or not direction.Z then return end
	
	local magnitude = math.min(data.magnitude or 50, MAX_KNOCKBACK_MAGNITUDE)
	
	if targetType == "player" then
		self:_handlePlayerKnockback(sourcePlayer, data.targetUserId, direction, magnitude, preserveMomentum)
	elseif targetType == "dummy" then
		self:_handleDummyKnockback(sourcePlayer, data.targetName, direction, magnitude)
	end
end

--[[
	Relay velocity-based knockback to another player's client (NEW)
]]
function KnockbackService:_handlePlayerKnockbackVelocity(sourcePlayer: Player, targetUserId: number, velocity: Vector3, preserveMomentum: number)
	if not targetUserId then return end
	
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		for _, player in Players:GetPlayers() do
			if player.UserId == targetUserId then
				targetPlayer = player
				break
			end
		end
	end
	
	if not targetPlayer then return end
	if targetPlayer == sourcePlayer then return end
	
	-- Relay to target player's client with velocity
	self._net:FireClient("Knockback", targetPlayer, {
		velocity = { X = velocity.X, Y = velocity.Y, Z = velocity.Z },
		preserveMomentum = preserveMomentum,
		sourceUserId = sourcePlayer.UserId,
	})
end

--[[
	Relay knockback to another player's client (LEGACY)
]]
function KnockbackService:_handlePlayerKnockback(sourcePlayer: Player, targetUserId: number, direction, magnitude: number, preserveMomentum: number)
	if not targetUserId then return end
	
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		-- Fallback for test clients with negative IDs
		for _, player in Players:GetPlayers() do
			if player.UserId == targetUserId then
				targetPlayer = player
				break
			end
		end
	end
	
	if not targetPlayer then return end
	
	-- Don't allow knockback on self through relay
	if targetPlayer == sourcePlayer then return end
	
	-- Relay to target player's client
	self._net:FireClient("Knockback", targetPlayer, {
		direction = direction,
		magnitude = magnitude,
		preserveMomentum = preserveMomentum,
		sourceUserId = sourcePlayer.UserId,
	})
end

--[[
	Find dummy by name (shared helper)
]]
function KnockbackService:_findDummy(targetName: string)
	if not targetName then return nil end
	
	-- Check in World/DummySpawns first
	local world = workspace:FindFirstChild("World")
	if world then
		local dummySpawns = world:FindFirstChild("DummySpawns")
		if dummySpawns then
			local dummy = dummySpawns:FindFirstChild(targetName)
			if dummy then return dummy end
		end
	end
	
	-- Fallback: check workspace root
	local dummy = workspace:FindFirstChild(targetName)
	if dummy then return dummy end
	
	-- Fallback: search by AimAssistTarget tag
	for _, tagged in CollectionService:GetTagged("AimAssistTarget") do
		if tagged.Name == targetName and tagged:IsA("Model") then
			return tagged
		end
	end
	
	return nil
end

--[[
	Apply velocity-based knockback to a dummy directly (NEW)
]]
function KnockbackService:_handleDummyKnockbackVelocity(sourcePlayer: Player, targetName: string, velocity: Vector3, preserveMomentum: number)
	local dummy = self:_findDummy(targetName)
	if not dummy or not dummy:IsA("Model") then return end
	
	local root = getRootFromCharacter(dummy)
	if not root then return end
	
	preserveMomentum = preserveMomentum or 0.0

	-- Light NPC roots can overreact; scale down by player-to-NPC mass ratio.
	local scale = getNpcKnockbackScale(sourcePlayer, root)
	local adjustedVelocity = velocity / scale

	-- Keep some existing horizontal momentum, same pattern as player knockback.
	local currentVel = root.AssemblyLinearVelocity
	local preserved = Vector3.new(currentVel.X, 0, currentVel.Z) * preserveMomentum
	root.AssemblyLinearVelocity = adjustedVelocity + preserved
end

--[[
	Apply knockback to a dummy directly (LEGACY - direction+magnitude)
]]
function KnockbackService:_handleDummyKnockback(sourcePlayer: Player, targetName: string, direction, magnitude: number)
	local dummy = self:_findDummy(targetName)
	if not dummy or not dummy:IsA("Model") then return end
	
	local root = getRootFromCharacter(dummy)
	if not root then return end
	
	-- Normalize direction
	local dir = Vector3.new(direction.X, direction.Y, direction.Z)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 1, 0)
	else
		dir = dir.Unit
	end
	
	-- Light NPC roots can overreact; scale down by player-to-NPC mass ratio.
	local scale = getNpcKnockbackScale(sourcePlayer, root)
	root.AssemblyLinearVelocity = (dir * magnitude) / scale
end

--[[
	Server-side API: Apply knockback to a character directly
	(For server-initiated knockback, e.g., from abilities or environmental hazards)
	
	@param character Model - The character to knockback
	@param direction Vector3 - Knockback direction
	@param magnitude number - Knockback strength
]]
function KnockbackService:ApplyKnockback(character: Model, direction: Vector3, magnitude: number)
	if not character then return end
	
	local root = getRootFromCharacter(character)
	if not root then return end
	
	-- Normalize direction
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(0, 1, 0)
	else
		direction = direction.Unit
	end
	
	magnitude = math.min(magnitude, MAX_KNOCKBACK_MAGNITUDE)
	
	-- Check if it's a player character
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		-- Send to player's client to apply
		self._net:FireClient("Knockback", player, {
			direction = { X = direction.X, Y = direction.Y, Z = direction.Z },
			magnitude = magnitude,
			sourceUserId = 0, -- Server-initiated
		})
	else
		-- Dummy/NPC - apply directly on server with mass compensation.
		local scale = math.clamp(DEFAULT_PLAYER_ROOT_MASS / math.max(getRootMass(root), 0.001), NPC_MASS_SCALE_MIN, NPC_MASS_SCALE_MAX)
		root.AssemblyLinearVelocity = (direction * magnitude) / scale
	end
end

return KnockbackService
