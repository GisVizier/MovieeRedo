--[[
	Mob Server Kit
	
	Handles server-side wall spawning, destruction, and validation.
	
	Wall Properties:
	- Spawned at client-specified pivot (validated)
	- Blocks projectiles (invisible to bullets but blocks ability hitboxes)
	- Tagged for destruction detection
	- One wall per player - new wall destroys old
	
	Actions:
	- spawnWall: Create wall at pivot location
	- pushWall: (TODO) Push wall forward, pieces become projectiles
	- relayUserVfx: Relay VFX to other clients
	
	Wall Destruction:
	- When destroyed by ability: triggers cooldown
	- When pushed by owner: pieces shoot forward with damage/knockback
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local WALL_CONFIG = {
	-- Wall size (placeholder part)
	WALL_SIZE = Vector3.new(22.659, 19.91, 7),
	
	-- Placement validation
	MAX_PLACEMENT_DISTANCE = 100,     -- Max distance from player to wall
	
	-- Knockback on spawn
	KNOCKBACK_RADIUS = 15,
	KNOCKBACK_UPWARD = 80,
	KNOCKBACK_OUTWARD = 40,
	
	-- Push (TODO)
	PUSH_UNLOCK_TIME = 3,
	PUSH_SPEED = 150,
	PUSH_DAMAGE = 25,
	PUSH_KNOCKBACK = 100,
}

-- Allowed VFX actions for relay
local ALLOWED_RELAY_ACTIONS = {
	arm = true,
	charge = true,
	start = true,
}

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local Kit = {}
Kit.__index = Kit

function Kit.new(ctx)
	local self = setmetatable({}, Kit)
	self._ctx = ctx
	self._activeWall = nil  -- Current active wall for this player
	return self
end

function Kit:SetCharacter(character)
	self._ctx.character = character
end

function Kit:Destroy()
	self:_destroyActiveWall()
end

function Kit:OnEquipped()
end

function Kit:OnUnequipped()
	self:_destroyActiveWall()
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getPlayerRoot(player)
	local character = player.Character
	if character then
		return character:FindFirstChild("HumanoidRootPart") 
			or character:FindFirstChild("Root") 
			or character.PrimaryPart
	end
	return nil
end

local function toVector3(data)
	if typeof(data) == "Vector3" then
		return data
	end
	if type(data) ~= "table" then
		return nil
	end
	if type(data.X) ~= "number" or type(data.Y) ~= "number" or type(data.Z) ~= "number" then
		return nil
	end
	return Vector3.new(data.X, data.Y, data.Z)
end

local function getKitRegistry(self)
	local service = self._ctx and self._ctx.service
	return service and service._registry or nil
end

local function getCombatService(self)
	local registry = getKitRegistry(self)
	return registry and registry:TryGet("CombatService") or nil
end

local function getEffectsFolder()
	local folder = workspace:FindFirstChild("Effects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = workspace
	end
	return folder
end

local function relayMobVfx(self, player, functionName, payload)
	local service = self._ctx and self._ctx.service
	if not service or not service.BroadcastVFXMatchScoped then
		return
	end
	service:BroadcastVFXMatchScoped(player, "Mob", payload, functionName, false)
end

--------------------------------------------------------------------------------
-- Wall Management
--------------------------------------------------------------------------------

function Kit:_destroyActiveWall()
	local player = self._ctx.player
	
	if self._activeWall and self._activeWall.Parent then
		self._activeWall:Destroy()
	end
	self._activeWall = nil
	
	-- Clear attribute
	if player then
		player:SetAttribute("MobActiveWallId", nil)
	end
end

function Kit:_spawnWall(pivot)
	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	if not character then return nil end
	
	local root = getPlayerRoot(player)
	if not root then return nil end
	
	-- Validate pivot
	if typeof(pivot) ~= "CFrame" then
		return nil
	end
	
	-- Validate distance
	local distance = (pivot.Position - root.Position).Magnitude
	if distance > WALL_CONFIG.MAX_PLACEMENT_DISTANCE then
		return nil
	end
	
	-- Destroy previous wall if exists
	self:_destroyActiveWall()
	
	-- Create wall part (placeholder - replace with Rocks model later)
	local wall = Instance.new("Part")
	wall.Name = "MobWall_" .. tostring(player.UserId)
	wall.Size = WALL_CONFIG.WALL_SIZE
	-- Position wall so bottom is at pivot, centered
	wall.CFrame = pivot * CFrame.new(0, WALL_CONFIG.WALL_SIZE.Y / 2, 0)
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = true
	wall.CanTouch = true
	wall.Material = Enum.Material.Slate
	wall.Color = Color3.fromRGB(100, 85, 70)
	wall.Transparency = 0
	
	-- Tags for detection
	CollectionService:AddTag(wall, "MobWall")
	CollectionService:AddTag(wall, "DestructibleByAbility")
	CollectionService:AddTag(wall, "BlocksProjectiles")
	
	-- Attributes
	wall:SetAttribute("OwnerUserId", player.UserId)
	wall:SetAttribute("SpawnTime", os.clock())
	wall:SetAttribute("WallId", player.UserId .. "_" .. os.clock())
	
	-- Parent to effects folder
	wall.Parent = getEffectsFolder()
	
	-- Store reference
	self._activeWall = wall
	player:SetAttribute("MobActiveWallId", wall:GetAttribute("WallId"))
	
	-- Apply knockback to nearby players
	self:_applySpawnKnockback(wall.CFrame.Position)
	
	-- Listen for wall destruction (by abilities)
	local destroyConn
	destroyConn = wall.Destroying:Connect(function()
		if self._activeWall == wall then
			self._activeWall = nil
			player:SetAttribute("MobActiveWallId", nil)
			
			-- Start cooldown when wall is destroyed
			local service = self._ctx.service
			if service then
				service:StartCooldown(player)
			end
		end
		destroyConn:Disconnect()
	end)
	
	return wall
end

function Kit:_applySpawnKnockback(position)
	local player = self._ctx.player
	local combatService = getCombatService(self)
	if not combatService then return end
	
	-- Find players in radius
	local registry = getKitRegistry(self)
	local characterService = registry and registry:TryGet("CharacterService")
	if not characterService then return end
	
	for _, targetPlayer in Players:GetPlayers() do
		if targetPlayer == player then continue end
		
		local targetChar = targetPlayer.Character
		if not targetChar then continue end
		
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") 
			or targetChar:FindFirstChild("Root")
		if not targetRoot then continue end
		
		local distance = (targetRoot.Position - position).Magnitude
		if distance > WALL_CONFIG.KNOCKBACK_RADIUS then continue end
		
		-- Calculate knockback direction
		local awayDir = (targetRoot.Position - position)
		awayDir = Vector3.new(awayDir.X, 0, awayDir.Z) -- Horizontal only
		if awayDir.Magnitude > 0.1 then
			awayDir = awayDir.Unit
		else
			awayDir = Vector3.new(1, 0, 0)
		end
		
		local knockbackVelocity = (awayDir * WALL_CONFIG.KNOCKBACK_OUTWARD) 
			+ Vector3.new(0, WALL_CONFIG.KNOCKBACK_UPWARD, 0)
		
		-- Apply knockback via combat service or character service
		if combatService.ApplyKnockback then
			combatService:ApplyKnockback(targetPlayer, knockbackVelocity)
		end
	end
end

--------------------------------------------------------------------------------
-- Wall Push (TODO - methods ready)
--------------------------------------------------------------------------------

--[[
function Kit:_pushWall()
	local wall = self._activeWall
	if not wall or not wall.Parent then return false end
	
	local player = self._ctx.player
	local camera direction would come from client...
	
	-- Get all children (Plane.001 - Plane.011)
	-- For each piece:
	--   - Unanchor
	--   - Apply velocity (forward + slight spread)
	--   - Enable gravity
	--   - On touch: damage + knockback + destruction
	
	self:_destroyActiveWall()
	return true
end
]]

--------------------------------------------------------------------------------
-- VFX Relay
--------------------------------------------------------------------------------

local function handleUserVfxRelay(self, clientData)
	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	if not character then return end
	
	local forceAction = clientData and clientData.forceAction
	if type(forceAction) ~= "string" or not ALLOWED_RELAY_ACTIONS[forceAction] then
		return
	end
	
	local payload = {
		Character = character,
		forceAction = forceAction,
	}
	
	if typeof(clientData.pivot) == "CFrame" then
		payload.pivot = clientData.pivot
		payload.Pivot = clientData.pivot
	end
	
	relayMobVfx(self, player, "User", payload)
end

--------------------------------------------------------------------------------
-- Kit Interface
--------------------------------------------------------------------------------

function Kit:OnAbility(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	
	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	if not character then
		return false
	end
	
	clientData = clientData or {}
	local action = clientData.action
	
	if action == "startCooldown" then
		local service = self._ctx.service
		if service then
			service:StartCooldown(player)
		end
		return false
		
	elseif action == "spawnWall" then
		local pivot = clientData.pivot
		if typeof(pivot) ~= "CFrame" then
			return false
		end
		
		local wall = self:_spawnWall(pivot)
		if not wall then
			return false
		end
		
		-- Relay spawn VFX to other clients
		relayMobVfx(self, player, "User", {
			Character = character,
			forceAction = "wallSpawned",
			Pivot = pivot,
		})
		
		return false  -- Don't end ability here, animation still playing
		
	elseif action == "relayUserVfx" then
		handleUserVfxRelay(self, clientData)
		return false
		
	elseif action == "pushWall" then
		-- TODO: Implement wall push
		-- self:_pushWall()
		return false
	end
	
	return false
end

function Kit:OnUltimate(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	return false
end

return Kit
