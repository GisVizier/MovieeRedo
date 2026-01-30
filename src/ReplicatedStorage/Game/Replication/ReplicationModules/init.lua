local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXRep = {}

VFXRep.Modules = {}
VFXRep._initialized = false

local function loadModules()
	for _, child in ipairs(script:GetChildren()) do
		if child:IsA("ModuleScript") and child.Name ~= "init" and child.Name ~= "Util" then
			if not VFXRep.Modules[child.Name] then
				local ok, mod = pcall(require, child)
				if ok then
					VFXRep.Modules[child.Name] = mod
				else
					warn("[VFXRep] Failed to load module:", child.Name, mod)
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
			else
				warn("[VFXRep] Failed to load module:", name, mod)
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

local function getTargets(sender: Player, targetSpec)
	if targetSpec == "Me" then
		return { sender }
	end
	if targetSpec == "Others" then
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= sender then
				table.insert(list, p)
			end
		end
		return list
	end
	if targetSpec == "All" or targetSpec == nil then
		return Players:GetPlayers()
	end
	if typeof(targetSpec) == "table" then
		if targetSpec.Players then
			return targetSpec.Players
		end
		if targetSpec.UserIds then
			local list = {}
			for _, id in ipairs(targetSpec.UserIds) do
				local p = Players:GetPlayerByUserId(id)
				if p then
					table.insert(list, p)
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

function VFXRep:Init(net, isServer)
	-- Prevent double-initialization (VFXRep is now initialized early in Initializer.client.lua)
	if self._initialized then
		return
	end
	self._initialized = true
	self._net = net

	if isServer then
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

			local targets = getTargets(player, targetSpec)
			if not targets then
				return
			end
			if moduleName == "Speed" and targetSpec == "Others" then
				table.insert(targets, player)
			end

			-- Send to all targets - clients now initialize VFXRep early so OnClientEvent is always connected
			for _, target in ipairs(targets) do
				self._net:FireClient("VFXRep", target, player.UserId, moduleName, functionName, data)
			end
		end)
	else
		-- Wait for assets that MovementFX modules depend on (StreamingEnabled-safe).
		local assets = ReplicatedStorage:WaitForChild("Assets", 10)
		if assets then
			assets:WaitForChild("MovementFX", 10)
		end

		waitForLocalPlayerLoaded()
		loadModules()
		self._net:ConnectClient("VFXRep", function(originUserId, moduleName, functionName, data)
			local mod = getModule(moduleName)
			if mod and type(mod[functionName]) == "function" then
				mod[functionName](mod, originUserId, data)
			end
		end)
	end
end

function VFXRep:Fire(targetSpec, moduleInfo, data)
	if not self._net then
		warn("[VFXRep] Fire called but VFXRep not initialized! Call VFXRep:Init(net, false) first.")
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
		end
		return
	end

	-- All other targets need server coordination
	self._net:FireServer("VFXRep", targetSpec, moduleInfo, data)
end

return VFXRep
