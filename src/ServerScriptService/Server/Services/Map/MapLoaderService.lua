--[[
	MapLoaderService
	
	Server-side service for loading and managing arena maps.
	Handles cloning maps from ServerStorage, positioning, and cleanup.
	
	API:
	- MapLoaderService:LoadMap(mapId, position) -> { instance, spawns }
	- MapLoaderService:UnloadMap(mapInstance) -> void
	- MapLoaderService:GetSpawns(mapInstance) -> { Team1 = spawn, Team2 = spawn }
	- MapLoaderService:GetAvailableMaps() -> { mapId, ... }
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MatchmakingConfig"))

local MapLoaderService = {}

function MapLoaderService:Init(registry, net)
	self._registry = registry
	self._net = net
	
	self._mapsFolder = ServerStorage:WaitForChild("Maps")
	self._loadedMaps = {}
end

function MapLoaderService:Start()
end

function MapLoaderService:LoadMap(mapId, position)
	local mapTemplate = self._mapsFolder:FindFirstChild(mapId)
	if not mapTemplate then
		return nil
	end
	
	local clonedMap = mapTemplate:Clone()
	if not clonedMap then
		return nil
	end
	
	clonedMap.Name = mapId .. "_" .. tostring(tick())
	
	if clonedMap:IsA("Model") and clonedMap.PrimaryPart then
		local currentPos = clonedMap.PrimaryPart.Position
		local offset = position - currentPos
		clonedMap:PivotTo(clonedMap:GetPivot() + offset)
	else
		local basePart = clonedMap:FindFirstChildWhichIsA("BasePart", true)
		if basePart then
			local currentPos = basePart.Position
			local offset = position - currentPos
			for _, part in clonedMap:GetDescendants() do
				if part:IsA("BasePart") then
					part.Position = part.Position + offset
				end
			end
		end
	end
	
	-- Parent to workspace.World.Map
	local worldFolder = workspace:FindFirstChild("World")
	local mapFolder = worldFolder and worldFolder:FindFirstChild("Map")
	clonedMap.Parent = mapFolder or workspace
	
	local spawns = self:GetSpawns(clonedMap)
	
	local mapData = {
		instance = clonedMap,
		spawns = spawns,
		mapId = mapId,
		position = position,
	}
	
	self._loadedMaps[clonedMap] = mapData
	
	-- Note: MapLoaded event removed - not used by clients and was broadcasting globally
	
	return mapData
end

function MapLoaderService:UnloadMap(mapInstance)
	if not mapInstance then
		return false
	end
	
	local mapData = self._loadedMaps[mapInstance]
	-- Note: MapUnloaded event removed - not used by clients and was broadcasting globally
	
	self._loadedMaps[mapInstance] = nil
	
	local success, err = pcall(function()
		mapInstance:Destroy()
	end)
	
	if not success then
		return false
	end
	
	return true
end

function MapLoaderService:GetSpawns(mapInstance)
	local spawns = {
		Team1 = nil,
		Team2 = nil,
	}
	
	local spawnLocations = mapInstance:FindFirstChild("SpawnLocations")
	if spawnLocations then
		local spawn1 = spawnLocations:FindFirstChild("Spawn1")
		local spawn2 = spawnLocations:FindFirstChild("Spawn2")
		
		if spawn1 then
			spawns.Team1 = spawn1
		end
		if spawn2 then
			spawns.Team2 = spawn2
		end
	end
	
	if not spawns.Team1 or not spawns.Team2 then
		for _, child in mapInstance:GetDescendants() do
			if child.Name == "Spawn1" or child.Name == "SpawnTeam1" then
				spawns.Team1 = child
			elseif child.Name == "Spawn2" or child.Name == "SpawnTeam2" then
				spawns.Team2 = child
			end
		end
	end
	
	-- Fallback: use any Part/Model with "Spawn" in name if standard spawns not found
	if not spawns.Team1 or not spawns.Team2 then
		local fallbackSpawns = {}
		for _, child in mapInstance:GetDescendants() do
			if (child:IsA("BasePart") or child:IsA("Model")) and string.find(child.Name:lower(), "spawn") then
				table.insert(fallbackSpawns, child)
			end
		end
		if not spawns.Team1 and fallbackSpawns[1] then
			spawns.Team1 = fallbackSpawns[1]
		end
		if not spawns.Team2 and (fallbackSpawns[2] or fallbackSpawns[1]) then
			spawns.Team2 = fallbackSpawns[2] or fallbackSpawns[1]
		end
	end
	
	return spawns
end

function MapLoaderService:GetAvailableMaps()
	local maps = {}
	
	for _, child in self._mapsFolder:GetChildren() do
		if child:IsA("Model") or child:IsA("Folder") then
			table.insert(maps, child.Name)
		end
	end
	
	return maps
end

function MapLoaderService:GetLoadedMaps()
	local maps = {}
	
	for mapInstance, mapData in self._loadedMaps do
		table.insert(maps, {
			instance = mapInstance,
			mapId = mapData.mapId,
			position = mapData.position,
		})
	end
	
	return maps
end

function MapLoaderService:IsMapLoaded(mapInstance)
	return self._loadedMaps[mapInstance] ~= nil
end

return MapLoaderService
