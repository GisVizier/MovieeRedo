local Registry = {}

local function createRegistry()
	local self = {}
	self._items = {}

	function self:Register(name, value, allowDuplicate)
		if self._items[name] ~= nil and not allowDuplicate then
			error("Registry already has item registered: " .. tostring(name))
		end
		self._items[name] = value
	end

	function self:Get(name)
		local value = self._items[name]
		if value == nil then
			error("Registry item not found: " .. tostring(name))
		end
		return value
	end

	function self:TryGet(name)
		return self._items[name]
	end

	return self
end

function Registry.new()
	return createRegistry()
end

return Registry
