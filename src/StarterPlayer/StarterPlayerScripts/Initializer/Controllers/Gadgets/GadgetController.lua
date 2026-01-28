local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Gadgets = require(Locations.Game:WaitForChild("Gadgets"))
local GadgetBase = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("GadgetBase"))
local JumpPad = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("JumpPad"))
local Zipline = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("Zipline"))

local GadgetController = {}

function GadgetController:Init(registry, net)
	self._registry = registry
	self._net = net
	self._gadgetSystem = Gadgets.new()
	self._gadgetSystem:setFallbackClass(GadgetBase)
	self._gadgetSystem:register("JumpPad", JumpPad)
	self._gadgetSystem:register("Zipline", Zipline)

	self._net:ConnectClient("GadgetInit", function(payload)
		self:_onInit(payload)
	end)

	self._net:ConnectClient("GadgetUseResponse", function(gadgetId, approved, responseData)
		self:_onUseResponse(gadgetId, approved, responseData)
	end)

	self._net:ConnectClient("CharacterSpawned", function(character)
		self:_onCharacterSpawned(character)
	end)
end

function GadgetController:Start() end

function GadgetController:_onCharacterSpawned(character)
	local player = Players.LocalPlayer
	if player and player.Character == character then
		self._net:FireServer("GadgetInitRequest")
	end
end

function GadgetController:_onInit(payload)
	if typeof(payload) ~= "table" then
		return
	end

	self._gadgetSystem:clear()

	for _, entry in ipairs(payload) do
		if typeof(entry) == "table" then
			local typeName = entry.typeName
			local model = entry.model
			if type(typeName) == "string" and model then
				local gadget = self._gadgetSystem:createFromModel(typeName, model, entry.data, false, nil, {
					net = self._net,
					registry = self._registry,
					localPlayer = Players.LocalPlayer,
				})
				if gadget and type(gadget.onClientCreated) == "function" then
					gadget:onClientCreated()
				end
			end
		end
	end
end

function GadgetController:RequestUse(gadgetId, payload)
	if type(gadgetId) ~= "string" or gadgetId == "" then
		return
	end
	self._net:FireServer("GadgetUseRequest", gadgetId, payload)
end

function GadgetController:_onUseResponse(gadgetId, approved, responseData)
	local gadget = self._gadgetSystem:getById(gadgetId)
	if gadget and type(gadget.onUseResponse) == "function" then
		gadget:onUseResponse(approved, responseData)
	end
end

return GadgetController
