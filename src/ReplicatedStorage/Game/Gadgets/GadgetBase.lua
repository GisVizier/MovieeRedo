local GadgetBase = {}
GadgetBase.__index = GadgetBase

function GadgetBase.new(params)
	local self = setmetatable({}, GadgetBase)
	self.id = params.id
	self.typeName = params.typeName
	self.model = params.model
	self.data = params.data or {}
	self.isServer = params.isServer == true
	self.mapInstance = params.mapInstance
	self.context = params.context
	return self
end

function GadgetBase:getId()
	return self.id
end

function GadgetBase:getTypeName()
	return self.typeName
end

function GadgetBase:getModel()
	return self.model
end

function GadgetBase:getData()
	return self.data
end

function GadgetBase:setData(data)
	if typeof(data) ~= "table" then
		return
	end
	self.data = data
end

function GadgetBase:getContext()
	return self.context
end

function GadgetBase:setContext(context)
	self.context = context
end

function GadgetBase:onServerCreated() end

function GadgetBase:onClientCreated() end

function GadgetBase:onUseRequest(_player, _payload)
	return false
end

function GadgetBase:onUseResponse(_approved) end

function GadgetBase:destroy()
	if self.isServer and self.model and self.model.Parent then
		self.model:Destroy()
	end
	self.model = nil
end

return GadgetBase
