local GadgetUtils = require(script:WaitForChild("GadgetUtils"))

local Gadgets = {}
Gadgets.__index = Gadgets

function Gadgets.new()
	local self = setmetatable({}, Gadgets)
	self.registry = {}
	self.instances = {}
	self.fallbackClass = nil
	return self
end

function Gadgets:register(typeName, class)
	if type(typeName) ~= "string" or typeName == "" then
		error("Gadget typeName must be a non-empty string")
	end
	if type(class) ~= "table" then
		error("Gadget class must be a table")
	end
	self.registry[typeName] = class
end

function Gadgets:setFallbackClass(class)
	if class ~= nil and type(class) ~= "table" then
		error("Fallback class must be a table or nil")
	end
	self.fallbackClass = class
end

function Gadgets:getById(id)
	return self.instances[id]
end

function Gadgets:createFromModel(typeName, model, data, isServer, mapInstance, context)
	local class = self.registry[typeName] or self.fallbackClass
	if not class or type(class.new) ~= "function" then
		return nil
	end

	local id = GadgetUtils:getOrCreateId(model)
	local instance = class.new({
		id = id,
		typeName = typeName,
		model = model,
		data = data,
		isServer = isServer,
		mapInstance = mapInstance,
		context = context,
	})
	self.instances[id] = instance
	return instance
end

function Gadgets:scanMap(mapInstance, dataByType, isServer, context)
	local created = {}

	for _, entry in ipairs(GadgetUtils:listGadgetModels(mapInstance)) do
		local typeName = entry.typeName
		local model = entry.model
		local data = dataByType and dataByType[typeName] or nil
		local instance = self:createFromModel(typeName, model, data, isServer, mapInstance, context)
		if instance then
			table.insert(created, instance)
		end
	end

	return created
end

function Gadgets:removeById(id)
	local instance = self.instances[id]
	if instance and type(instance.destroy) == "function" then
		instance:destroy()
	end
	self.instances[id] = nil
end

function Gadgets:clear()
	for id, instance in pairs(self.instances) do
		if type(instance.destroy) == "function" then
			instance:destroy()
		end
		self.instances[id] = nil
	end
end

return Gadgets
