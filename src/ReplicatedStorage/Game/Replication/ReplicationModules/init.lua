local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local VFXRep = {}

VFXRep.Modules = {}
VFXRep._initialized = false
VFXRep._registry = nil
VFXRep._matchManager = nil
VFXRep._lastRelayByUserId = {}
VFXRep._spectatorMap = {} -- [spectatedUserId] = { [spectatorPlayer] = true }

-- Temporary recv isolation toggle: disable server-side VFX relay.
local DISABLE_SERVER_VFX_RELAY = false
local SERVER_THROTTLE_INTERVAL_BY_MODULE = {
	Speed = 1 / 12,
}

local function loadModules()
	for _, child in ipairs(script:GetChildren()) do
		if child:IsA("ModuleScript") and child.Name ~= "init" and child.Name ~= "Util" then
			if not VFXRep.Modules[child.Name] then
				local ok, mod = pcall(require, child)
				if ok then
					VFXRep.Modules[child.Name] = mod
				end
			end
		end
	end
end

local function getModule(name)
	if not VFXRep.Modules[name] then
		local moduleScript = script:FindFirstChild(name)
		if moduleScript and moduleScript:IsA("ModuleScript") then
			local ok, mod = pcall(require, moduleScript)
			if ok then
				VFXRep.Modules[name] = mod
			end
		end
	end
	return VFXRep.Modules[name]
end

local function waitForLocalPlayerLoaded()
	if Players.LocalPlayer then
		return
	end
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
end

local function appendUniqueTarget(list, seen, player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return
	end
	if seen[player] then
		return
	end
	seen[player] = true
	table.insert(list, player)
end

local function resolveMatchManager(self)
	local manager = self._matchManager
	if manager and manager.GetPlayersInMatch then
		return manager
	end

	local registry = self._registry
	if registry and registry.TryGet then
		local resolved = registry:TryGet("MatchManager")
		if resolved and resolved.GetPlayersInMatch then
			self._matchManager = resolved
			return resolved
		end
	end

	return nil
end

local function getScopedPlayers(self, sender: Player)
	local matchManager = resolveMatchManager(self)
	if matchManager then
		local ok, scoped = pcall(function()
			return matchManager:GetPlayersInMatch(sender)
		end)
		if ok and type(scoped) == "table" then
			return scoped
		end
	end

	return Players:GetPlayers()
end

local function getTargets(self, sender: Player, targetSpec)
	local scopedPlayers = getScopedPlayers(self, sender)
	local scopedSet = {}
	for _, scopedPlayer in ipairs(scopedPlayers) do
		if typeof(scopedPlayer) == "Instance" and scopedPlayer:IsA("Player") and scopedPlayer.Parent then
			scopedSet[scopedPlayer] = true
		end
	end

	if targetSpec == "Me" then
		return { sender }
	end
	if targetSpec == "Others" then
		local list = {}
		local seen = {}
		for _, p in ipairs(scopedPlayers) do
			if p ~= sender then
				appendUniqueTarget(list, seen, p)
			end
		end
		return list
	end
	if targetSpec == "All" or targetSpec == nil then
		local list = {}
		local seen = {}
		for _, p in ipairs(scopedPlayers) do
			appendUniqueTarget(list, seen, p)
		end
		return list
	end
	if typeof(targetSpec) == "table" then
		if targetSpec.Players then
			local list = {}
			local seen = {}
			for _, p in ipairs(targetSpec.Players) do
				if p == sender or scopedSet[p] == true then
					appendUniqueTarget(list, seen, p)
				end
			end
			return list
		end
		if targetSpec.UserIds then
			local list = {}
			local seen = {}
			for _, id in ipairs(targetSpec.UserIds) do
				local p = Players:GetPlayerByUserId(id)
				if p and (p == sender or scopedSet[p] == true) then
					appendUniqueTarget(list, seen, p)
				end
			end
			return list
		end
	end
	return nil
end

local function resolveModuleInfo(moduleInfo)
	if typeof(moduleInfo) ~= "table" then
		return nil, nil
	end
	local moduleName = moduleInfo.Module or moduleInfo.ReplicateModule
	local functionName = moduleInfo.Function or moduleInfo.ReplicateFunction or "Execute"
	return moduleName, functionName
end

function VFXRep:Init(net, isServer, registry)
	-- Prevent double-initialization (VFXRep is now initialized early in Initializer.client.lua)
	if self._initialized then
		return
	end
	self._initialized = true
	self._net = net
	self._registry = registry

	if isServer then
		if DISABLE_SERVER_VFX_RELAY then
			return
		end

		loadModules()
		self._net:ConnectServer("VFXRep", function(player, targetSpec, moduleInfo, data)
			local moduleName, functionName = resolveModuleInfo(moduleInfo)
			if not moduleName then
				return
			end

			local mod = getModule(moduleName)
			if not mod or type(mod[functionName]) ~= "function" then
				return
			end

			if mod.Validate and mod:Validate(player, data) == false then
				return
			end

			local moduleThrottle = SERVER_THROTTLE_INTERVAL_BY_MODULE[moduleName]
			if moduleThrottle then
				local now = os.clock()
				local userId = player.UserId
				local byKey = self._lastRelayByUserId[userId]
				if not byKey then
					byKey = {}
					self._lastRelayByUserId[userId] = byKey
				end
				local throttleKey = string.format("%s|%s|%s", moduleName, tostring(functionName), tostring(targetSpec))
				local lastSent = byKey[throttleKey] or 0
				if (now - lastSent) < moduleThrottle then
					return
				end
				byKey[throttleKey] = now
			end

			local targets = getTargets(self, player, targetSpec)
			if not targets then
				return
			end

			-- Send to all targets - clients now initialize VFXRep early so OnClientEvent is always connected
			for _, target in ipairs(targets) do
				self._net:FireClient("VFXRep", target, player.UserId, moduleName, functionName, data)
			end
		end)

		-- Spectate VFX: track who is spectating whom
		self._net:ConnectServer("SpectateRegister", function(player, targetUserId)
			-- Remove player from any previous spectate mapping
			for uid, spectators in pairs(self._spectatorMap) do
				if spectators[player] then
					spectators[player] = nil
					if next(spectators) == nil then
						self._spectatorMap[uid] = nil
					end
				end
			end

			-- Register new target
			if type(targetUserId) == "number" and targetUserId > 0 then
				local map = self._spectatorMap[targetUserId]
				if not map then
					map = {}
					self._spectatorMap[targetUserId] = map
				end
				map[player] = true
			end
		end)

		-- Spectate VFX: forward "Me" VFX to spectators
		self._net:ConnectServer("SpectateVFXForward", function(player, moduleName, functionName, data)
			if type(moduleName) ~= "string" or type(functionName) ~= "string" then
				return
			end

			local spectators = self._spectatorMap[player.UserId]
			if not spectators then
				return
			end

			for spectator, _ in pairs(spectators) do
				if spectator and spectator.Parent then
					self._net:FireClient("SpectateVFXForward", spectator, player.UserId, moduleName, functionName, data)
				end
			end
		end)

		-- Clean up spectator tracking on leave
		Players.PlayerRemoving:Connect(function(player)
			-- Remove as spectator
			for uid, spectators in pairs(self._spectatorMap) do
				spectators[player] = nil
				if next(spectators) == nil then
					self._spectatorMap[uid] = nil
				end
			end
			-- Remove as spectated
			self._spectatorMap[player.UserId] = nil
			-- Clean relay throttles
			self._lastRelayByUserId[player.UserId] = nil
		end)
	else
		-- Connect OnClientEvent IMMEDIATELY so no events are dropped.
		-- getModule() will lazy-load individual modules on demand if they
		-- haven't been bulk-loaded yet, so early events still work.
		self._net:ConnectClient("VFXRep", function(originUserId, moduleName, functionName, data)
			local mod = getModule(moduleName)
			if mod and type(mod[functionName]) == "function" then
				mod[functionName](mod, originUserId, data)
			end
		end)

		-- Receive forwarded "Me" VFX while spectating
		self._net:ConnectClient("SpectateVFXForward", function(originUserId, moduleName, functionName, data)
			local spectateController = ServiceRegistry:GetController("Spectate")
			if not spectateController or not spectateController:IsSpectating() then
				return
			end
			if spectateController:GetTargetUserId() ~= originUserId then
				return
			end

			local mod = getModule(moduleName)
			if mod and type(mod[functionName]) == "function" then
				if type(data) ~= "table" then
					data = {}
				end
				data._spectate = true
				data._originUserId = originUserId

				-- Inject the spectate viewmodel and target character
				data.ViewModel = spectateController:GetSpectateViewmodelRig()
				local targetPlayer = Players:GetPlayerByUserId(originUserId)
				if targetPlayer and targetPlayer.Character then
					data.Character = targetPlayer.Character
				end

				mod[functionName](mod, originUserId, data)
			end
		end)

		-- Bulk-load modules in the background so they're warm for future calls.
		task.spawn(function()
			-- Wait for assets that MovementFX modules depend on (StreamingEnabled-safe).
			local assets = ReplicatedStorage:WaitForChild("Assets", 10)
			if assets then
				assets:WaitForChild("MovementFX", 10)
			end

			waitForLocalPlayerLoaded()
			loadModules()
		end)
	end
end

local function stripInstancesForNetwork(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	local clean = {}
	for key, value in pairs(tbl) do
		if typeof(value) == "Instance" then
			-- skip
		elseif type(value) == "table" then
			clean[key] = stripInstancesForNetwork(value)
		else
			clean[key] = value
		end
	end
	return clean
end

function VFXRep:Fire(targetSpec, moduleInfo, data)
	if not self._net then
		return
	end

	-- Skip network round-trip for "Me" - execute locally immediately
	if targetSpec == "Me" then
		local moduleName = moduleInfo.Module or moduleInfo.ReplicateModule
		local functionName = moduleInfo.Function or moduleInfo.ReplicateFunction or "Execute"

		if moduleName then
			local mod = getModule(moduleName)
			if mod and type(mod[functionName]) == "function" then
				local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId or 0
				mod[functionName](mod, localUserId, data)
			end

			-- Forward to any spectators via server (strip Instance refs for serialization)
			local cleanData = stripInstancesForNetwork(data)
			self._net:FireServer("SpectateVFXForward", moduleName, functionName, cleanData)
		end
		return
	end

	-- All other targets need server coordination
	self._net:FireServer("VFXRep", targetSpec, moduleInfo, data)
end

return VFXRep
