local Loader = {}

function Loader:Load(entries, registry, net)
	local loaded = {}

	for _, entry in ipairs(entries) do
		local moduleScript = entry.module
		local name = entry.name
		local moduleValue = require(moduleScript)
		loaded[name] = moduleValue

		if type(moduleValue.Init) == "function" then
			moduleValue:Init(registry, net)
		end

		if registry and type(registry.TryGet) == "function" and registry:TryGet(name) == nil then
			registry:Register(name, moduleValue)
		end
	end

	for _, entry in ipairs(entries) do
		local moduleValue = loaded[entry.name]
		if type(moduleValue.Start) == "function" then
			moduleValue:Start()
		end
	end

	return loaded
end

return Loader
