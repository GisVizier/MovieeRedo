--[[
	OCI Server - Open Cloud Interface / Command system
	Command loading commented out for now (Race command required Modules.Global from another game).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for OCIServerHolder (command modules live here)
local OCIServerHolder = ReplicatedStorage:WaitForChild("OCIServerHolder", 5)
if not OCIServerHolder then
	warn("[OCI] OCIServerHolder not found - skipping")
	return
end

local CommandsFolder = OCIServerHolder:FindFirstChild("Commands")
if not CommandsFolder then
	return
end

-- Command loading commented out - Race and other commands required Modules.Global from another game
--[[
for _, commandModule in CommandsFolder:GetChildren() do
	if commandModule:IsA("ModuleScript") then
		local ok, err = pcall(require, commandModule)
		if not ok then
			warn("[OCI] Failed to load command:", commandModule.Name, err)
		end
	end
end
]]

print("[OCI] Server ready (command loading disabled)")
