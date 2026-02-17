local ConfigsModules = {}
for _, child in ipairs(script:GetChildren()) do
	if child:IsA("ModuleScript") then
		ConfigsModules[child.Name] = require(child)
	elseif child:IsA("Folder") then
		local init = child:FindFirstChild("Init") or child:FindFirstChild("init")
		if init and init:IsA("ModuleScript") then
			ConfigsModules[child.Name] = require(init)
		end
	end
end
return ConfigsModules