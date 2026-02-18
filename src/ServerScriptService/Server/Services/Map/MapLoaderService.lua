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
	print("[MAPLOADER] LoadMap called - mapId:", mapId, "position:", position)
	
	local mapTemplate = self._mapsFolder:FindFirstChild(mapId)
	if not mapTemplate then
		warn("[MAPLOADER] ERROR: Map template not found for mapId:", mapId)
		warn("[MAPLOADER] Available maps in ServerStorage.Maps:")
		for _, child in self._mapsFolder:GetChildren() do
			warn("  -", child.Name, "(" .. child.ClassName .. ")")
		end
		return nil
	end
	
	print("[MAPLOADER] Found map template:", mapTemplate.Name, "class:", mapTemplate.ClassName)
	
	local clonedMap = mapTemplate:Clone()
	if not clonedMap then
		warn("[MAPLOADER] ERROR: Failed to clone map template")
		return nil
	end
	
	clonedMap.Name = mapId .. "_" .. tostring(tick())
	
	if clonedMap:IsA("Model") and clonedMap.PrimaryPart then
		local currentPos = clonedMap.PrimaryPart.Position
		local offset = position - currentPos
		print("[MAPLOADER] Using PrimaryPart pivot - currentPos:", currentPos, "offset:", offset)
		clonedMap:PivotTo(clonedMap:GetPivot() + offset)
	else
		local basePart = clonedMap:FindFirstChildWhichIsA("BasePart", true)
		if basePart then
			local currentPos = basePart.Position
			local offset = position - currentPos
			print("[MAPLOADER] Using basePart fallback - currentPos:", currentPos, "offset:", offset)
			for _, part in clonedMap:GetDescendants() do
				if part:IsA("BasePart") then
					part.Position = part.Position + offset
				end
			end
		else
			warn("[MAPLOADER] WARNING: No PrimaryPart or BasePart found for positioning")
		end
	end
	
	-- Parent to workspace.World.Map
	local worldFolder = workspace:FindFirstChild("World")
	local mapFolder = worldFolder and worldFolder:FindFirstChild("Map")
	clonedMap.Parent = mapFolder or workspace
	print("[MAPLOADER] Map parented to:", clonedMap.Parent:GetFullName())
	
	local spawns = self:GetSpawns(clonedMap)
	print("[MAPLOADER] Spawns found - Team1:", spawns.Team1 and spawns.Team1:GetFullName() or "NIL", 
		"Team2:", spawns.Team2 and spawns.Team2:GetFullName() or "NIL")
	
	if spawns.Team1 then
		local pos1 = spawns.Team1:IsA("BasePart") and spawns.Team1.Position or spawns.Team1:GetPivot().Position
		print("[MAPLOADER] Team1 spawn position:", pos1)
	end
	if spawns.Team2 then
		local pos2 = spawns.Team2:IsA("BasePart") and spawns.Team2.Position or spawns.Team2:GetPivot().Position
		print("[MAPLOADER] Team2 spawn position:", pos2)
	end
	
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
	print("[MAPLOADER] GetSpawns called for:", mapInstance.Name)
	
	local spawns = {
		Team1 = nil,
		Team2 = nil,
	}
	
	-- Method 1: Check SpawnLocations folder
	local spawnLocations = mapInstance:FindFirstChild("SpawnLocations")
	if spawnLocations then
		print("[MAPLOADER] Found SpawnLocations folder")
		local spawn1 = spawnLocations:FindFirstChild("Spawn1")
		local spawn2 = spawnLocations:FindFirstChild("Spawn2")
		
		if spawn1 then
			spawns.Team1 = spawn1
			print("[MAPLOADER] Method 1: Found Spawn1 in SpawnLocations:", spawn1:GetFullName())
		end
		if spawn2 then
			spawns.Team2 = spawn2
			print("[MAPLOADER] Method 1: Found Spawn2 in SpawnLocations:", spawn2:GetFullName())
		end
	else
		print("[MAPLOADER] No SpawnLocations folder found")
	end
	
	-- Method 2: Search descendants for Spawn1/Spawn2/SpawnTeam1/SpawnTeam2
	if not spawns.Team1 or not spawns.Team2 then
		print("[MAPLOADER] Method 2: Searching descendants for spawn names...")
		for _, child in mapInstance:GetDescendants() do
			if child.Name == "Spawn1" or child.Name == "SpawnTeam1" then
				if not spawns.Team1 then
					spawns.Team1 = child
					print("[MAPLOADER] Method 2: Found Team1 spawn:", child:GetFullName())
				end
			elseif child.Name == "Spawn2" or child.Name == "SpawnTeam2" then
				if not spawns.Team2 then
					spawns.Team2 = child
					print("[MAPLOADER] Method 2: Found Team2 spawn:", child:GetFullName())
				end
			end
		end
	end
	
	-- Method 3: Fallback - use any Part/Model with "Spawn" in name
	if not spawns.Team1 or not spawns.Team2 then
		print("[MAPLOADER] Method 3: Fallback search for anything with 'spawn' in name...")
		local fallbackSpawns = {}
		for _, child in mapInstance:GetDescendants() do
			if (child:IsA("BasePart") or child:IsA("Model")) and string.find(child.Name:lower(), "spawn") then
				table.insert(fallbackSpawns, child)
				print("[MAPLOADER] Method 3: Found potential spawn:", child.Name, "at", child:GetFullName())
			end
		end
		if not spawns.Team1 and fallbackSpawns[1] then
			spawns.Team1 = fallbackSpawns[1]
			print("[MAPLOADER] Method 3: Using fallback for Team1:", fallbackSpawns[1]:GetFullName())
		end
		if not spawns.Team2 and (fallbackSpawns[2] or fallbackSpawns[1]) then
			spawns.Team2 = fallbackSpawns[2] or fallbackSpawns[1]
			print("[MAPLOADER] Method 3: Using fallback for Team2:", (fallbackSpawns[2] or fallbackSpawns[1]):GetFullName())
		end
	end
	
	-- Final warning if spawns not found
	if not spawns.Team1 then
		warn("[MAPLOADER] WARNING: No Team1 spawn found for map:", mapInstance.Name)
	end
	if not spawns.Team2 then
		warn("[MAPLOADER] WARNING: No Team2 spawn found for map:", mapInstance.Name)
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
