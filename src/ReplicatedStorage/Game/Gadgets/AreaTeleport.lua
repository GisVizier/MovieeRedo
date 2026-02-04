--[[
	AreaTeleport Gadget
	
	A gadget that teleports players to a destination area and loads that area's gadgets.
	
	Model structure:
	- Model (with GadgetType = "AreaTeleport" or in ShootingRange folder)
		- Entrance (Part) - Touch trigger to teleport
		- Root (Part, optional) - Visual/anchor
	
	Model attributes:
	- DestinationArea (string) - Area folder name (e.g., "TrainingArea")
	- SpawnFolder (string, optional) - Subfolder in destination's Gadgets to find spawn points (e.g., "Exits")
]]

local GadgetBase = require(script.Parent:WaitForChild("GadgetBase"))

local AreaTeleport = setmetatable({}, { __index = GadgetBase })
AreaTeleport.__index = AreaTeleport

function AreaTeleport.new(params)
	local self = setmetatable(GadgetBase.new(params), AreaTeleport)
	self._touchConnection = nil
	return self
end

function AreaTeleport:onServerCreated()
	-- Server just validates and handles teleportation
end

function AreaTeleport:onClientCreated()
	local model = self.model
	if not model then return end

	local entrance = model:FindFirstChild("Entrance") or model:FindFirstChild("Enter")
	if not entrance or not entrance:IsA("BasePart") then
		return
	end

	local localPlayer = self.context and self.context.localPlayer
	if not localPlayer then return end

	self._touchConnection = entrance.Touched:Connect(function(hit)
		self:_onTouched(hit, localPlayer)
	end)
end

function AreaTeleport:_onTouched(hit, localPlayer)
	local character = localPlayer.Character
	if not character then return end

	-- Check if the hit part belongs to the local player
	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local hitParent = hit.Parent
	if hitParent ~= character and hit ~= root then
		-- Check if hit is a child of character (like a limb)
		if not hit:IsDescendantOf(character) then
			return
		end
	end

	-- Don't trigger if player is already in Training (prevent re-triggering)
	local playerState = localPlayer:GetAttribute("PlayerState")
	if playerState == "Training" then
		return
	end

	-- Debounce - only trigger once per teleport
	if self._teleporting then return end
	self._teleporting = true

	-- Request teleport from server
	local net = self.context and self.context.net
	if net then
		net:FireServer("GadgetUseRequest", self.id, {})
	end

	-- Reset debounce after a delay
	task.delay(1, function()
		self._teleporting = false
	end)
end

function AreaTeleport:onUseRequest(player, _payload)
	-- Server-side: Handle teleportation
	local model = self.model
	if not model then
		return { approved = false }
	end

	local destAreaId = model:GetAttribute("DestinationArea")
	if not destAreaId or destAreaId == "" then
		return { approved = false }
	end

	local character = player.Character
	if not character then
		return { approved = false }
	end

	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
	if not root then
		return { approved = false }
	end

	-- Get services
	local registry = self.context and self.context.registry
	local gadgetService = registry and registry:TryGet("GadgetService")
	local roundService = registry and registry:TryGet("Round")
	local matchService = registry and registry:TryGet("MatchService")
	local net = self.context and self.context.net

	if not gadgetService then
		return { approved = false }
	end

	-- Get destination area folder
	local destFolder = gadgetService:GetAreaFolder(destAreaId)
	if not destFolder then
		return { approved = false }
	end

	-- Find spawn point in destination
	local spawnCFrame = self:_findSpawnInArea(destFolder)
	if not spawnCFrame then
		return { approved = false }
	end

	-- Check if player is already in the training match
	local isInMatch = roundService and roundService:IsPlayerInMatch(player)
	
	-- Load destination area gadgets for this player
	gadgetService:LoadAreaForPlayer(player, destAreaId)
	
	if not isInMatch then
		-- Player needs to select loadout after teleporting
		-- Store pending entry data in MatchService
		if matchService then
			matchService:SetPendingTrainingEntry(player, {
				areaId = destAreaId,
			})
		end
		
		-- Return with requiresLoadout flag - client will teleport THEN show loadout
		return {
			approved = true,
			data = {
				requiresLoadout = true,
				areaId = destAreaId,
				spawnPosition = spawnCFrame.Position,
				spawnLookVector = spawnCFrame.LookVector,
			}
		}
	end

	-- Player already in match - just teleport
	return { 
		approved = true, 
		data = { 
			areaId = destAreaId,
			spawnPosition = spawnCFrame.Position,
			spawnLookVector = spawnCFrame.LookVector,
		} 
	}
end

function AreaTeleport:_findSpawnInArea(areaFolder)
	-- Look for spawn points in the Gadgets/Exits folder (or SpawnFolder attribute)
	local spawnFolderName = self.model:GetAttribute("SpawnFolder") or "Exits"
	
	local gadgetsFolder = areaFolder:FindFirstChild("Gadgets")
	if not gadgetsFolder then
		return nil
	end

	local spawnFolder = gadgetsFolder:FindFirstChild(spawnFolderName)
	if not spawnFolder then
		return nil
	end

	-- Collect all spawn points from Exit models
	local spawns = {}
	for _, exitModel in ipairs(spawnFolder:GetChildren()) do
		if exitModel:IsA("Model") then
			local spawnPart = exitModel:FindFirstChild("Spawn")
			if spawnPart and spawnPart:IsA("BasePart") then
				table.insert(spawns, spawnPart)
			end
		end
	end

	if #spawns == 0 then
		return nil
	end

	-- Pick random spawn and apply random offset within bounds
	local spawnPart = spawns[math.random(1, #spawns)]
	local size = spawnPart.Size
	local offset = Vector3.new(
		(math.random() - 0.5) * size.X,
		0,
		(math.random() - 0.5) * size.Z
	)

	return spawnPart.CFrame * CFrame.new(offset)
end

function AreaTeleport:onUseResponse(approved, responseData)
	if not approved or not responseData then
		return
	end

	local spawnPos = responseData.spawnPosition
	local lookVector = responseData.spawnLookVector
	local registry = self.context and self.context.registry
	local net = self.context and self.context.net

	-- Stop any active emotes before teleporting
	if net then
		net:FireServer("EmoteStop")
	end

	-- Teleport player first
	if spawnPos then
		local movementController = registry and registry:TryGet("Movement")
		
		if movementController and type(movementController.Teleport) == "function" then
			movementController:Teleport(spawnPos, lookVector)
		end
	end

	-- If requiresLoadout is set, show loadout UI after teleporting
	if responseData.requiresLoadout then
		-- Small delay to let teleport settle before showing UI
		task.delay(0.15, function()
			if net then
				-- Fire event to UIController to show loadout
				-- We do this client-side since server already sent the approval
				local Players = game:GetService("Players")
				local player = Players.LocalPlayer
				if player then
					-- Trigger the ShowTrainingLoadout flow via attribute (UIController watches this)
					player:SetAttribute("_showTrainingLoadout", responseData.areaId or "TrainingArea")
				end
			end
		end)
	end
end

function AreaTeleport:destroy()
	if self._touchConnection then
		self._touchConnection:Disconnect()
		self._touchConnection = nil
	end
	-- Don't destroy the model - it's part of the map
	self.model = nil
end

return AreaTeleport
