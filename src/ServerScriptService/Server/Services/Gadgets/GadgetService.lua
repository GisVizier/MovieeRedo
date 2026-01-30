local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Gadgets = require(Locations.Game:WaitForChild("Gadgets"))
local GadgetBase = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("GadgetBase"))
local JumpPad = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("JumpPad"))
local Zipline = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("Zipline"))
local AreaTeleport = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("AreaTeleport"))
local Exit = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("Exit"))

local GadgetService = {}

function GadgetService:Init(registry, net)
	self._registry = registry
	self._net = net
	self._gadgetSystem = Gadgets.new()
	self._gadgetSystem:setFallbackClass(GadgetBase)
	self._gadgetsByMap = {}
	self._mapByGadgetId = {}
	self._loadedAreas = {} -- Track which areas have been scanned
	self._areaFolders = {} -- Map areaId -> folder instance

	self:Register("JumpPad", JumpPad)
	self:Register("Zipline", Zipline)
	self:Register("AreaTeleport", AreaTeleport)
	self:Register("Exit", Exit)

	self._net:ConnectServer("GadgetInitRequest", function(player)
		self:SendInitToPlayer(player)
	end)

	self._net:ConnectServer("GadgetUseRequest", function(player, gadgetId, payload)
		self:_onUseRequest(player, gadgetId, payload)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)
end

function GadgetService:Start()
	local world = workspace:FindFirstChild("World")
	if not world then
		world = workspace:WaitForChild("World", 10)
	end
	if not world then
		return
	end

	local mapFolder = world:FindFirstChild("Map")
	if not mapFolder then
		return
	end

	-- Load Lobby gadgets at startup
	local lobby = mapFolder:FindFirstChild("Lobby")
	if lobby then
		self._areaFolders["Lobby"] = lobby
		self:CreateForMap(lobby, nil)
		self._loadedAreas["Lobby"] = true
	else
	end

	-- Register TrainingArea folder (but don't load gadgets yet)
	local trainingArea = mapFolder:FindFirstChild("TrainingArea")
	if trainingArea then
		self._areaFolders["TrainingArea"] = trainingArea
		
		-- Set streaming mode to Atomic so gadgets are always loaded when player is nearby
		if trainingArea:IsA("Model") then
			trainingArea.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		end
	end
end

function GadgetService:Register(typeName, class)
	self._gadgetSystem:register(typeName, class)
end

function GadgetService:CreateForMap(mapInstance, dataByType)
	if not mapInstance or not mapInstance.Parent then
		return {}
	end

	local created = self._gadgetSystem:scanMap(mapInstance, dataByType, true, {
		net = self._net,
		registry = self._registry,
	})
	self._gadgetsByMap[mapInstance] = created

	for _, gadget in ipairs(created) do
		local model = gadget.getModel and gadget:getModel() or gadget.model
		local typeName = gadget.getTypeName and gadget:getTypeName() or gadget.typeName
		if model and typeName then
		end
	end

	for _, gadget in ipairs(created) do
		local id = gadget:getId()
		if id then
			self._mapByGadgetId[id] = mapInstance
		end
		if type(gadget.onServerCreated) == "function" then
			gadget:onServerCreated()
		end
	end

	return created
end

function GadgetService:ClearForMap(mapInstance)
	local list = self._gadgetsByMap[mapInstance]
	if not list then
		return
	end

	for _, gadget in ipairs(list) do
		local id = gadget:getId()
		if id then
			self._mapByGadgetId[id] = nil
		end
		if type(gadget.destroy) == "function" then
			gadget:destroy()
		end
	end

	self._gadgetsByMap[mapInstance] = nil
end

function GadgetService:GetAreaFolder(areaId)
	return self._areaFolders[areaId]
end

function GadgetService:LoadAreaForPlayer(player, areaId)
	if not player or type(areaId) ~= "string" then
		return
	end

	local areaFolder = self._areaFolders[areaId]
	if not areaFolder then
		return
	end

	-- Scan area if not already done (server-side gadgets)
	if not self._loadedAreas[areaId] then
		self:CreateForMap(areaFolder, nil)
		self._loadedAreas[areaId] = true
	end

	-- Send only this area's gadgets to the player
	local payload = self:_buildPayloadForMap(areaFolder)
	self._net:FireClient("GadgetAreaLoaded", player, areaId, payload)
end

function GadgetService:_buildPayloadForMap(mapInstance)
	local payload = {}
	local gadgets = self._gadgetsByMap[mapInstance] or {}

	for _, gadget in ipairs(gadgets) do
		local model = gadget:getModel()
		local typeName = gadget:getTypeName()
		local id = gadget:getId()
		if model and model.Parent and type(typeName) == "string" then
			table.insert(payload, {
				id = id,
				typeName = typeName,
				model = model,
			})
		end
	end

	return payload
end

function GadgetService:SendInitToPlayer(player)
	if not player then
		return
	end

	self._net:FireClient("GadgetInit", player, self:_buildInitPayload())
end

function GadgetService:_buildInitPayload()
	local payload = {}

	for id, gadget in pairs(self._gadgetSystem.instances) do
		local model = (gadget.getModel and gadget:getModel()) or gadget.model
		local typeName = (gadget.getTypeName and gadget:getTypeName()) or gadget.typeName
		if model and model.Parent and type(typeName) == "string" then
			table.insert(payload, {
				id = id,
				typeName = typeName,
				model = model,
			})
		end
	end

	return payload
end

function GadgetService:_onUseRequest(player, gadgetId, payload)
	if typeof(gadgetId) ~= "string" then
		return
	end

	local gadget = self._gadgetSystem:getById(gadgetId)
	if not gadget then
		self._net:FireClient("GadgetUseResponse", player, gadgetId, false)
		return
	end

	local approved = false
	local responseData = nil
	if type(gadget.onUseRequest) == "function" then
		local result = gadget:onUseRequest(player, payload)
		if type(result) == "table" then
			approved = result.approved == true
			responseData = result.data
		else
			approved = result == true
		end
	end

	self._net:FireClient("GadgetUseResponse", player, gadgetId, approved, responseData)
end

function GadgetService:_onPlayerRemoving(_player) end

return GadgetService
