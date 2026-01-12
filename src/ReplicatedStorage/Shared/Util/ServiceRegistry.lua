local ServiceRegistry = {}

ServiceRegistry._registry = nil
ServiceRegistry._controllers = {}
ServiceRegistry._systems = {}

function ServiceRegistry:SetRegistry(registry)
	self._registry = registry
end

function ServiceRegistry:RegisterController(name, controller)
	self._controllers[name] = controller
end

function ServiceRegistry:RegisterSystem(name, system)
	self._systems[name] = system
end

function ServiceRegistry:GetController(name)
	if self._registry then
		local found = self._registry:TryGet(name)
		if found then
			return found
		end
	end
	return self._controllers[name]
end

function ServiceRegistry:GetSystem(name)
	return self._systems[name]
end

return ServiceRegistry
