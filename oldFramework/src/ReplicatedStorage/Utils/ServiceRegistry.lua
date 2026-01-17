--[[
	ServiceRegistry - A clean replacement for global variable storage
	Provides type-safe access to services and controllers without polluting _G
]]

local ServiceRegistry = {}

-- Private storage
local services = {}
local controllers = {}
local systems = {}

-- Service registration and access
function ServiceRegistry:RegisterService(name, service)
	if services[name] then
		warn(`Service '{name}' is already registered`)
		return
	end
	services[name] = service
end

function ServiceRegistry:GetService(name)
	local service = services[name]
	if not service then
		warn(`Service '{name}' not found in registry`)
	end
	return service
end

function ServiceRegistry:GetAllServices()
	-- Return a copy to prevent external modification
	return table.clone(services)
end

-- Controller registration and access
function ServiceRegistry:RegisterController(name, controller)
	if controllers[name] then
		warn(`Controller '{name}' is already registered`)
		return
	end
	controllers[name] = controller
end

function ServiceRegistry:GetController(name)
	local controller = controllers[name]
	if not controller then
		warn(`Controller '{name}' not found in registry`)
	end
	return controller
end

function ServiceRegistry:GetAllControllers()
	-- Return a copy to prevent external modification
	return table.clone(controllers)
end

-- System registration and access (for things like ClientReplicator, RemoteReplicator, etc.)
function ServiceRegistry:RegisterSystem(name, system)
	if systems[name] then
		warn(`System '{name}' is already registered`)
		return
	end
	systems[name] = system
end

function ServiceRegistry:GetSystem(name)
	local system = systems[name]
	if not system then
		warn(`System '{name}' not found in registry`)
	end
	return system
end

function ServiceRegistry:GetAllSystems()
	-- Return a copy to prevent external modification
	return table.clone(systems)
end

-- Utility functions
function ServiceRegistry:Clear()
	services = {}
	controllers = {}
	systems = {}
end

function ServiceRegistry:ListServices()
	local names = {}
	for name in pairs(services) do
		table.insert(names, name)
	end
	return names
end

function ServiceRegistry:ListControllers()
	local names = {}
	for name in pairs(controllers) do
		table.insert(names, name)
	end
	return names
end

function ServiceRegistry:ListSystems()
	local names = {}
	for name in pairs(systems) do
		table.insert(names, name)
	end
	return names
end

return ServiceRegistry
