--[[
	Exit Gadget
	
	A gadget that teleports players back to the lobby/world spawn and unloads area gadgets.
	
	Model structure:
	- Model (with GadgetType = "Exit" or in Exits folder)
		- Leave (Part) - Touch trigger to exit
		- Spawn (Part) - Where incoming players spawn (used by AreaTeleport)
		- Root (Part, optional) - Visual/anchor
	
	Model attributes:
	- SourceArea (string, optional) - Area to unload on client (auto-detected if not set)
]]

local CollectionService = game:GetService("CollectionService")
local GadgetBase = require(script.Parent:WaitForChild("GadgetBase"))

local Exit = setmetatable({}, { __index = GadgetBase })
Exit.__index = Exit

function Exit.new(params)
	local self = setmetatable(GadgetBase.new(params), Exit)
	self._touchConnection = nil
	return self
end

function Exit:onServerCreated()
	-- Server just validates and handles teleportation
end

function Exit:onClientCreated()
	local model = self.model
	if not model then return end

	local leavePart = model:FindFirstChild("Leave")
	if not leavePart or not leavePart:IsA("BasePart") then
		return
	end

	local localPlayer = self.context and self.context.localPlayer
	if not localPlayer then return end

	self._touchConnection = leavePart.Touched:Connect(function(hit)
		self:_onTouched(hit, localPlayer)
	end)
end

function Exit:_onTouched(hit, localPlayer)
	local character = localPlayer.Character
	if not character then return end

	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	if not hit:IsDescendantOf(character) and hit ~= root then
		return
	end

	-- Debounce
	if self._exiting then return end
	self._exiting = true

	-- Request exit from server
	local net = self.context and self.context.net
	if net then
		net:FireServer("GadgetUseRequest", self.id, {})
	end

	-- Reset debounce after a delay
	task.delay(1, function()
		self._exiting = false
	end)
end

function Exit:onUseRequest(player, _payload)
	print("[EXIT GADGET] onUseRequest called for player:", player.Name)
	print("[EXIT GADGET] traceback:", debug.traceback())
	
	local character = player.Character
	if not character then
		return { approved = false }
	end

	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
	if not root then
		return { approved = false }
	end

	-- Find World/Spawn/Spawn
	local world = workspace:FindFirstChild("World")
	local spawnFolder = world and world:FindFirstChild("Spawn")
	local spawnPart = spawnFolder and spawnFolder:FindFirstChild("Spawn")
	
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return { approved = false }
	end

	-- Calculate spawn position with random offset based on spawn size
	local size = spawnPart.Size
	local offset = Vector3.new(
		(math.random() - 0.5) * size.X,
		0,
		(math.random() - 0.5) * size.Z
	)
	local spawnCFrame = spawnPart.CFrame * CFrame.new(offset)

	-- Determine source area to tell client to unload
	local sourceArea = self.model:GetAttribute("SourceArea")
	
	if not sourceArea then
		-- Auto-detect from mapInstance
		if self.mapInstance then
			sourceArea = self.mapInstance.Name
		else
			-- Fallback: Check model parent hierarchy for area folder
			local current = self.model
			while current and current ~= workspace do
				local parent = current.Parent
				if parent and parent.Name == "Gadgets" then
					local areaFolder = parent.Parent
					if areaFolder then
						sourceArea = areaFolder.Name
					end
					break
				end
				current = parent
			end
		end
	end

	-- Remove player from training match
	local registry = self.context and self.context.registry
	local roundService = registry and registry:TryGet("Round")
	if roundService then
		roundService:RemovePlayer(player)
	end

	-- Clear player's match state so they can re-enter training
	local matchService = registry and registry:TryGet("MatchService")
	if matchService and matchService.ClearPlayerState then
		matchService:ClearPlayerState(player)
	end

	-- Update player state to Lobby
	player:SetAttribute("PlayerState", "Lobby")

	-- Destroy Mob wall for player leaving training
	do
		-- Get all effects folders (workspace.World.Map.Effects and workspace.Effects)
		local effectsFolders = {}
		local worldFolder = workspace:FindFirstChild("World")
		local mapFolder = worldFolder and worldFolder:FindFirstChild("Map")
		if mapFolder then
			local effects = mapFolder:FindFirstChild("Effects")
			if effects then table.insert(effectsFolders, effects) end
		end
		local legacyEffects = workspace:FindFirstChild("Effects")
		if legacyEffects then table.insert(effectsFolders, legacyEffects) end
		
		local walls = CollectionService:GetTagged("MobWall")
		for _, wall in walls do
			if wall:GetAttribute("OwnerUserId") == player.UserId then
				local visualId = wall:GetAttribute("VisualId")
				if type(visualId) == "string" and visualId ~= "" then
					for _, effectsFolder in effectsFolders do
						local visual = effectsFolder:FindFirstChild(visualId)
						if visual then
							visual:Destroy()
							break
						end
					end
				end
				wall:Destroy()
			end
		end
		-- Fallback cleanup for any orphaned visual model
		for _, effectsFolder in effectsFolders do
			local orphanVisual = effectsFolder:FindFirstChild("MobWallVisual_" .. tostring(player.UserId))
			if orphanVisual then
				orphanVisual:Destroy()
			end
		end
	end

	-- Fire ReturnToLobby so UIController hides HUD
	local net = self.context and self.context.net
	if net then
		net:FireClient("ReturnToLobby", player, {})
	end

	return { 
		approved = true, 
		data = { 
			sourceArea = sourceArea,
			spawnPosition = spawnCFrame.Position,
			spawnLookVector = spawnCFrame.LookVector,
		} 
	}
end

function Exit:onUseResponse(approved, responseData)
	if not approved or not responseData then
		return
	end

	local spawnPos = responseData.spawnPosition
	local lookVector = responseData.spawnLookVector
	local registry = self.context and self.context.registry

	-- Teleport first
	if spawnPos then
		local movementController = registry and registry:TryGet("Movement")
		
		if movementController and type(movementController.Teleport) == "function" then
			movementController:Teleport(spawnPos, lookVector)
		end
	end

	-- Update client state to lobby (reset all training-related state)
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InLobby", true)
		player:SetAttribute("PlayerState", "Lobby")
		player:SetAttribute("TrainingMode", nil)
	end

	-- Fire ReturnToLobby event to UIController (via net if available)
	local net = self.context and self.context.net
	-- Note: ReturnToLobby is server->client, so we manually trigger UI update
	-- The UIController will handle this when it receives the state change

	-- Delay unload until AFTER teleport completes (teleport takes 0.1s)
	local sourceArea = responseData.sourceArea
	if sourceArea then
		task.delay(0.2, function()
			local gadgetController = registry and registry:TryGet("GadgetController")
			
			if gadgetController and type(gadgetController.UnloadArea) == "function" then
				gadgetController:UnloadArea(sourceArea)
			end
		end)
	end
end

function Exit:destroy()
	if self._touchConnection then
		self._touchConnection:Disconnect()
		self._touchConnection = nil
	end
	self.model = nil
end

return Exit
