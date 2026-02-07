local Net = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(script.Parent:WaitForChild("Remotes"))

local function logInfo(message, data)
	if data ~= nil then
	else
	end
end

Net.FolderName = "Remotes"
Net._initialized = false
Net._folder = nil
Net._events = {}

function Net:Init()
	if self._initialized then
		return
	end

	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(self.FolderName)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = self.FolderName
			folder.Parent = ReplicatedStorage
			logInfo("Created ReplicatedStorage/Remotes folder")
		end

		self._folder = folder

		for _, def in ipairs(Remotes) do
			self:_createRemote(def)
		end
	else
		self._folder = ReplicatedStorage:WaitForChild(self.FolderName)

		for _, def in ipairs(Remotes) do
			local remote = self._folder:WaitForChild(def.name)
			self._events[def.name] = remote
		end
	end

	self._initialized = true
end

function Net:_createRemote(def)
	local name = def.name
	local unreliable = def.unreliable == true

	local existing = self._folder:FindFirstChild(name)
	if existing then
		local isUnreliable = existing:IsA("UnreliableRemoteEvent")
		if isUnreliable ~= unreliable then
			logInfo("Recreating remote with different reliability", { Name = name })
			existing:Destroy()
			existing = nil
		end
	end

	local remote = existing
	if not remote then
		remote = Instance.new(unreliable and "UnreliableRemoteEvent" or "RemoteEvent")
		remote.Name = name
		remote.Parent = self._folder
	end

	if def.description then
		remote:SetAttribute("Description", def.description)
	end
	if unreliable then
		remote:SetAttribute("Unreliable", true)
	end

	self._events[name] = remote
	return remote
end

function Net:Get(name)
	local remote = self._events[name]
	if remote then
		return remote
	end

	if self._folder then
		remote = self._folder:FindFirstChild(name)
		if remote then
			self._events[name] = remote
		end
	end

	return remote
end

function Net:FireServer(name, ...)
	local remote = self:Get(name)
	if remote then
		remote:FireServer(...)
	end
end

function Net:FireClient(name, player, ...)
	local remote = self:Get(name)
	if remote then
		remote:FireClient(player, ...)
	end
end

function Net:FireAllClients(name, ...)
	local remote = self:Get(name)
	if remote then
		remote:FireAllClients(...)
	end
end

--[[
	Fires a remote to a specific list of players.
	Usage:
		local players = matchManager:GetPlayersInMatch(caster)
		net:FireClients(players, "VFXRep", data)
]]
function Net:FireClients(players, name, ...)
	local remote = self:Get(name)
	if remote then
		for _, player in players do
			remote:FireClient(player, ...)
		end
	end
end

function Net:FireAllClientsExcept(excludePlayer, name, ...)
	local remote = self:Get(name)
	if remote then
		local Players = game:GetService("Players")
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= excludePlayer then
				remote:FireClient(player, ...)
			end
		end
	end
end

function Net:ConnectServer(name, callback)
	local remote = self:Get(name)
	if remote then
		return remote.OnServerEvent:Connect(callback)
	end
	return nil
end

function Net:ConnectClient(name, callback)
	local remote = self:Get(name)
	if remote then
		return remote.OnClientEvent:Connect(callback)
	end
	return nil
end

return Net
