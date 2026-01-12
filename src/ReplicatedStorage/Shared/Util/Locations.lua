local Locations = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function waitForChild(parent, name, timeout)
	timeout = timeout or 5
	local child = parent:FindFirstChild(name)
	if child then
		return child
	end

	local startTime = tick()
	while not child and (tick() - startTime) < timeout do
		child = parent:FindFirstChild(name)
		if not child then
			task.wait(0.1)
		end
	end

	return child
end

Locations.Services = {
	ReplicatedStorage = ReplicatedStorage,
	Players = game:GetService("Players"),
	RunService = RunService,
	UserInputService = game:GetService("UserInputService"),
	ContextActionService = game:GetService("ContextActionService"),
	TweenService = game:GetService("TweenService"),
	Workspace = workspace,
}

if RunService:IsServer() then
	Locations.Services.ServerStorage = game:GetService("ServerStorage")
	Locations.Services.ServerScriptService = game:GetService("ServerScriptService")
end

if RunService:IsClient() then
	local starterPlayer = game:GetService("StarterPlayer")
	Locations.Services.StarterPlayerScripts = starterPlayer:WaitForChild("StarterPlayerScripts")
	Locations.Services.StarterCharacterScripts = starterPlayer:WaitForChild("StarterCharacterScripts")
end

Locations.Shared = waitForChild(ReplicatedStorage, "Shared", 5)
Locations.Game = waitForChild(ReplicatedStorage, "Game", 5)
Locations.Global = waitForChild(ReplicatedStorage, "Global", 5)

return Locations
