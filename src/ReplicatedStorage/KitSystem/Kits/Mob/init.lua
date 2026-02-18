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
local RunService = game:GetService("RunService")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Hitbox = require(Locations.Shared.Util:WaitForChild("Hitbox"))

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local WALL_CONFIG = {
	-- Wall size (collision box)
	WALL_SIZE = Vector3.new(17.497, 18.003, 5.331),
	
	-- Placement validation (client uses 75, add buffer for latency)
	MAX_PLACEMENT_DISTANCE = 150,
	
	-- Knockback on spawn (client applies knockback, server just validates)
	KNOCKBACK_RADIUS = 12.5,
	KNOCKBACK_UPWARD = 120,
	KNOCKBACK_OUTWARD = 30,
	
	-- Rise timing - wall is non-collidable during rise animation
	RISE_DURATION = 0.5,  -- Seconds before collision enables
	
	-- Grace period - time before cooldown auto-starts
	GRACE_PERIOD = 3,     -- Seconds to use push before cooldown kicks in
	
	-- Push projectile physics
	PUSH_SPEED = 80,              -- Initial speed
	PUSH_UPWARD = 25,             -- Slight upward arc
	PUSH_GRAVITY = 0.6,           -- Gravity multiplier (lower = more floaty)
	PUSH_LIFETIME = 4,            -- Max seconds before despawn
	
	-- Impact damage/knockback
	IMPACT_RADIUS = 10,           -- Sphere radius on impact
	IMPACT_DAMAGE = 20,           -- Damage to players in impact radius
	IMPACT_KNOCKBACK = 70,        -- Knockback strength
	IMPACT_UPWARD = 50,           -- Upward knockback component
}

-- Allowed VFX actions for relay
local ALLOWED_RELAY_ACTIONS = {
	arm = true,
	charge = true,
	start = true,
	pushStart = true,
	pushCharge = true,
	push = true,
	projectileImpact = true,
	wallPushed = true,
}

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local Kit = {}
Kit.__index = Kit

function Kit.new(ctx)
	local self = setmetatable({}, Kit)
	self._ctx = ctx
	self._activeWall = nil
	self._activeWallVisual = nil        -- Reference to visual model
	self._visualDestroyConn = nil       -- Connection to disconnect on push
	self._graceThread = nil             -- Thread for delayed cooldown
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
		return character:FindFirstChild("Root") 
			or character:FindFirstChild("HumanoidRootPart") 
			or character.PrimaryPart
	end
	return nil
end

local function getKitRegistry(self)
	local service = self._ctx and self._ctx.service
	return service and service._registry or nil
end

local function getPlayerPosition(self, player)
	local registry = getKitRegistry(self)
	if registry then
		local replicationService = registry:TryGet("ReplicationService")
		if replicationService and replicationService.PlayerStates then
			local playerData = replicationService.PlayerStates[player]
			if playerData and playerData.LastState and playerData.LastState.Position then
				return playerData.LastState.Position
			end
		end
	end
	
	local root = getPlayerRoot(player)
	if root then
		return root.Position
	end
	
	return nil
end

local function getEffectsFolder()
	-- Parent to workspace.World.Map for organization
	local worldFolder = workspace:FindFirstChild("World")
	local mapFolder = worldFolder and worldFolder:FindFirstChild("Map")
	
	if mapFolder then
		local folder = mapFolder:FindFirstChild("Effects")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Effects"
			folder.Parent = mapFolder
		end
		return folder
	end
	
	-- Fallback to workspace.Effects
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

	service:BroadcastVFXMatchScoped(player, "MobAbility", payload, functionName, true)
end

--------------------------------------------------------------------------------
-- Wall Management
--------------------------------------------------------------------------------

function Kit:_cancelGraceThread()
	if self._graceThread then
		task.cancel(self._graceThread)
		self._graceThread = nil
	end
end

function Kit:_startGraceTimer()
	-- Cancel any existing timer
	self:_cancelGraceThread()
	
	local player = self._ctx.player
	local service = self._ctx.service
	
	-- Start delayed cooldown
	self._graceThread = task.delay(WALL_CONFIG.GRACE_PERIOD, function()
		self._graceThread = nil
		-- Grace period expired - start cooldown
		if service then
			service:StartCooldown(player)
		end
	end)
end

function Kit:_destroyActiveWall(skipCooldown)
	local player = self._ctx.player
	
	-- Cancel grace timer
	self:_cancelGraceThread()

	-- Capture visual reference first; if missing, try deterministic fallback.
	local wallVisual = self._activeWallVisual
	if not wallVisual and player then
		local effectsFolder = workspace:FindFirstChild("Effects")
		if effectsFolder then
			wallVisual = effectsFolder:FindFirstChild("MobWallVisual_" .. tostring(player.UserId))
		end
	end
	
	-- Disconnect visual connection
	if self._visualDestroyConn then
		self._visualDestroyConn:Disconnect()
		self._visualDestroyConn = nil
	end
	
	if self._activeWall and self._activeWall.Parent then
		self._activeWall:Destroy()
	end
	if wallVisual and wallVisual.Parent then
		wallVisual:Destroy()
	end
	self._activeWall = nil
	self._activeWallVisual = nil
	
	if player then
		player:SetAttribute("MobActiveWallId", nil)
	end
end

function Kit:_spawnWall(pivot)
	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	if not character then return nil end
	
	local playerPosition = getPlayerPosition(self, player)
	if not playerPosition then return nil end
	
	if typeof(pivot) ~= "CFrame" then return nil end
	
	local distance = (pivot.Position - playerPosition).Magnitude
	if distance > WALL_CONFIG.MAX_PLACEMENT_DISTANCE then return nil end
	
	-- Destroy previous wall if exists (don't trigger cooldown on replace)
	self:_cancelGraceThread()
	if self._activeWall and self._activeWall.Parent then
		self._activeWall:Destroy()
	end
	self._activeWall = nil
	
	-- Create collision part (invisible, non-collidable during rise)
	local wall = Instance.new("Part")
	wall.Name = "MobWall_" .. tostring(player.UserId)
	wall.Size = WALL_CONFIG.WALL_SIZE
	wall.CFrame = pivot * CFrame.new(0, WALL_CONFIG.WALL_SIZE.Y / 2, 0)
	wall.Anchored = true
	wall.CanCollide = false  -- Starts non-collidable, enabled after rise
	wall.CanQuery = true
	wall.CanTouch = true
	wall.Material = Enum.Material.Slate
	wall.Color = Color3.fromRGB(100, 85, 70)
	wall.Transparency = 1
	
	-- Tags for detection
	CollectionService:AddTag(wall, "MobWall")
	CollectionService:AddTag(wall, "DestructibleByAbility")
	CollectionService:AddTag(wall, "BlocksProjectiles")
	
	-- Attributes
	wall:SetAttribute("OwnerUserId", player.UserId)
	wall:SetAttribute("SpawnTime", os.clock())
	wall:SetAttribute("WallId", player.UserId .. "_" .. os.clock())
	
	-- Parent to effects folder
	local effectsFolder = getEffectsFolder()
	wall.Parent = effectsFolder
	
	-- Create visual model from WallModel
	local wallVisual;
	local wallModelTemplate = script:FindFirstChild("WallModel")
	if wallModelTemplate then
		wallVisual = wallModelTemplate:Clone()
		wallVisual.Name = "MobWallVisual_" .. tostring(player.UserId)
		wallVisual:SetAttribute("OwnerUserId", player.UserId)
		
		-- Position at pivot
		if wallVisual.PrimaryPart or wallVisual:FindFirstChild("Root") then
			wallVisual:PivotTo(pivot)
		else
			local firstPart = wallVisual:FindFirstChildWhichIsA("BasePart")
			if firstPart then
				wallVisual:PivotTo(pivot)
			end
		end
		
		wallVisual.Parent = effectsFolder
		wall:SetAttribute("VisualId", wallVisual.Name)
		
		-- Store visual reference for push
		self._activeWallVisual = wallVisual
		
		-- Play RockAnim animation on the rig
		local rig = wallVisual:FindFirstChild("Rig")
		if rig then
			local animController = rig:FindFirstChildWhichIsA("AnimationController") 
				or rig:FindFirstChildWhichIsA("Humanoid")
			if animController then
				local animator = animController:FindFirstChildWhichIsA("Animator")
				if not animator then
					animator = Instance.new("Animator")
					animator.Parent = animController
				end
				
				-- Find the animation (RockAnim is directly under script)
				local rockAnim = script:FindFirstChild("RockAnim")
				
				if rockAnim then
					local track = animator:LoadAnimation(rockAnim)
					track:Play()
				end
			end
		end
		
		-- Connect visual destruction to collision destruction (stored so we can disconnect on push)
		self._visualDestroyConn = wall.Destroying:Connect(function()
			if wallVisual and wallVisual.Parent then
				wallVisual:Destroy()
			end
		end)
	else
		wall.Transparency = 0  -- Make visible if no model
	end
	
	-- Store reference
	self._activeWall = wall
	player:SetAttribute("MobActiveWallId", wall:GetAttribute("WallId"))
	
	-- Enable collision after rise animation completes
	task.delay(WALL_CONFIG.RISE_DURATION, function()
		if wall and wall.Parent then
			wall.CanCollide = true
		end
	end)
	
	-- Listen for wall destruction (by abilities or external forces)
	local destroyConn
	destroyConn = wall.Destroying:Connect(function()
		if self._activeWall == wall then
			self._activeWall = nil
			player:SetAttribute("MobActiveWallId", nil)
			
			-- Cancel grace timer and start cooldown
			self:_cancelGraceThread()
			local service = self._ctx.service
			if service then
				service:StartCooldown(player)
			end
		end
		destroyConn:Disconnect()
	end)
	
	-- Start grace period timer (cooldown after GRACE_PERIOD unless pushed)
	self:_startGraceTimer()
	
	return wall, wallVisual
end

--------------------------------------------------------------------------------
-- Wall Push
--------------------------------------------------------------------------------

local function toVector3(data)
	if typeof(data) == "Vector3" then
		return data
	end
	if type(data) == "table" and data.X and data.Y and data.Z then
		return Vector3.new(data.X, data.Y, data.Z)
	end
	return nil
end


function Kit:_pushWall(direction)
	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	local wall = self._activeWall
	if not wall or not wall.Parent then return false end
	
	-- Cancel grace timer immediately
	self:_cancelGraceThread()
	
	-- IMPORTANT: Disconnect visual destruction connection BEFORE destroying wall
	if self._visualDestroyConn then
		self._visualDestroyConn:Disconnect()
		self._visualDestroyConn = nil
	end
	
	-- Get the visual model
	local wallVisual = self._activeWallVisual
	local effectsFolder = getEffectsFolder()
	
	-- Normalize direction
	if not direction or direction.Magnitude < 0.1 then
		direction = Vector3.new(0, 0, -1)
	else
		direction = direction.Unit
	end
	
	-- First, destroy all welds/constraints so pieces can fly independently
	if wallVisual then
		for _, child in ipairs(wallVisual:GetDescendants()) do
			if child:IsA("Weld") 
				or child:IsA("WeldConstraint") 
				or child:IsA("Motor6D") 
				or child:IsA("Constraint")
				or child:IsA("JointInstance") then
				child:Destroy()
			end
		end
	end
	
	-- Get all pieces from the visual model
	local pieces = {}
	if wallVisual then
		for _, child in ipairs(wallVisual:GetDescendants()) do
			if child:IsA("BasePart") then
				table.insert(pieces, child)
			end
		end
	end
	
	-- Also include the collision box as a piece if no visual
	if #pieces == 0 then
		table.insert(pieces, wall)
	end
	
	-- Reparent visual to effects (keep pieces alive)
	if wallVisual then
		wallVisual.Parent = effectsFolder
	end
	
	-- Destroy collision box
	wall:Destroy()
	self._activeWall = nil
	self._activeWallVisual = nil
	player:SetAttribute("MobActiveWallId", nil)
	
	-- Get services
	local registry = getKitRegistry(self)
	local weaponService = registry and registry:TryGet("WeaponService")
	local knockbackService = registry and registry:TryGet("KnockbackService")
	
	-- Raycast params - exclude caster and effects
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { character, effectsFolder }
	
	-- Also exclude colliders folder
	local collidersFolder = workspace:FindFirstChild("Colliders")
	if collidersFolder then
		table.insert(filterList, collidersFolder)
	end
	rayParams.FilterDescendantsInstances = filterList
	
	-- Gravity constant
	local gravity = workspace.Gravity * WALL_CONFIG.PUSH_GRAVITY
	
	-- Launch each piece as a proper projectile
	for i, piece in ipairs(pieces) do
		-- Make piece anchored (we control movement manually)
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		
		-- Store original position
		local position = piece.Position
		
		-- Calculate initial velocity with spread
		local spread = Vector3.new(
			(math.random() - 0.5) * 0.5,
			(math.random() - 0.5) * 0.3,
			(math.random() - 0.5) * 0.5
		)
		local pieceDir = (direction + spread).Unit
		local velocity = pieceDir * WALL_CONFIG.PUSH_SPEED + Vector3.new(0, WALL_CONFIG.PUSH_UPWARD, 0)
		
		-- Track state
		local elapsed = 0
		local destroyed = false
		local hitTargets = {}
		
		-- Impact function - creates explosion hitbox
		local function onImpact(hitPosition, hitInstance)
			if destroyed then return end
			destroyed = true
			
			-- Create impact pivot (at hit position, facing travel direction)
			local impactPivot = CFrame.lookAt(hitPosition, hitPosition + pieceDir)
		
			-- Use Hitbox utility to find ALL characters (players AND dummies)
			-- GetCharactersInRadius uses ReplicationService for accurate server-side positions
			local targets = Hitbox.GetCharactersInRadius(hitPosition, WALL_CONFIG.IMPACT_RADIUS, player)
			
			for _, targetChar in ipairs(targets) do
				if hitTargets[targetChar] then continue end
				hitTargets[targetChar] = true
				
				-- Get target position for knockback direction
				local targetRoot = targetChar:FindFirstChild("Root") 
					or targetChar:FindFirstChild("HumanoidRootPart")
					or targetChar.PrimaryPart
				local targetPosition = targetRoot and targetRoot.Position or hitPosition
				
				-- DAMAGE (handles players AND dummies)
				if weaponService then
					weaponService:ApplyDamageToCharacter(
						targetChar, 
						WALL_CONFIG.IMPACT_DAMAGE, 
						player,              -- shooter
						false,               -- isHeadshot
						"MobWallImpact",     -- weaponId
						hitPosition,         -- source position
						hitPosition          -- hit position
					)
				end
				
				-- KNOCKBACK (handles players AND dummies via character Model)
				if knockbackService then
					local awayDir = (targetPosition - hitPosition)
					awayDir = Vector3.new(awayDir.X, 0, awayDir.Z)
					if awayDir.Magnitude > 0.1 then
						awayDir = awayDir.Unit
					else
						awayDir = pieceDir
					end
					
					-- Add upward component
					local knockbackDir = (awayDir + Vector3.new(0, 0.5, 0)).Unit
					knockbackService:ApplyKnockback(targetChar, knockbackDir, WALL_CONFIG.IMPACT_KNOCKBACK)
				end
			end
			
			-- Fire VFX to all clients
			relayMobVfx(self, player, "Execute", {
				Character = character,
				forceAction = "projectileImpact",
				Pivot = impactPivot,
			})
			
			-- Destroy piece
			if piece and piece.Parent then
				piece:Destroy()
			end
		end
		
		-- Heartbeat simulation
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			if destroyed then
				connection:Disconnect()
				return
			end
			
			-- Update elapsed time
			elapsed = elapsed + dt
			if elapsed >= WALL_CONFIG.PUSH_LIFETIME then
				destroyed = true
				connection:Disconnect()
				if piece and piece.Parent then
					piece:Destroy()
				end
				return
			end
			
			-- Apply gravity to velocity
			velocity = velocity + Vector3.new(0, -gravity * dt, 0)
			
			-- Calculate movement this frame
			local moveVector = velocity * dt
			local newPosition = position + moveVector
			
			-- Raycast from old to new position
			local rayResult = workspace:Raycast(position, moveVector, rayParams)
			
			if rayResult then
				-- Hit something!
				onImpact(rayResult.Position, rayResult.Instance)
				connection:Disconnect()
			else
				-- No hit - update position
				position = newPosition
				piece.CFrame = CFrame.new(position) * CFrame.Angles(
					math.rad(elapsed * 180), 
					math.rad(elapsed * 90), 
					0
				) -- Spin for visual effect
			end
		end)
	end
	
	-- Cleanup visual model container after pieces despawn
	if wallVisual then
		Debris:AddItem(wallVisual, WALL_CONFIG.PUSH_LIFETIME + 1)
	end
	
	-- Start cooldown
	local service = self._ctx.service
	if service then
		service:StartCooldown(player)
	end
	
	return true
end

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
	if not character then return false end
	
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
		if typeof(pivot) ~= "CFrame" then return false end
		
		local wall, wt = self:_spawnWall(pivot)
		if not wall then return false end
		
		-- Relay spawn VFX to other clients
		relayMobVfx(self, player, "Execute", {
			Character = character,
			forceAction = "wallSpawned",
			Pivot = pivot,
			Wall = wt
		})

		return false
		
	elseif action == "relayUserVfx" then
		handleUserVfxRelay(self, clientData)
		return false
		
	elseif action == "pushStarted" then
		-- Cancel grace timer - push animation has started
		self:_cancelGraceThread()
		return false

	elseif action == "pushWall" then
		local direction = toVector3(clientData.direction)

		-- Get wall position BEFORE pushing (since push destroys it)
		local wallPosition = self._activeWall and self._activeWall.Position or Vector3.zero

		local success = self:_pushWall(direction)

		if success then
			-- Create pivot at wall origin facing throw direction
			local pivot = CFrame.lookAt(wallPosition, wallPosition + direction)

			-- Relay push VFX to other clients
			relayMobVfx(self, player, "Execute", {
				Character = character,
				forceAction = "wallPushed",
				Pivot = pivot,
			})
		end

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

