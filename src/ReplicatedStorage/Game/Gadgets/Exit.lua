--[[
	Exit Gadget
	
	A gadget that teleports players back to the lobby/world spawn and unloads area gadgets.
	
	Model structure:
	- Model (with GadgetType = "Exit" or in Exits folder)
		- Leave (Part) - Touch trigger to exit
		- Spawn (Part) - Where incoming players spawn (used by AreaTeleport)
		- Root (Part, optional) - Visual/anchor
	
	Model attributes:
	- SourceArea (string, optional) - Area to unload on client (auto-detected if not set)
]]

local GadgetBase = require(script.Parent:WaitForChild("GadgetBase"))

local Exit = setmetatable({}, { __index = GadgetBase })
Exit.__index = Exit

function Exit.new(params)
	local self = setmetatable(GadgetBase.new(params), Exit)
	self._touchConnection = nil
	return self
end

function Exit:onServerCreated()
	-- Server just validates and handles teleportation
end

function Exit:onClientCreated()
	local model = self.model
	if not model then return end

	local leavePart = model:FindFirstChild("Leave")
	if not leavePart or not leavePart:IsA("BasePart") then
		warn("[Exit] No Leave part found in " .. model.Name)
		return
	end

	local localPlayer = self.context and self.context.localPlayer
	if not localPlayer then return end

	self._touchConnection = leavePart.Touched:Connect(function(hit)
		self:_onTouched(hit, localPlayer)
	end)
end

function Exit:_onTouched(hit, localPlayer)
	local character = localPlayer.Character
	if not character then return end

	-- Check if the hit part belongs to the local player
	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	if not hit:IsDescendantOf(character) and hit ~= root then
		return
	end

	-- Debounce
	if self._exiting then return end
	self._exiting = true

	-- Request exit from server
	local net = self.context and self.context.net
	if net then
		net:FireServer("GadgetUseRequest", self.id, {})
	end

	-- Reset debounce after a delay
	task.delay(1, function()
		self._exiting = false
	end)
end

function Exit:onUseRequest(player, _payload)
	-- Server-side: Handle teleportation back to World/Spawn
	local character = player.Character
	if not character then
		return { approved = false }
	end

	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
	if not root then
		return { approved = false }
	end

	-- Find World/Spawn
	local world = workspace:FindFirstChild("World")
	local spawnPart = world and world:FindFirstChild("Spawn")
	
	if not spawnPart or not spawnPart:IsA("BasePart") then
		warn("[Exit] World/Spawn not found")
		return { approved = false }
	end

	-- Teleport with random offset based on spawn size
	local size = spawnPart.Size
	local offset = Vector3.new(
		(math.random() - 0.5) * size.X,
		0,
		(math.random() - 0.5) * size.Z
	)
	root.CFrame = spawnPart.CFrame * CFrame.new(offset)

	-- Determine source area to tell client to unload
	local sourceArea = self.model:GetAttribute("SourceArea")
	if not sourceArea then
		-- Auto-detect from mapInstance
		if self.mapInstance then
			sourceArea = self.mapInstance.Name
		end
	end

	return { approved = true, data = { sourceArea = sourceArea } }
end

function Exit:onUseResponse(approved, responseData)
	-- Client-side: Unload area gadgets after teleporting back
	if not approved then return end

	local sourceArea = responseData and responseData.sourceArea
	if not sourceArea then return end

	-- Get GadgetController to unload area
	local registry = self.context and self.context.registry
	local gadgetController = registry and registry:TryGet("GadgetController")
	
	if gadgetController and type(gadgetController.UnloadArea) == "function" then
		gadgetController:UnloadArea(sourceArea)
	end

	print("[Exit] Returned to lobby, unloaded: " .. tostring(sourceArea))
end

function Exit:destroy()
	if self._touchConnection then
		self._touchConnection:Disconnect()
		self._touchConnection = nil
	end
	-- Don't destroy the model - it's part of the map
	self.model = nil
end

return Exit
