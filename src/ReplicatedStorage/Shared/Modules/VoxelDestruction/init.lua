-- Settings are in the Settings module

--[[

A voxel based destruction tool utilizing greedy meshing, function queueing, 
and EgoMoose's part splitter algorithm. Allows simple destruction as well as moveable hitbox destruction.

Please check out the DevForum page for more information on proper usage!
https://devforum.roblox.com/t/voxeldestruct-voxelated-destruction-physics-with-greedy-meshing-hitboxes-and-more/3044264

By: @ SalvatoreScripts
Last Updated: July 2025

Verion: 2.1

]]

type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
	-- optional: Fire, Once, DisconnectAll, etc.
}

export type _breaker = {
	Destroy: (
		focus: Part | MeshPart,
		parameters: OverlapParams?,
		voxelSize: number?,
		debrisCount: number?,
		reset: number?
	) -> ({ Part }, { Part }),

	Hitbox: (
		focus: Part | MeshPart,
		parameters: OverlapParams?,
		voxelSize: number?,
		debrisCount: number?,
		reset: number?
	) -> {
		Start: (self: any) -> nil,
		Stop: (self: any) -> nil,
		Fire: (self: any) -> nil,
		Destroy: (self: any) -> nil,
		IsActive: (self: any) -> boolean,
		GetRuntimeParts: (self: any) -> ({ Part }, { Part }),
		GetLifetimeParts: (self: any) -> ({ Part }, { Part }),

		Started: Signal<>,
		Stopped: Signal<>,
		Ceiling: Signal<>,
		Collision: Signal<{ Part }, { Part }>,
	},

	Cleanup: (parts: Part | { Part }) -> nil,

	Repair: (wall: Part | Model) -> nil,

	-- Reset all destruction for a round: repairs map, clears server state and __Destruction folder. Call after each round.
	ResetAll: (mapModel: Model?) -> nil,

	GreedyMesh: (parts: { Part }) -> { Part },

	Intersect: (part: Part | MeshPart, canvas: Part) -> (Part?, { Part }),
}

local Settings = require(script:WaitForChild("Settings"))
local Queuer = require(script:WaitForChild("Queue"))
local Voxelize = require(script:WaitForChild("Voxelize"))
local Mesh = require(script:WaitForChild("Mesh"))
local Signal = require(script:WaitForChild("Signal"))
local PartCache = require(script:WaitForChild("PartCache"))
local Clone = require(script:WaitForChild("PartCache"):WaitForChild("Clone"))

local RemoteName = "_ClientDestruction"
local Remote = nil
if Remote == nil and game:GetService("RunService"):IsServer() then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = RemoteName
	Remote.Parent = script
end
Remote = script:WaitForChild(RemoteName) :: RemoteEvent

local Settings = Settings
local Storage = {}
local Hitboxes = {}

local Cache = nil
if Settings.PartCache then
	container = Instance.new("Folder")
	container.Name = "VoxelCache"
	container.Parent = game:GetService("Workspace")

	local template = Instance.new("Part")
	template.Anchored = true
	template.CanQuery = false -- Voxel debris/pieces should not be hit by projectiles

	Cache = PartCache.new(template, Settings.CachePrecreated, container)
	Cache.ExpansionSize = Settings.CacheExtra

	template:Destroy()
end

function Cleanup(parts)
	local function destroyPart(part)
		if Cache and table.find(Cache.InUse, part) then
			Cache:ReturnPart(part)
		elseif Cache == nil or not table.find(Cache.InUse, part) and not table.find(Cache.Open, part) then
			part:Destroy()
		end
	end

	if typeof(parts) == "Instance" then
		destroyPart(parts)
	elseif typeof(parts) == "table" then
		for i, part in ipairs(parts) do
			destroyPart(part)
		end
	end
end

local RIGHT = Vector3.new(1, 0, 0)
local UP = Vector3.new(0, 1, 0)
local BACK = Vector3.new(0, 0, 1)

local function unsparse(array)
	if array ~= nil and typeof(array) == "table" and #array > 0 then
		local highestIndex = 0
		local numElements = 0

		for k in pairs(array) do
			if type(k) == "number" and k > 0 and k % 1 == 0 then
				highestIndex = math.max(highestIndex, k)
				numElements += 1
			end
		end

		local result = table.create(numElements)
		local resultN = 0

		for i = 1, highestIndex do
			local val = rawget(array, i)

			if val ~= nil then
				resultN += 1
				result[resultN] = val
			end
		end

		return result
	end
	return array
end

local function engulf(part: Part | MeshPart, canvas: Part)
	local canvasCF = canvas.CFrame
	local canvasSize = canvas.Size

	local targetCF = part.CFrame
	local targetSize = part.Size

	local corners = {
		targetCF * CFrame.new(-targetSize.X / 2, -targetSize.Y / 2, -targetSize.Z / 2).Position,
		targetCF * CFrame.new(-targetSize.X / 2, -targetSize.Y / 2, targetSize.Z / 2).Position,
		targetCF * CFrame.new(-targetSize.X / 2, targetSize.Y / 2, -targetSize.Z / 2).Position,
		targetCF * CFrame.new(-targetSize.X / 2, targetSize.Y / 2, targetSize.Z / 2).Position,
		targetCF * CFrame.new(targetSize.X / 2, -targetSize.Y / 2, -targetSize.Z / 2).Position,
		targetCF * CFrame.new(targetSize.X / 2, -targetSize.Y / 2, targetSize.Z / 2).Position,
		targetCF * CFrame.new(targetSize.X / 2, targetSize.Y / 2, -targetSize.Z / 2).Position,
		targetCF * CFrame.new(targetSize.X / 2, targetSize.Y / 2, targetSize.Z / 2).Position,
	}

	local minExtent = Vector3.new(math.huge, math.huge, math.huge)
	local maxExtent = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, corner in ipairs(corners) do
		local relativeCorner = canvasCF:PointToObjectSpace(corner)
		minExtent = Vector3.new(
			math.min(minExtent.X, relativeCorner.X),
			math.min(minExtent.Y, relativeCorner.Y),
			math.min(minExtent.Z, relativeCorner.Z)
		)
		maxExtent = Vector3.new(
			math.max(maxExtent.X, relativeCorner.X),
			math.max(maxExtent.Y, relativeCorner.Y),
			math.max(maxExtent.Z, relativeCorner.Z)
		)
	end

	local finalCF = canvasCF * CFrame.new((minExtent + maxExtent) / 2)
	local finalSize = (maxExtent - minExtent) / 2
	if part:IsA("Part") and part.Shape == Enum.PartType.Ball then
		finalSize = part.Size / 2
	end

	return finalCF, finalSize
end

local function vec3Func(f, v)
	return Vector3.new(f(v.x), f(v.y), f(v.z))
end

local function slice(part, cf, direction, axis, size2, sliceAxis)
	if part ~= nil then
		local wPoint = cf * ((direction * axis) * size2)

		local pSize, pCF = part.Size, part.CFrame
		local pRot = pCF - pCF.p

		local length = sliceAxis:Dot(pSize)
		local mSize = pSize - sliceAxis * length
		local max, min = length / 2, -length / 2
		local split = sliceAxis:Dot(pCF:PointToObjectSpace(wPoint))

		if split > min and split < max then
			local l1, l2 = max - split, split - min
			local p1, p2 = pCF * (sliceAxis * (l1 / 2 + split)), pCF * (sliceAxis * (-l2 / 2 + split))

			local part1 = part
			part1.CFrame = CFrame.new(p1) * pRot
			part1.Size = mSize + sliceAxis * l1

			local part2
			if Cache then
				part2 = Cache:GetPart(part1)
			elseif not Cache then
				part2 = part1:Clone()
			end

			part2.CFrame = CFrame.new(p2) * pRot
			part2.Size = mSize + sliceAxis * l2
			part2.Parent = part1.Parent

			if direction < 0 then
				return part1, part2
			elseif direction > 0 then
				return part2, part1
			end
		end

		return part
	end
end

function Intersect(part: Part | MeshPart, canvas: Part): (Part?, { Part })
	local cf, size2 = engulf(part, canvas)

	local parts = {}
	local enumAxis = { Enum.Axis.Y, Enum.Axis.X, Enum.Axis.Z }
	for _, enum in ipairs(enumAxis) do
		local axis = Vector3.FromAxis(enum)

		local sliceAxis = canvas.CFrame:VectorToObjectSpace(cf:VectorToWorldSpace(axis))
		sliceAxis = vec3Func(function(c)
			return math.min(1, math.abs(c))
		end, sliceAxis)

		if enum == Enum.Axis.Z and canvas ~= nil then
			local frontCanvas, back = slice(canvas, cf, -1, axis, size2, sliceAxis)
			if back ~= nil then
				table.insert(parts, back)
			end

			if frontCanvas ~= nil then
				canvas = frontCanvas
				local middleCanvas, front = slice(canvas, cf, 1, axis, size2, sliceAxis)
				if front ~= nil then
					table.insert(parts, front)
				end

				if middleCanvas ~= nil then
					canvas = middleCanvas
				end
			end
		elseif enum == Enum.Axis.Y then
			local topCanvas, bottom = slice(canvas, cf, -1, axis, size2, sliceAxis)
			if bottom ~= nil then
				table.insert(parts, bottom)
			end

			if topCanvas ~= nil then
				canvas = topCanvas
				local middleCanvas, top = slice(canvas, cf, 1, axis, size2, sliceAxis)
				if top ~= nil then
					table.insert(parts, top)
				end

				if middleCanvas ~= nil then
					canvas = middleCanvas
				end
			end
		elseif enum == Enum.Axis.X and canvas ~= nil then
			local rightCanvas, left = slice(canvas, cf, -1, axis, size2, sliceAxis)
			if left ~= nil then
				table.insert(parts, left)
			end

			if rightCanvas ~= nil then
				canvas = rightCanvas
				local middleCanvas, right = slice(canvas, cf, 1, axis, size2, sliceAxis)
				if right ~= nil then
					table.insert(parts, right)
				end

				if middleCanvas ~= nil then
					canvas = middleCanvas
				end
			end
		end
	end

	return canvas, parts
end

function GreedyMesh(parts: { Part }, mergeCache)
	return unsparse(Mesh:MergeParts(parts, nil, mergeCache))
end

function Repair(wall: Part | Model, __self: boolean?)
	local isClient = game:GetService("RunService"):IsClient()
	local clientID = if isClient then "Client" else ""

	if not wall:IsA("Model") and wall:GetAttribute("__" .. Settings.Tag .. clientID) ~= false then
		return
	end

	-- Client

	if not __self and game:GetService("RunService"):IsServer() and Settings.OnClient then
		Remote:FireAllClients("Repair", wall)

		if not Settings.OnServer then
			return
		end
	end

	--

	wall:SetAttribute(Settings.Tag .. "Timer" .. clientID, 0)

	if wall:IsA("Model") then
		for i, child in ipairs(wall:GetChildren()) do
			coroutine.resume(coroutine.create(function()
				if
					child:IsA("Model") and child:HasTag(Settings.Tag)
					or child:IsA("Part") and not child:HasTag(Settings.Tag .. "Piece")
				then
					Repair(child)
				end
			end))
		end

		return
	end

	local id = wall:GetAttribute("__VoxelDestructID" .. clientID)
	local folder = if id then workspace.Camera:FindFirstChild(id) else nil
	local parent = wall
	if game:GetService("RunService"):IsServer() and Settings.OnClient and Settings.OnServer and folder then
		parent = folder
	end

	-- Main logic

	for i, child in ipairs(parent:GetChildren()) do
		if child:HasTag(Settings.Tag .. "Piece") then
			Cleanup(child)
		end
	end

	wall.CanCollide = wall:GetAttribute("__OriginalCanCollide") or wall.CanCollide
	wall.Transparency = wall:GetAttribute("__OriginalTransparency") or wall.Transparency

	wall:SetAttribute("__" .. Settings.Tag .. clientID, true)

	--

	if parent and parent:IsA("Folder") then
		parent:Destroy()
	end
end

-- Reset all destruction (round end): repair map, clear Storage and __Destruction. Server-only.
function ResetAll(mapModel: Model?)
	if not game:GetService("RunService"):IsServer() then
		return
	end
	-- Repair all destroyed parts in the map. Repair(mapModel) only recurses into direct Model/Part
	-- children, but breakables can be nested under Folders. So we find every Part/Model with
	-- __Breakable == false (was destroyed) and Repair each.
	if mapModel and mapModel.Parent then
		for _, desc in ipairs(mapModel:GetDescendants()) do
			if (desc:IsA("Part") or desc:IsA("MeshPart") or desc:IsA("Model")) then
				if desc:GetAttribute("__" .. Settings.Tag) == false then
					Repair(desc)
				end
			end
		end
		-- Also run Repair on map root in case it has direct breakable children (covers both traversal paths)
		Repair(mapModel)
	end
	-- Clear server destruction state
	for id in pairs(Storage) do
		Storage[id] = nil
	end
	local destructionFolder = workspace:FindFirstChild("__Destruction")
	if destructionFolder then
		for _, child in ipairs(destructionFolder:GetChildren()) do
			child:Destroy()
		end
	end
end

function Destroy(
	focus: Part | MeshPart,
	parameters: OverlapParams?,
	voxelSize: number?,
	debrisCount: number?,
	reset: number?
)
	local isClient = game:GetService("RunService"):IsClient()
	local clientID = if isClient then "Client" else ""

	if focus:GetAttribute("__HitboxID") == nil and game:GetService("RunService"):IsServer() and Settings.OnClient then
		task.wait()
		Remote:FireAllClients("Destroy", focus, parameters, voxelSize, debrisCount, reset)

		if not Settings.RecordDestruction then
			return
		end
	end

	assert(
		focus ~= nil and typeof(focus) == "Instance" and (focus:IsA("Part") or focus:IsA("MeshPart")),
		"Parameter 'focus' must be of type instance and must be a Part or MeshPart."
	)

	if parameters == nil then
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = game:GetService("CollectionService"):GetTagged(Settings.Tag)
		params.RespectCanCollide = false
		parameters = params
	end
	if voxelSize ~= nil and voxelSize < 0 then
		voxelSize = 0
	end
	if debrisCount ~= nil and debrisCount < 0 then
		debrisCount = 0
	end
	if reset ~= nil and reset <= 0 then
		reset = Settings.ResetDefault
	elseif reset ~= nil and reset > 0 and reset < Settings.ResetMinimum then
		reset = Settings.ResetMinimum
	end

	local part = focus:Clone()
	for _, tag in ipairs(part:GetTags()) do
		part:RemoveTag(tag)
	end

	local size = focus.Size
	if voxelSize == nil then
		if Settings.Relativity then
			voxelSize = Settings.VoxelRelative * math.max(size.X, size.Y, size.Z)
		elseif not Settings.Relativity then
			voxelSize = Settings.VoxelDefault
		end
	end
	if voxelSize and voxelSize < Settings.VoxelMinimum then
		voxelSize = Settings.VoxelMinimum
	end

	local cframe = focus.CFrame
	if Settings.GridLock == true then
		cframe = cframe.Rotation
			+ Vector3.new(math.round(cframe.Position.X), math.round(cframe.Position.Y), math.round(cframe.Position.Z))
		size = Vector3.new(math.round(size.X), math.round(size.Y), math.round(size.Z))
		if voxelSize then
			voxelSize = math.round(voxelSize)
		end
	end

	if game:GetService("RunService"):IsServer() and Settings.OnClient == true then
		debrisCount = 0
	end

	part.Name = "Hitbox"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.Transparency = 1
	part.Locked = true

	part.CFrame = cframe
	part.Size = size
	part.Parent = game:GetService("Workspace")

	-- Store destruction info

	if Settings.RecordDestruction and game:GetService("RunService"):IsServer() and Settings.OnClient then
		if not workspace:FindFirstChild("__Destruction") then
			local folder = Instance.new("Folder")
			folder.Name = "__Destruction"
			folder.Parent = workspace
		end

		if not focus:GetAttribute("__DestructionID") then
			focus:SetAttribute("__DestructionID", game:GetService("HttpService"):GenerateGUID())
		end

		local id = focus:GetAttribute("__DestructionID")
		if not Storage[id] then
			focus.Destroying:Once(function()
				if Storage[id] and Storage[id].CFrames then
					local empty = true
					for i, _ in pairs(Storage[id].CFrames) do
						empty = false
						break
					end

					if empty then
						Storage[id] = nil
					end
				end
			end)

			local properties = {}

			if part:IsA("Part") then
				properties = { Size = part.Size, Shape = part.Shape }
			elseif part:IsA("MeshPart") then
				properties = { Size = part.Size, MeshId = part.MeshId }
			end

			Storage[id] = {
				Previous = nil,
				Properties = properties,
				CFrames = {},
				Models = {},
			}

			local clone = part:Clone()
			local cloneID = game:GetService("HttpService"):GenerateGUID()
			clone:SetAttribute("__DestructionID", cloneID)
			clone:AddTag(cloneID)
			clone.Name = cloneID
			clone.CanQuery = false -- Record destruction clones should not be hit by projectiles
			Storage[id].CFrames[cloneID] = {}
			Storage[id].Previous = cloneID
			clone.Parent = workspace:FindFirstChild("__Destruction") or workspace:WaitForChild("__Destruction")
		end

		if Storage[id] then
			local different = false
			for property, value in pairs(Storage[id].Properties) do
				if (focus :: any)[property] ~= nil and (focus :: any)[property] ~= value then
					different = true
					break
				end
			end

			if different then
				local clone = part:Clone()
				local cloneID = game:GetService("HttpService"):GenerateGUID()
				clone:SetAttribute("__DestructionID", cloneID)
				clone:AddTag(cloneID)
				clone.Name = cloneID
				clone.CanQuery = false -- Record destruction clones should not be hit by projectiles
				Storage[id].CFrames[cloneID] = {}
				Storage[id].Previous = cloneID
				clone.Parent = workspace:FindFirstChild("__Destruction") or workspace:WaitForChild("__Destruction")
			end
		end
	end

	--

	local debris, walls = {}, {}

	if not Settings.OnClient or game:GetService("RunService"):IsClient() or Settings.OnServer then
		for i, wall in ipairs(game:GetService("Workspace"):GetPartsInPart(part, parameters)) do
			-- Is part inside tagged model?

			local container = wall
			if
				not wall:HasTag(Settings.Tag)
				and not wall:HasTag(Settings.Tag .. "Piece")
				and wall:FindFirstAncestorOfClass("Model") ~= nil
				and wall:FindFirstAncestorOfClass("Model"):HasTag(Settings.Tag)
			then
				container = wall:FindFirstAncestorOfClass("Model")
			end

			if
				(container == wall or container:IsA("Model"))
				and wall:GetAttribute("__" .. Settings.Tag .. clientID) == nil
			then
				wall:SetAttribute("__" .. Settings.Tag .. clientID, true)
			end

			if not Settings.ResetModel then
				container = wall
			end

			-- Begin queue

			local isUnsupportedShape = wall:IsA("MeshPart")
				or wall:IsA("WedgePart")
				or wall:IsA("CornerWedgePart")
				or (wall:IsA("Part") and (wall.Shape == Enum.PartType.Wedge or wall.Shape == Enum.PartType.CornerWedge))

			if
				(wall:HasTag(Settings.Tag) or wall:GetAttribute("__" .. Settings.Tag .. clientID) ~= nil)
				and not isUnsupportedShape
				and not wall:HasTag(Settings.Tag .. "Piece")
				and wall:GetAttribute(Settings.Tag .. "Locked" .. clientID) ~= true
			then
				local queue = Queuer.Fetch(wall) or Queuer.New(wall, false)

				queue:Add(function()
					if not wall:GetAttribute("__OriginalCanCollide") then
						wall:SetAttribute("__OriginalCanCollide", wall.CanCollide)
					end
					if not wall:GetAttribute("__OriginalTransparency") then
						wall:SetAttribute("__OriginalTransparency", wall.Transparency)
					end

					local pieces = {}
					if wall:GetAttribute("__" .. Settings.Tag .. clientID) == true then
						wall:SetAttribute("__" .. Settings.Tag .. clientID, false)

						local piece
						if Cache then
							piece = Cache:GetPart(wall)
						elseif not Cache then
							piece = wall:Clone()
						end

						local originalTransparency = wall:GetAttribute("__OriginalTransparency")
						local originalCanCollide = wall:GetAttribute("__OriginalCanCollide")
						piece.Transparency = originalTransparency or piece.Transparency
						piece.CanCollide = originalCanCollide or piece.CanCollide

						Clone.wipeAttributes(piece)
						piece:AddTag(Settings.Tag .. "Piece")
						piece.CanQuery = false -- Voxel pieces should not be hit by projectiles

						if game:GetService("RunService"):IsServer() and Settings.OnClient and Settings.OnServer then
							local id = wall:GetAttribute("__VoxelDestructID" .. clientID)
							if not id then
								id = game:GetService("HttpService"):GenerateGUID()
								wall:SetAttribute("__VoxelDestructID" .. clientID, id)
							end

							local folder = workspace.Camera:FindFirstChild(id)
							if not folder then
								folder = Instance.new("Folder")

								wall.Destroying:Once(function()
									folder:Destroy()
								end)

								folder.Name = id
								folder.Parent = workspace.Camera
							end

							piece.Parent = folder
						else
							piece.Parent = wall
						end

						pieces = { piece }

						coroutine.resume(coroutine.create(function()
							if
								(
									game:GetService("RunService"):IsServer()
									or Settings.OnClient and not Settings.OnServer
								)
								and reset ~= nil
								and reset >= 0
							then
								if not container:GetAttribute(Settings.Tag .. "Locked" .. clientID) then
									container:SetAttribute(Settings.Tag .. "Locked" .. clientID, false)
								end

								if not container:GetAttribute(Settings.Tag .. "Freeze" .. clientID) then
									container:SetAttribute(Settings.Tag .. "Freeze" .. clientID, false)
								end

								if not container:GetAttribute(Settings.Tag .. "Destroy" .. clientID) then
									container:SetAttribute(Settings.Tag .. "Destroy" .. clientID, false)
								end

								if container:GetAttribute(Settings.Tag .. "Timer" .. clientID) == nil then
									container:SetAttribute(Settings.Tag .. "Timer" .. clientID, 0)
								end

								local timerInit = false
								if
									container:IsA("Part")
									or container:GetAttribute(Settings.Tag .. "Timer" .. clientID) == 0
								then
									timerInit = true
								end

								container:SetAttribute(Settings.Tag .. "Timer" .. clientID, math.floor(reset + 0.5))

								if not timerInit then
									return
								else
									repeat
										task.wait()
										repeat
											task.wait(1)
											if
												container:GetAttribute(Settings.Tag .. "Freeze" .. clientID)
													== false
												and container:GetAttribute(Settings.Tag .. "Timer" .. clientID) > 0
											then
												container:SetAttribute(
													Settings.Tag .. "Timer" .. clientID,
													container:GetAttribute(Settings.Tag .. "Timer" .. clientID) - 1
												)
											end
										until container:GetAttribute(Settings.Tag .. "Timer" .. clientID) <= 0

										if Settings.ResetYields then
											local found = {}
											if Settings.ResetModel and container:IsA("Model") then
												local cframe, size = container:GetBoundingBox()
												found = game:GetService("Workspace"):GetPartBoundsInBox(cframe, size)
											else
												found = game:GetService("Workspace"):GetPartsInPart(wall)
											end

											for i, found in ipairs(found) do
												if found.Parent:FindFirstChildOfClass("Humanoid") then
													container:SetAttribute(
														Settings.Tag .. "Timer" .. clientID,
														math.floor(reset + 0.5)
													)
													break
												end
											end
										end
									until container:GetAttribute(Settings.Tag .. "Timer" .. clientID) <= 0
								end

								Repair(container, true)

								if queue.IsRunning then
									queue.Completed:Wait()
								end
							end
						end))
					elseif wall:GetAttribute("__" .. Settings.Tag .. clientID) == false then
						if reset then
							wall:SetAttribute(Settings.Tag .. "Timer" .. clientID, reset)
						end

						local id = wall:GetAttribute("__VoxelDestructID" .. clientID)
						local folder = if id
							then workspace.Camera:FindFirstChild(wall:GetAttribute("__VoxelDestructID" .. clientID))
							else nil

						local parent = wall
						if
							game:GetService("RunService"):IsServer()
							and Settings.OnClient
							and Settings.OnServer
							and folder
						then
							parent = folder
						end

						if parent then
							local children = parent:GetChildren()

							if #children > 0 then
								local params = OverlapParams.new()
								params.FilterType = Enum.RaycastFilterType.Include
								params.FilterDescendantsInstances = children

								for i, found in ipairs(game:GetService("Workspace"):GetPartsInPart(part, params)) do
									if found:HasTag(Settings.Tag .. "Piece") then
										table.insert(pieces, found)
									end
								end
							end
						end
					end

					if #pieces > 0 then
						if wall:GetAttribute(Settings.Tag .. "OriginalCanCollide") then
							wall.CanCollide = wall:GetAttribute(Settings.Tag .. "OriginalCanCollide")
						end
						if wall:GetAttribute(Settings.Tag .. "OriginalTransparency") then
							wall.Transparency = wall:GetAttribute(Settings.Tag .. "OriginalTransparency")
						end

						local intersections = {}
						for i, cutPart in ipairs(pieces) do
							if cutPart and cutPart.Parent then
								local intersection, wallPiecez = Intersect(part, cutPart)

								if intersection ~= nil then
									table.insert(intersections, intersection)
								end
							end
						end

						local function handleDebris(debri)
							debri.Name = "Debris"
							debri.CanQuery = false
							game:GetService("CollectionService"):AddTag(debri, "Debris")
							debri.Parent = Settings.DebrisContainer
							table.insert(debris, debri)

							if Settings.DebrisDefaultBehavior == true then
								if Settings.DebrisAnchored == false then
									debri.Anchored = false

									if game:GetService("RunService"):IsServer() then
										debri:SetNetworkOwner(nil)
									end
								end

								if Settings.DebrisReset ~= nil and Settings.DebrisReset > 0 then
									debri:SetAttribute(Settings.Tag .. "Timer", Settings.DebrisReset)

									coroutine.resume(coroutine.create(function()
										repeat
											task.wait(1)
											debri:SetAttribute(
												Settings.Tag .. "Timer",
												debri:GetAttribute(Settings.Tag .. "Timer") - 1
											)
										until debri:GetAttribute(Settings.Tag .. "Timer") <= 0

										Cleanup(debri)
									end))
								end
							end
						end

						part.Size = part.Size * Settings.CutoutSize
						if voxelSize ~= nil and voxelSize > 0 then
							for i, voxelizeChild in ipairs(intersections) do
								if voxelizeChild and voxelizeChild.Parent then
									local newVoxels, newDebris =
										Voxelize.voxelize(voxelizeChild, voxelSize, Cache, debrisCount, #debris, part)

									if #newDebris > 0 then
										for i, debri in ipairs(newDebris) do
											handleDebris(debri)
										end
									end
								end
							end
						elseif voxelSize == 0 then
							local count = 0
							for i, intersection in ipairs(intersections) do
								if intersection and intersection.Parent then
									if debrisCount == nil or count < debrisCount then
										count += 1

										handleDebris(intersection)
									else
										Cleanup(intersection)
									end
								end
							end
						end

						local children = {}
						for i, child in ipairs(wall:GetChildren()) do
							if child:HasTag(Settings.Tag .. "Piece") then
								table.insert(children, child)
							end
						end

						if Settings.GreedyMeshing and #children > 0 then
							GreedyMesh(children, Cache)
						end

						wall.CanCollide = false
						wall.Transparency = 1

						-- Remove textures/decals from the now-invisible wall
						for _, child in ipairs(wall:GetChildren()) do
							if child:IsA("Texture") or child:IsA("Decal") or child:IsA("SurfaceAppearance") then
								child:Destroy()
							end
						end
					end
				end, true, true)

				table.insert(walls, wall)
			end

			-- Store models

			local id = focus:GetAttribute("__DestructionID")
			if
				container
				and container:IsA("Model")
				and Settings.ResetModel
				and Settings.RecordDestruction
				and Settings.OnClient
				and Storage[id]
				and Storage[id].Models[container] == nil
			then
				Storage[id].Models[container] = true
			end

			--
		end
	end

	-- Store cframe

	local id = focus:GetAttribute("__DestructionID")
	if
		Settings.RecordDestruction == true
		and game:GetService("RunService"):IsServer()
		and Settings.OnClient == true
		and id ~= nil
		and Storage[id] ~= nil
	then
		local storage = Storage[id]
		local previous = storage.Previous

		local clone = nil
		local tagged = if previous then game:GetService("CollectionService"):GetTagged(previous) else nil
		if tagged and #tagged > 0 then
			clone = tagged[1]
		end

		if previous and storage.CFrames[previous] then
			local cframes = storage.CFrames[previous]
			local cframe = part.CFrame
			cframes[cframe] = { VoxelSize = voxelSize, Parts = {} }

			for i, wall in ipairs(walls) do
				if wall and wall.Parent ~= nil and not cframes[cframe].Parts[wall] then
					cframes[cframe].Parts[wall] = true

					wall:GetAttributeChangedSignal(Settings.Tag):Once(function()
						if
							wall:GetAttribute("__" .. Settings.Tag) == true
							and Storage[id]
							and Storage[id].CFrames[previous]
							and Storage[id].CFrames[previous][cframe]
						then
							cframes[cframe].Parts[wall] = nil

							local empty = true
							for wall, _ in pairs(cframes[cframe].Parts) do
								empty = false
								break
							end

							if empty then
								cframes[cframe] = nil

								for cf, _ in pairs(storage.CFrames[previous]) do
									empty = false
									break
								end

								if empty then
									storage.CFrames[previous] = nil

									for id, _ in pairs(storage.CFrames) do
										empty = false
										break
									end

									if empty then
										clone:SetAttribute(Settings.Tag .. "Timer", 0)
									end
								end
							end
						end
					end)
				end
			end
		end

		if previous and clone and reset ~= nil and reset > 0 then
			if clone:GetAttribute(Settings.Tag .. "Timer") == nil then
				clone:SetAttribute(Settings.Tag .. "Timer", reset)

				coroutine.resume(coroutine.create(function()
					repeat
						task.wait()
						repeat
							task.wait(1)
							if clone:GetAttribute(Settings.Tag .. "Timer") > 0 then
								clone:SetAttribute(
									Settings.Tag .. "Timer",
									clone:GetAttribute(Settings.Tag .. "Timer") - 1
								)
							end
						until clone:GetAttribute(Settings.Tag .. "Timer") <= 0

						if Settings.ResetModel then
							local largest = nil

							for model, _ in pairs(storage.Models) do
								local modelTimer = model:GetAttribute(Settings.Tag .. "Timer")

								if model.Parent and modelTimer ~= nil and modelTimer > 0 then
									if largest == nil or modelTimer > largest:GetAttribute(Settings.Tag .. "Timer") then
										largest = model
									end
								else
									storage.Models[model] = nil
								end
							end

							local modelTimer = if largest then largest:GetAttribute(Settings.Tag .. "Timer") else nil
							if modelTimer then
								clone:SetAttribute(Settings.Tag .. "Timer", modelTimer)
							end
						end
					until clone:GetAttribute(Settings.Tag .. "Timer") <= 0

					local cloneID = clone:GetAttribute("__DestructionID")
					if cloneID then
						storage.CFrames[cloneID] = nil
					end
					clone:Destroy()
					if storage.Previous == previous then
						storage.Previous = nil
					end

					local empty = true
					for i, _ in pairs(storage.CFrames) do
						empty = false
						break
					end

					if empty then
						Storage[id] = nil
					end
				end))
			else
				clone:SetAttribute(Settings.Tag .. "Timer", reset)
			end
		end
	end

	--

	part:Destroy()

	return unsparse(debris), unsparse(walls)
end

local CreatingHitbox = nil
local Players = {}

function Hitbox(
	focus: Part | MeshPart,
	parameters: OverlapParams?,
	voxelSize: number?,
	debrisCount: number?,
	reset: number?
)
	task.wait()

	local isClient = game:GetService("RunService"):IsClient()
	local clientID = if isClient then "Client" else ""

	assert(
		focus ~= nil,
		"'Focus' parameter is nil."
			.. if game:GetService("RunService"):IsClient() then " Is it replicating to clients?" else ""
	)
	assert(
		focus:GetAttribute("__" .. Settings.Tag) == nil and focus:GetAttribute("__" .. Settings.Tag .. clientID) == nil,
		"Unable to create hitbox from destructable object."
	)
	assert(focus:GetAttribute("__HitboxID" .. clientID) == nil, "Instance is already a hitbox.")
	assert(
		focus and typeof(focus) == "Instance" and focus:IsA("Part")
			or focus and typeof(focus) == "Instance" and focus:IsA("MeshPart"),
		"Parameter 'focus' must be of type Instance [Part or Model]."
	)

	local timestamp = os.clock()
	CreatingHitbox = timestamp

	local hitbox = {}
	hitbox.focus = focus
	hitbox.limit = 0
	hitbox.auto = true
	hitbox.revert = false
	hitbox.distance = 0

	hitbox.parameters = parameters
	hitbox.voxelSize = voxelSize
	hitbox.debrisCount = debrisCount
	hitbox.reset = reset

	hitbox.active = false
	hitbox.queue = nil
	hitbox.collisions = 0
	hitbox.connections = {}
	hitbox.runDebris = {}
	hitbox.totalDebris = {}
	hitbox.runWalls = {}
	hitbox.totalWalls = {}

	hitbox.Started = Signal.new()
	hitbox.Stopped = Signal.new()
	hitbox.Collision = Signal.new()
	hitbox.Ceiling = Signal.new()

	-- Client initialize

	if game:GetService("RunService"):IsServer() and Settings.OnClient then
		if #game:GetService("Players"):GetChildren() == 0 then
			repeat
				task.wait()
			until #game:GetService("Players"):GetChildren() > 0
		end

		for i, player in pairs(game:GetService("Players"):GetChildren()) do
			coroutine.resume(coroutine.create(function()
				local token = Settings.Tag .. tostring(player.UserId)
				local queue = Queuer.Fetch(token) or Queuer.New(token)

				queue:Add(function()
					task.wait()
					Remote:FireClient(player, "Hitbox", focus, parameters, voxelSize, debrisCount, reset)
				end, false, Players[player] ~= nil)
			end))
		end
	end

	--

	function hitbox:IsActive()
		return hitbox.active ~= false
	end

	local function isAvailable(part)
		if part and part.Parent then
			if Cache and table.find(Cache.InUse, part) or not table.find(Cache.Open, part) or not Cache then
				return true
			end
		end
		return false
	end

	function hitbox:GetRuntimeParts()
		for i = #hitbox.runDebris, 1, -1 do
			if not isAvailable(hitbox.runDebris[i]) then
				table.remove(hitbox.runDebris, i)
			end
		end

		for i = #hitbox.runWalls, 1, -1 do
			if not isAvailable(hitbox.runWalls[i]) then
				table.remove(hitbox.runWalls, i)
			end
		end

		return unsparse(hitbox.runDebris), unsparse(hitbox.runWalls)
	end

	function hitbox:GetLifetimeParts()
		local runDebris, runWalls = hitbox:GetRuntimeParts()

		for i, debri in ipairs(runDebris) do
			if not table.find(hitbox.totalDebris, debri) then
				table.insert(hitbox.totalDebris, debri)
			end
		end

		for i, wall in ipairs(runWalls) do
			if not table.find(hitbox.totalWalls, wall) then
				table.insert(hitbox.totalWalls, wall)
			end
		end

		for i, debri in ipairs(hitbox.totalDebris) do
			if not isAvailable(debri) then
				table.remove(hitbox.totalDebris, table.find(hitbox.totalDebris, debri))
			end
		end

		for i, wall in ipairs(hitbox.totalWalls) do
			if isAvailable(wall) then
				table.remove(hitbox.totalDebris, table.find(hitbox.totalDebris, wall))
			end
		end

		return unsparse(hitbox.totalDebris), unsparse(hitbox.totalWalls), runDebris, runWalls
	end

	local function wipeConnections()
		if hitbox.connections ~= nil and #hitbox.connections > 0 then
			for i, connection in ipairs(hitbox.connections) do
				connection:Disconnect()
			end
			hitbox.connections = {}
		end
	end

	function hitbox:Stop()
		hitbox.active = false

		-- Client

		if game:GetService("RunService"):IsServer() and Settings.OnClient then
			for i, player in pairs(game:GetService("Players"):GetChildren()) do
				coroutine.resume(coroutine.create(function()
					local token = Settings.Tag .. tostring(player.UserId)
					local queue = Queuer.Fetch(token) or Queuer.New(token)

					queue:Add(function()
						task.wait()
						Remote:FireAllClients("Stop", focus)
					end, false, Players[player] ~= nil)
				end))
			end

			if not Settings.OnServer then
				return
			end
		end

		--

		if hitbox.connections ~= nil and #hitbox.connections > 0 then
			wipeConnections()

			if hitbox.revert then
				hitbox.collisions = 0
			end

			local i, o, debrisCopy, wallsCopy = hitbox:GetLifetimeParts()
			hitbox.runDebris, hitbox.runWalls = {}, {}

			coroutine.resume(coroutine.create(function()
				hitbox.Stopped:Fire(debrisCopy, wallsCopy)
			end))
		end
	end

	local function createDictionary(object: Instance): { [Part]: {} }
		local dictionary = {}

		if object:IsA("Part") or object:IsA("MeshPart") then
			dictionary[object] = object
		elseif object:IsA("Model") then
			for i, part in ipairs(object:GetDescendants()) do
				if part:IsA("Part") or part:IsA("MeshPart") then
					dictionary[part] = part
				end
			end
		end

		return dictionary
	end

	local dictionary = nil
	function hitbox:Fire(__self: boolean)
		assert(hitbox.focus, "Hitbox 'focus' cannot be nil.")

		-- Client

		if not __self and game:GetService("RunService"):IsServer() and Settings.OnClient then
			for i, player in pairs(game:GetService("Players"):GetChildren()) do
				coroutine.resume(coroutine.create(function()
					local token = Settings.Tag .. tostring(player.UserId)
					local queue = Queuer.Fetch(token) or Queuer.New(token)

					queue:Add(function()
						task.wait()
						Remote:FireClient(player, "Fire", focus)
					end, false, Players[player] ~= nil)
				end))
			end

			if not Settings.OnServer then
				return
			end
		end

		--

		if not dictionary then
			dictionary = createDictionary(hitbox.focus)
		end

		if hitbox.queue == nil or Queuer.Fetch(hitbox.focus) == nil then
			hitbox.queue = Queuer.Fetch(hitbox.focus) or Queuer.New(hitbox.focus, false)
		end

		if
			hitbox.limit == 0 and hitbox.queue ~= nil
			or hitbox.limit > 0 and hitbox.collisions < hitbox.limit and hitbox.queue ~= nil
		then
			hitbox.queue:Add(function()
				local totalDebris, totalWalls = {}, {}
				for part, data in pairs(dictionary or {}) do
					local debris, walls =
						Destroy(part, hitbox.parameters, hitbox.voxelSize, hitbox.debrisCount, hitbox.reset)

					for i, debri in ipairs(debris) do
						if not table.find(totalDebris, debri) then
							table.insert(totalDebris, debri)
						end
					end

					for i, wall in ipairs(walls) do
						if not table.find(totalWalls, wall) then
							table.insert(totalWalls, wall)
						end
					end
				end

				if #totalDebris > 0 then
					hitbox.collisions += 1

					for i, debri in ipairs(totalDebris) do
						if debri and not table.find(hitbox.runDebris, debri) then
							table.insert(hitbox.runDebris, debri)
						end
					end

					for i, wall in ipairs(totalWalls) do
						if wall and not table.find(hitbox.runWalls, wall) then
							table.insert(hitbox.runWalls, wall)
						end
					end

					coroutine.resume(coroutine.create(function()
						hitbox.Collision:Fire(totalDebris, totalWalls)
					end))

					if hitbox.limit and hitbox.collisions == hitbox.limit then
						if hitbox.auto == true then
							hitbox:Stop()
						end

						coroutine.resume(coroutine.create(function()
							hitbox.Ceiling:Fire()
						end))
					end
				end
			end, true, true)
		end

		dictionary = nil
	end

	local lastCFrame = nil
	local lastSize = nil
	local lastShape = nil
	local previousVoxelSize = nil
	local function updateVoxelSize()
		if hitbox.voxelSize ~= previousVoxelSize then
			if hitbox.voxelSize ~= nil and hitbox.voxelSize <= 0 then
				if Settings.Relativity then
					if hitbox.focus:IsA("Part") or hitbox.focus:IsA("MeshPart") then
						voxelSize = hitbox.voxelSize
						hitbox.voxelSize = Settings.VoxelRelative
							* math.max(hitbox.focus.Size.X, hitbox.focus.Size.Y, hitbox.focus.Size.Z)
					elseif hitbox.focus:IsA("Model") then
						voxelSize = hitbox.voxelSize
						local modelCFrame, modelSize = hitbox.focus:GetBoundingBox()
						hitbox.voxelSize = Settings.VoxelRelative * math.max(modelSize.X, modelSize.Y, modelSize.Z)
					end
				elseif not Settings.Relativity then
					voxelSize = hitbox.voxelSize
					hitbox.voxelSize = Settings.VoxelDefault
				end
			end
		end
	end
	updateVoxelSize()

	local function setPrimaryPart()
		if hitbox.focus:IsA("Model") and not hitbox.focus.PrimaryPart then
			local parts = {}
			for i, part in ipairs(hitbox.focus:GetDescendants()) do
				if part:IsA("Part") or part:IsA("MeshPart") then
					table.insert(parts, part)
				end
			end
			hitbox.focus.PrimaryPart = parts[math.random(1, #parts)]
		end
	end
	setPrimaryPart()

	function hitbox:Start()
		hitbox:Stop()

		assert(hitbox.focus, "Hitbox 'focus' cannot be nil.")
		hitbox.active = true

		coroutine.resume(coroutine.create(function()
			hitbox.Started:Fire()
		end))

		-- Client

		if game:GetService("RunService"):IsServer() and Settings.OnClient then
			for i, player in pairs(game:GetService("Players"):GetChildren()) do
				coroutine.resume(coroutine.create(function()
					local token = Settings.Tag .. tostring(player.UserId)
					local queue = Queuer.Fetch(token) or Queuer.New(token)

					queue:Add(function()
						task.wait()
						Remote:FireClient(player, "Start", focus)
					end, false, Players[player] ~= nil)
				end))
			end

			if not Settings.OnServer then
				return
			end
		end

		--

		local debounce = false
		local function Fire(bypass)
			if not debounce then
				debounce = true
				task.wait()

				setPrimaryPart()
				updateVoxelSize()

				local currentCFrame, currentSize, currentShape = nil, nil, nil
				if hitbox.focus:IsA("Part") then
					currentCFrame, currentSize, currentShape =
						hitbox.focus.CFrame, hitbox.focus.Size, hitbox.focus.Shape
				elseif hitbox.focus:IsA("MeshPart") then
					currentCFrame, currentSize, currentShape =
						hitbox.focus.CFrame, hitbox.focus.Size, hitbox.focus.MeshId
				elseif hitbox.focus:IsA("Model") then
					currentCFrame, currentSize = hitbox.focus:GetBoundingBox()
					if hitbox.focus.PrimaryPart:IsA("Part") then
						currentShape = hitbox.focus.PrimaryPart.Shape
					elseif hitbox.focus.PrimaryPart:IsA("MeshPart") then
						currentShape = hitbox.focus.PrimaryPart.MeshId
					end
				end

				local distanceUsed = 1
				if hitbox.distance ~= nil and hitbox.distance > 0 then
					distanceUsed = hitbox.distance
				elseif voxelSize ~= nil then
					distanceUsed = hitbox.voxelSize
				elseif voxelSize == nil then
					distanceUsed = math.max(currentSize.X, currentSize.Y, currentSize.Z) * Settings.HitboxRelative
				end

				if
					lastCFrame == nil
					or lastSize == nil
					or lastShape == nil
					or bypass
					or (currentCFrame.Position - lastCFrame.Position).Magnitude >= distanceUsed
					or math.abs(currentSize.X - lastSize.X) >= distanceUsed
					or math.abs(currentSize.Y - lastSize.Y) >= distanceUsed
					or math.abs(currentSize.Z - lastSize.Z) >= distanceUsed
					or currentShape ~= lastShape
				then
					lastCFrame = currentCFrame
					lastSize = currentSize
					lastShape = currentShape

					hitbox:Fire(true)
				end

				debounce = false
			end
		end
		Fire()

		if Settings.RunService or hitbox.focus.Anchored == false then
			hitbox.connections = {
				game:GetService("RunService").Heartbeat:Connect(function()
					Fire()
				end),
			}
		elseif not Settings.RunService then
			local function addConnections(part, excludeCFrame)
				if part:IsA("Part") then
					for i, connection in ipairs({
						part:GetPropertyChangedSignal("CFrame"):Connect(function()
							Fire()
						end),
						part:GetPropertyChangedSignal("Size"):Connect(function()
							Fire()
						end),
						part:GetPropertyChangedSignal("Shape"):Connect(function()
							Fire(true)
						end),
					}) do
						table.insert(hitbox.connections, connection)
					end
				elseif part:IsA("MeshPart") then
					for i, connection in ipairs({
						part:GetPropertyChangedSignal("CFrame"):Connect(function()
							Fire()
						end),
						part:GetPropertyChangedSignal("Size"):Connect(function()
							Fire()
						end),
						part:GetPropertyChangedSignal("MeshId"):Connect(function()
							Fire(true)
						end),
					}) do
						table.insert(hitbox.connections, connection)
					end
				end
			end

			if hitbox.focus:IsA("Part") or hitbox.focus:IsA("MeshPart") then
				addConnections(hitbox.focus)
			elseif hitbox.focus:IsA("Model") then
				for i, part in ipairs(hitbox.focus:GetDescendants()) do
					if part:IsA("Part") or part:IsA("MeshPart") then
						if part == hitbox.focus.PrimaryPart then
							addConnections(part)
						elseif part ~= hitbox.focus.PrimaryPart then
							addConnections(part)
						end
					end
				end
			end
		end
	end

	focus:SetAttribute("Limit", hitbox.limit)
	focus:SetAttribute("Auto", hitbox.auto)
	focus:SetAttribute("Revert", hitbox.revert)
	focus:SetAttribute("Distance", hitbox.distance)

	local attributeConnections = {
		focus:GetAttributeChangedSignal("Limit"):Connect(function()
			hitbox.limit = focus:GetAttribute("Limit")
		end),
		focus:GetAttributeChangedSignal("Auto"):Connect(function()
			hitbox.auto = focus:GetAttribute("Auto")
		end),
		focus:GetAttributeChangedSignal("Revert"):Connect(function()
			hitbox.revert = focus:GetAttribute("Revert")
		end),
		focus:GetAttributeChangedSignal("Distance"):Connect(function()
			hitbox.distance = focus:GetAttribute("Distance")
		end),
	}

	function hitbox:Destroy()
		Hitboxes[focus] = nil

		if hitbox.queue then
			hitbox.queue:Destroy()
		end
		hitbox:Stop()

		if focus:GetAttribute("__HitboxID") then
			focus:RemoveTag(focus:GetAttribute("__HitboxID"))
		end
		focus:SetAttribute("__HitboxID", nil)

		for i, connection in ipairs(attributeConnections) do
			connection:Disconnect()
		end
	end

	if not Hitboxes[focus] then
		Hitboxes[focus] = hitbox

		local id = game:GetService("HttpService"):GenerateGUID()
		focus:SetAttribute("__HitboxID", id)
		focus:AddTag(id)

		focus.Destroying:Once(function()
			hitbox:Destroy()
		end)
	end

	if CreatingHitbox == timestamp then
		CreatingHitbox = nil
	end

	return hitbox
end

coroutine.resume(coroutine.create(function()
	if game:GetService("RunService"):IsClient() then
		local player = game:GetService("Players").LocalPlayer

		Remote.OnClientEvent:Connect(function(key, ...)
			if key == "Destroy" then
				Destroy(...)
			elseif key == "Repair" then
				Repair(...)
			end

			if key == "Hitbox" or key == "Start" or key == "Stop" or key == "Fire" then
				local args = { ... }

				local token = tostring(player.UserId) .. "Hitbox"
				local queue = Queuer.Fetch(token) or Queuer.New(token)
				queue:Add(function()
					if key == "Hitbox" then
						Hitbox(table.unpack(args))
					elseif key == "Start" then
						local args = { table.unpack(args) }
						local focus = args[1]

						if focus and Hitboxes[focus] then
							Hitboxes[focus]:Start()
						end
					elseif key == "Stop" then
						local args = { table.unpack(args) }
						local focus = args[1]

						if focus and Hitboxes[focus] then
							Hitboxes[focus]:Stop()
						end
					elseif key == "Fire" then
						local args = { table.unpack(args) }
						local focus = args[1]

						if focus and Hitboxes[focus] then
							Hitboxes[focus]:Fire()
						end
					end
				end, nil, true)
			end

			if key == "Hitboxes" then
				task.wait()

				local args = { ... }
				local hitboxes = args[1]

				for id, hitbox in pairs(hitboxes) do
					coroutine.resume(coroutine.create(function()
						local focuses = game:GetService("CollectionService"):GetTagged(id)
						local focus = if focuses and #focuses > 0 then focuses[1] else nil

						if focus then
							local new = Hitbox(focus, table.unpack(hitbox[1]))
							task.wait()
							if hitbox[2] == true then
								new:Start()
							end
						end
					end))
				end
			elseif key == "Destruction" then
				task.wait()

				local args = { ... }
				local destruction = args[1]

				for id, cframes in pairs(destruction) do
					coroutine.resume(coroutine.create(function()
						local focuses = game:GetService("CollectionService"):GetTagged(id)
						local focus = if focuses and #focuses > 0 then focuses[1] else nil

						if focus then
							for _, cframe in pairs(cframes) do
								if cframe then
									focus.CFrame = cframe[1] or focus.CFrame
									Destroy(
										focus,
										nil,
										cframe[2] or 1,
										0,
										focus:GetAttribute(Settings.Tag .. "Timer") or 1
									)
								end
							end
						end
					end))
				end
			end
		end)

		repeat
			task.wait()
		until script:HasTag("ServerLoaded")
		task.wait()
		Remote:FireServer("Load")
	elseif game:GetService("RunService"):IsServer() then
		Remote.OnServerEvent:Connect(function(player, key)
			if key == "Load" and not Players[player] then
				local token = Settings.Tag .. tostring(player.UserId)
				local queue = Queuer.Fetch(token) or Queuer.New(token)
				queue:Run()

				Players[player] = queue
			end
		end)

		game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
			Players[player] = nil
		end)

		if Settings.OnClient and Settings.RecordDestruction then
			game:GetService("Players").PlayerAdded:Connect(function(player: Player)
				repeat
					task.wait()
				until CreatingHitbox == nil

				task.wait()
				local hitboxes = {}
				for focus, hitbox in pairs(Hitboxes) do
					if focus:GetAttribute("__HitboxID") ~= nil then
						hitboxes[focus:GetAttribute("__HitboxID")] = {
							{ hitbox.parameters, hitbox.voxelSize, hitbox.debrisCount, hitbox.reset },
							hitbox.active,
						}
					end
				end
				Remote:FireClient(player, "Hitboxes", hitboxes)

				task.wait()
				local destruction = {}
				for id, data in pairs(Storage) do
					for id, cframes in pairs(data.CFrames) do
						destruction[id] = {}

						for cframe, info in pairs(cframes) do
							table.insert(destruction[id], { cframe, info.VoxelSize })
						end
					end
				end
				Remote:FireClient(player, "Destruction", destruction)
			end)
		end

		script:AddTag("ServerLoaded")
	end
end))

local breaker: _breaker = {
	_Settings = Settings,
	_Storage = Settings,
	_Hitboxes = Hitboxes,
	_Cache = Cache,

	Destroy = Destroy,
	Hitbox = Hitbox,
	Cleanup = Cleanup,
	Repair = Repair,
	ResetAll = ResetAll,
	GreedyMesh = GreedyMesh,
	Intersect = Intersect,
}

return breaker
