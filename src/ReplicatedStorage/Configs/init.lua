local ConfigsModules = {}
for _, Module in next, script:GetChildren() do
	ConfigsModules[Module.Name] = require(Module:Clone())
end
return ConfigsModules