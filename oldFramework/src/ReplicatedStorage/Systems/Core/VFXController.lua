local VFXController = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local Config = require(Locations.Modules.Config)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)

local assetsFolder = nil
local activeEffects = {}
local continuousEffects = {}

local isServer = RunService:IsServer()
local isClient = RunService:IsClient()

function VFXController:Init()
	LogService:RegisterCategory("VFX", "VFX effects and particles")
	
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		assetsFolder = assets:FindFirstChild("MovementFX")
	end
	
	if not assetsFolder then
		LogService:Warn("VFX", "MovementFX assets folder not found")
	end
	
	if isServer then
		self:SetupServerConnections()
	elseif isClient then
		self:SetupClientConnections()
	end
	
	-- Load Kit VFX Modules
	self.KitEffects = {}
	local vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
	if vfxFolder then
		local kitsFolder = vfxFolder:FindFirstChild("Kits")
		if kitsFolder then
			for _, module in ipairs(kitsFolder:GetChildren()) do
				if module:IsA("ModuleScript") then
					local success, result = pcall(function()
						-- Store by module name (e.g. "WhiteBeard")
						local kitName = module.Name:gsub("VFX", "") -- Remove "VFX" suffix if present
						-- Or just use the module name if preferred. Let's support both.
						-- If file is WhiteBeardVFX, access via "WhiteBeard"
						self.KitEffects[kitName] = require(module)
						self.KitEffects[module.Name] = self.KitEffects[kitName] -- Alias
						LogService:Debug("VFX", "Loaded Kit VFX module", { Name = kitName })
					end)
					if not success then
						LogService:Warn("VFX", "Failed to load Kit VFX module", { Module = module.Name, Error = result })
					end
				end
			end
		end
	else
		LogService:Warn("VFX", "VFX folder not found in ReplicatedStorage")
	end
	
	LogService:Info("VFX", "VFXController initialized", {
		HasAssets = assetsFolder ~= nil,
		IsServer = isServer,
		IsClient = isClient,
		KitModulesLoaded = self.KitEffects and table.maxn(self.KitEffects) or 0
	})
end

function VFXController:SetupServerConnections()
	RemoteEvents:ConnectServer("PlayVFXRequest", function(player, vfxName, position, config)
		if not self:ValidateVFXRequest(player, vfxName) then
			return
		end
		
		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				RemoteEvents:FireClient("PlayVFX", otherPlayer, vfxName, position, player, config)
			end
		end
		
		LogService:Debug("VFX", "Replicated VFX", {
			Player = player.Name,
			VFX = vfxName,
		})
	end)
	
	RemoteEvents:ConnectServer("StopVFXRequest", function(player, vfxName)
		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				RemoteEvents:FireClient("StopVFX", otherPlayer, vfxName, player)
			end
		end
	end)
	
	RemoteEvents:ConnectServer("StartContinuousVFXRequest", function(player, vfxName)
		if not self:ValidateVFXRequest(player, vfxName) then
			return
		end
		
		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				RemoteEvents:FireClient("StartContinuousVFX", otherPlayer, vfxName, player)
			end
		end
	end)
end

function VFXController:SetupClientConnections()
	-- Handle legacy VFX format (vfxName, position, fromPlayer, config)
	RemoteEvents:ConnectClient("PlayVFX", function(arg1, arg2, arg3, arg4)
		-- Check if this is kit ability format (table with Effect key)
		if type(arg1) == "table" and arg1.Effect then
			local data = arg1
			local position = data.Position
			local ownerUserId = data.Owner
			local params = data.Params or {}
			
			local targetParent = nil
			if ownerUserId then
				local owner = Players:GetPlayerByUserId(ownerUserId)
				if owner and owner.Character then
					local bodyPart = CharacterLocations:GetBody(owner.Character)
					targetParent = bodyPart or owner.Character.PrimaryPart
				end
			end
			
			self:PlayVFXLocal(data.Effect, position, targetParent, params)
		else
			-- Legacy format
			local vfxName = arg1
			local position = arg2
			local fromPlayer = arg3
			local config = arg4
			
			local targetParent = nil
			if fromPlayer and fromPlayer.Character then
				local bodyPart = CharacterLocations:GetBody(fromPlayer.Character) 
				targetParent = bodyPart or fromPlayer.Character.PrimaryPart
			end
			
			self:PlayVFXLocal(vfxName, position, targetParent, config)
		end
	end)
	
	RemoteEvents:ConnectClient("StopVFX", function(vfxName, fromPlayer)
		local effectKey = vfxName .. "_" .. (fromPlayer and fromPlayer.UserId or "unknown")
		self:StopContinuousVFXByKey(effectKey)
	end)
	
	RemoteEvents:ConnectClient("StartContinuousVFX", function(vfxName, fromPlayer)
		local targetParent = nil
		if fromPlayer and fromPlayer.Character then
			local bodyPart = CharacterLocations:GetBody(fromPlayer.Character)
			targetParent = bodyPart or fromPlayer.Character.PrimaryPart
		end
		
		local effectKey = vfxName .. "_" .. (fromPlayer and fromPlayer.UserId or "unknown")
		self:StartContinuousVFXWithKey(vfxName, targetParent, effectKey)
	end)
end

function VFXController:ValidateVFXRequest(player, vfxName)
	if not player or not vfxName then
		return false
	end
	
	local vfxConfig = self:GetVFXConfig(vfxName)
	if vfxConfig and vfxConfig.Enabled == false then
		return false
	end
	
	return true
end

function VFXController:GetVFXConfig(vfxName)
	local vfxConfigs = Config.Gameplay.VFX
	if vfxConfigs then
		return vfxConfigs[vfxName]
	end
	return nil
end

function VFXController:GetVFXAsset(vfxName)
	if not assetsFolder then
		LogService:Warn("VFX", "No assets folder available")
		return nil
	end
	
	local asset = assetsFolder:FindFirstChild(vfxName)
	if not asset then
		LogService:Warn("VFX", "VFX asset not found", { Name = vfxName })
		return nil
	end
	
	return asset
end

function VFXController:PlayVFX(vfxName, position, config)
	local vfxConfig = self:GetVFXConfig(vfxName)
	if vfxConfig and vfxConfig.Enabled == false then
		return nil
	end
	
	local localPlayer = Players.LocalPlayer
	local targetParent = nil
	
	if localPlayer and localPlayer.Character then
		local bodyPart = CharacterLocations:GetBody(localPlayer.Character)
		targetParent = bodyPart or localPlayer.Character.PrimaryPart
	end
	
	return self:PlayVFXLocal(vfxName, position, targetParent, config)
end

function VFXController:PlayVFXReplicated(vfxName, position, config)
	local effect = self:PlayVFX(vfxName, position, config)
	
	RemoteEvents:FireServer("PlayVFXRequest", vfxName, position, config)
	
	return effect
end

function VFXController:PlayVFXLocal(vfxName, position, parent, config)
	-- CHECK FOR MODULAR KIT VFX (Format: "KitName.EffectName")
	if string.find(vfxName, "%.") then
		local parts = string.split(vfxName, ".")
		if #parts == 2 then
			local kitName = parts[1]
			local effectName = parts[2]
			
			if self.KitEffects and self.KitEffects[kitName] then
				local effectFunc = self.KitEffects[kitName][effectName]
				if effectFunc and type(effectFunc) == "function" then
					-- Call the modular effect function
					task.spawn(function()
						local success, err = pcall(function()
							effectFunc({
								Position = position,
								Parent = parent,
								Params = config, -- Pass config as Params
								Owner = config and config.Owner -- Optional owner if passed in config
							})
						end)
						if not success then
							LogService:Warn("VFX", "Error playing modular VFX", { VFX = vfxName, Error = err })
						end
					end)
					return true -- Handled successfully
				end
			end
		end
	end

	local asset = self:GetVFXAsset(vfxName)
	if not asset then
		return nil
	end
	
	local vfxConfig = self:GetVFXConfig(vfxName)
	local lifetime = config and config.Lifetime or (vfxConfig and vfxConfig.Lifetime) or 1.0
	
	local effect = asset:Clone()
	
	-- Disable collision on ALL parts in the effect
	self:DisableCollisionOnAllParts(effect)
	
	if effect:IsA("Model") then
		local rootPart = effect.PrimaryPart or effect:FindFirstChild("Root")
		if rootPart then
			effect.PrimaryPart = rootPart
			
			-- Calculate orientation: use Rotation CFrame if provided, otherwise Direction, otherwise just position
			local targetCFrame = CFrame.new(position)
			if config and config.Rotation then
				-- Use the provided rotation CFrame directly (position + rotation)
				targetCFrame = CFrame.new(position) * (config.Rotation - config.Rotation.Position)
			elseif config and config.Direction and config.Direction.Magnitude > 0.01 then
				local direction = config.Direction.Unit
				targetCFrame = CFrame.lookAt(position, position + direction)
			end
			
			-- Apply rotation offset from VFX config (e.g., 180 degrees to flip direction)
			local rotationOffset = vfxConfig and vfxConfig.RotationOffset or 0
			if rotationOffset ~= 0 then
				targetCFrame = targetCFrame * CFrame.Angles(0, math.rad(rotationOffset), 0)
			end
			
			effect:PivotTo(targetCFrame)
		else
			local anyPart = effect:FindFirstChildWhichIsA("BasePart", true)
			if anyPart then
				anyPart.Position = position
			end
		end
		effect.Parent = workspace
	elseif effect:IsA("BasePart") then
		effect.Position = position
		effect.Parent = workspace
	elseif effect:IsA("Attachment") and parent then
		effect.Parent = parent
	end
	
	self:EmitParticles(effect)
	
	local effectId = vfxName .. "_" .. tick()
	activeEffects[effectId] = effect
	
	task.delay(lifetime, function()
		self:CleanupEffect(effectId, effect)
	end)
	
	LogService:Debug("VFX", "Played VFX", {
		Name = vfxName,
		Position = position,
		Lifetime = lifetime,
	})
	
	return effect
end

function VFXController:DisableCollisionOnAllParts(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
		instance.CastShadow = false
		instance.Transparency = 1
	end
	
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Transparency = 1
		end
	end
end

function VFXController:EmitParticles(parent)
	local function processDescendant(descendant)
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(descendant:GetAttribute("EmitCount") or 10)
		elseif descendant:IsA("Trail") then
			descendant.Enabled = true
		elseif descendant:IsA("Beam") then
			descendant.Enabled = true
		end
	end
	
	if parent:IsA("ParticleEmitter") or parent:IsA("Trail") or parent:IsA("Beam") then
		processDescendant(parent)
	end
	
	for _, descendant in ipairs(parent:GetDescendants()) do
		processDescendant(descendant)
	end
end

function VFXController:CleanupEffect(effectId, effect)
	if activeEffects[effectId] then
		activeEffects[effectId] = nil
	end
	
	if effect and effect.Parent then
		local function disableDescendant(descendant)
			if descendant:IsA("ParticleEmitter") then
				descendant.Enabled = false
			elseif descendant:IsA("Trail") then
				descendant.Enabled = false
			elseif descendant:IsA("Beam") then
				descendant.Enabled = false
			end
		end
		
		for _, descendant in ipairs(effect:GetDescendants()) do
			disableDescendant(descendant)
		end
		
		task.delay(0.5, function()
			if effect and effect.Parent then
				effect:Destroy()
			end
		end)
	end
end

function VFXController:StartContinuousVFXReplicated(vfxName, attachTo)
	local effect = self:StartContinuousVFX(vfxName, attachTo)
	
	RemoteEvents:FireServer("StartContinuousVFXRequest", vfxName)
	
	return effect
end

function VFXController:StartContinuousVFXWithKey(vfxName, attachTo, effectKey)
	if continuousEffects[effectKey] then
		return continuousEffects[effectKey]
	end
	
	local asset = self:GetVFXAsset(vfxName)
	if not asset then
		return nil
	end
	
	local effect = asset:Clone()
	
	-- Disable collision and hide all parts
	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Transparency = 1
		end
	end
	
	-- Set up the model with Root part
	if effect:IsA("Model") then
		local rootPart = effect.PrimaryPart or effect:FindFirstChild("Root")
		if rootPart then
			effect.PrimaryPart = rootPart
			rootPart.Anchored = true
		end
	end
	
	-- Initial position at attach target
	if attachTo then
		if effect:IsA("Model") and effect.PrimaryPart then
			effect:PivotTo(attachTo.CFrame)
		elseif effect:IsA("BasePart") then
			effect.CFrame = attachTo.CFrame
		end
	end
	
	effect.Parent = workspace
	
	-- Store the attach target for position updates
	if attachTo then
		effect:SetAttribute("AttachTarget", attachTo:GetFullName())
	end
	
	-- Enable particle emitters
	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = true
		end
	end
	
	continuousEffects[effectKey] = effect
	
	LogService:Debug("VFX", "Started continuous VFX with key", { Name = vfxName, Key = effectKey })
	
	return effect
end

function VFXController:StartContinuousVFX(vfxName, attachTo)
	local localPlayer = Players.LocalPlayer
	local effectKey = vfxName .. "_local"
	
	if continuousEffects[effectKey] then
		return continuousEffects[effectKey]
	end
	
	local asset = self:GetVFXAsset(vfxName)
	if not asset then
		return nil
	end
	
	local effect = asset:Clone()
	
	-- Disable collision and hide all parts
	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Transparency = 1
		end
	end
	
	-- Set up the model with Root part
	if effect:IsA("Model") then
		local rootPart = effect.PrimaryPart or effect:FindFirstChild("Root")
		if rootPart then
			effect.PrimaryPart = rootPart
			rootPart.Anchored = true
		end
	end
	
	-- Initial position at attach target
	if attachTo then
		if effect:IsA("Model") and effect.PrimaryPart then
			effect:PivotTo(attachTo.CFrame)
		elseif effect:IsA("BasePart") then
			effect.CFrame = attachTo.CFrame
		end
	end
	
	effect.Parent = workspace
	
	-- Store the attach target for position updates
	if attachTo then
		effect:SetAttribute("AttachTarget", attachTo:GetFullName())
	end
	
	-- Enable particle emitters
	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = true
		end
	end
	
	continuousEffects[effectKey] = effect
	
	LogService:Debug("VFX", "Started continuous VFX", { Name = vfxName })
	
	return effect
end

function VFXController:UpdateContinuousVFXOrientation(vfxName, velocity, attachTo)
	local effectKey = vfxName .. "_local"
	local effect = continuousEffects[effectKey]
	
	if not effect or not effect.Parent then
		return
	end
	
	local rootPart = nil
	if effect:IsA("Model") then
		rootPart = effect.PrimaryPart or effect:FindFirstChild("Root")
	elseif effect:IsA("BasePart") then
		rootPart = effect
	end
	
	if not rootPart then
		return
	end
	
	-- Get position from attach target (follow character)
	local position = rootPart.Position
	if attachTo and attachTo.Position then
		position = attachTo.Position
	end
	
	-- Calculate rotation from velocity direction
	local targetCFrame = CFrame.new(position)
	
	if velocity and velocity.Magnitude >= 1 then
		local direction = velocity.Unit
		
		-- Calculate rotation angles from velocity direction
		-- Yaw (Y rotation) - horizontal direction
		local yaw = math.atan2(-direction.X, -direction.Z)
		
		-- Pitch (X rotation) - vertical tilt based on Y velocity
		local horizontalMag = math.sqrt(direction.X * direction.X + direction.Z * direction.Z)
		local pitch = math.atan2(direction.Y, horizontalMag)
		
		-- Build CFrame from position and euler angles (pitch, yaw, 0)
		targetCFrame = CFrame.new(position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	end
	
	-- Update the effect position and orientation
	if effect:IsA("Model") then
		effect:PivotTo(targetCFrame)
	else
		rootPart.CFrame = targetCFrame
	end
end

-- Update replication of continuous VFX orientation
function VFXController:UpdateContinuousVFXOrientationForPlayer(vfxName, velocity, player)
	local effectKey = vfxName .. "_" .. player.UserId
	local effect = continuousEffects[effectKey]
	
	if not effect then return end
	
	local attachTo = nil
	if player.Character then
		attachTo = CharacterLocations:GetBody(player.Character) or player.Character.PrimaryPart
	end
	
	if not attachTo then return end
	
	-- Re-use the existing logic but we need to extract it into a function that takes the effect directly
	-- or just duplicate the simple logic here since it's just positioning
	
	local rootPart = nil
	if effect:IsA("Model") then
		rootPart = effect.PrimaryPart or effect:FindFirstChild("Root")
	elseif effect:IsA("BasePart") then
		rootPart = effect
	end
	
	if not rootPart then return end
	
	-- Position
	local position = attachTo.Position
	local targetCFrame = CFrame.new(position)
	
	-- Rotation
	if velocity and velocity.Magnitude >= 1 then
		local direction = velocity.Unit
		local yaw = math.atan2(-direction.X, -direction.Z)
		local horizontalMag = math.sqrt(direction.X * direction.X + direction.Z * direction.Z)
		-- Avoid NaN
		if horizontalMag > 0.001 then
			local pitch = math.atan2(direction.Y, horizontalMag)
			targetCFrame = CFrame.new(position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
		end
	end
	
	if effect:IsA("Model") then
		effect:PivotTo(targetCFrame)
	else
		rootPart.CFrame = targetCFrame
	end
end

function VFXController:StopContinuousVFX(vfxName)
	local effectKey = vfxName .. "_local"
	self:StopContinuousVFXByKey(effectKey)
	
	RemoteEvents:FireServer("StopVFXRequest", vfxName)
end

function VFXController:StopContinuousVFXByKey(effectKey)
	local effect = continuousEffects[effectKey]
	if not effect then
		return
	end
	
	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		elseif descendant:IsA("Trail") then
			descendant.Enabled = false
		elseif descendant:IsA("Beam") then
			descendant.Enabled = false
		end
	end
	
	task.delay(1.0, function()
		if effect and effect.Parent then
			effect:Destroy()
		end
	end)
	
	continuousEffects[effectKey] = nil
	
	LogService:Debug("VFX", "Stopped continuous VFX", { Key = effectKey })
end

function VFXController:IsContinuousVFXActive(vfxName)
	local effectKey = vfxName .. "_local"
	return continuousEffects[effectKey] ~= nil
end

function VFXController:Cleanup()
	for effectId, effect in pairs(activeEffects) do
		if effect and effect.Parent then
			effect:Destroy()
		end
	end
	activeEffects = {}
	
	for effectKey, effect in pairs(continuousEffects) do
		if effect and effect.Parent then
			effect:Destroy()
		end
	end
	continuousEffects = {}
	
	LogService:Debug("VFX", "VFXController cleaned up")
end

return VFXController
