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

	-- Get GadgetService to find destination
	local registry = self.context and self.context.registry
	local gadgetService = registry and registry:TryGet("GadgetService")
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

	-- Teleport player (anchor briefly to prevent physics fighting)
	local wasAnchored = root.Anchored
	root.Anchored = true
	root.CFrame = spawnCFrame
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	task.defer(function()
		root.Anchored = wasAnchored
	end)

	-- Load destination area gadgets for this player
	gadgetService:LoadAreaForPlayer(player, destAreaId)

	return { approved = true, data = { areaId = destAreaId } }
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
	-- Client-side: Handle response (teleport already happened server-side)
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
