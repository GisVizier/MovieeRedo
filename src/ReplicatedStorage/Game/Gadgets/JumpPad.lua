local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local GadgetBase = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("GadgetBase"))

local JumpPad = {}
JumpPad.__index = JumpPad
setmetatable(JumpPad, GadgetBase)

local defaultLaunchSpeed = 120
local defaultUseDistance = 12
local defaultCooldown = 0.5

function JumpPad.new(params)
	local self = GadgetBase.new(params)
	setmetatable(self, JumpPad)
	self._lastUseByUserId = {}
	self._clientConnection = nil
	self._clientLastRequest = 0
	return self
end

function JumpPad:_getPadPart()
	if not self.model or not self.model.Parent then
		return nil
	end
	local bouncePart = self.model:FindFirstChild("BouncePart")
	if bouncePart and bouncePart:IsA("BasePart") then
		return bouncePart
	end
	local bouncerPart = self.model:FindFirstChild("BouncerPart")
	if bouncerPart and bouncerPart:IsA("BasePart") then
		return bouncerPart
	end
	local root = self.model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		return root
	end
	if self.model.PrimaryPart and self.model.PrimaryPart:IsA("BasePart") then
		return self.model.PrimaryPart
	end
	for _, child in ipairs(self.model:GetChildren()) do
		if child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

function JumpPad:_getLaunchSpeed()
	local speed = self.model and self.model:GetAttribute("LaunchSpeed")
	if type(speed) ~= "number" or speed <= 0 then
		return defaultLaunchSpeed
	end
	return speed
end

function JumpPad:_getUseDistance()
	local distance = self.model and self.model:GetAttribute("UseDistance")
	if type(distance) ~= "number" or distance <= 0 then
		return defaultUseDistance
	end
	return distance
end

function JumpPad:_getCooldown()
	local cooldown = self.model and self.model:GetAttribute("UseCooldown")
	if type(cooldown) ~= "number" or cooldown < 0 then
		return defaultCooldown
	end
	return cooldown
end

function JumpPad:_getLaunchDirection(padPart)
	local useLook = self.model and self.model:GetAttribute("UseLookVector")
	if useLook == nil then
		useLook = true
	end

	if useLook and padPart then
		return padPart.CFrame.LookVector
	end

	local direction = self.model and self.model:GetAttribute("LaunchDirection")
	if typeof(direction) == "Vector3" and direction.Magnitude > 0 then
		return direction.Unit
	end

	return Vector3.new(0, 1, 0)
end

function JumpPad:_isOnCooldown(userId)
	local last = self._lastUseByUserId[userId]
	if not last then
		return false
	end
	return (os.clock() - last) < self:_getCooldown()
end

function JumpPad:_setCooldown(userId)
	self._lastUseByUserId[userId] = os.clock()
end

function JumpPad:onUseRequest(player, _payload)
	if not player then
		return false
	end

	local character = player.Character
	if not character or not character.Parent then
		return false
	end

	local root = character:FindFirstChild("Root") or character.PrimaryPart
	if not root or not root:IsA("BasePart") then
		return false
	end

	local padPart = self:_getPadPart()
	if not padPart then
		return false
	end

	if self:_isOnCooldown(player.UserId) then
		return false
	end

	local distance = (root.Position - padPart.Position).Magnitude
	if distance > self:_getUseDistance() then
		return false
	end

	self:_setCooldown(player.UserId)

	return {
		approved = true,
		data = {
			direction = self:_getLaunchDirection(padPart),
			speed = self:_getLaunchSpeed(),
		},
	}
end

function JumpPad:_canClientRequest()
	local now = os.clock()
	local cooldown = self:_getCooldown()
	if cooldown <= 0 then
		return true
	end
	return (now - self._clientLastRequest) >= cooldown
end

function JumpPad:_markClientRequest()
	self._clientLastRequest = os.clock()
end

function JumpPad:onClientCreated()
	local context = self:getContext()
	if not context or not context.net then
		return
	end

	local padPart = self:_getPadPart()
	if not padPart then
		return
	end

	if self._clientConnection then
		self._clientConnection:Disconnect()
		self._clientConnection = nil
	end

	self._clientConnection = padPart.Touched:Connect(function(hit)
		local localPlayer = context.localPlayer or Players.LocalPlayer
		local character = localPlayer and localPlayer.Character
		if not character or not hit or not hit:IsDescendantOf(character) then
			return
		end

		if not self:_canClientRequest() then
			return
		end

		self:_markClientRequest()
		context.net:FireServer("GadgetUseRequest", self.id, nil)
	end)
end

function JumpPad:onUseResponse(approved, responseData)
	if approved ~= true then
		return
	end

	if type(responseData) ~= "table" then
		return
	end

	local direction = responseData.direction
	local speed = responseData.speed
	if typeof(direction) ~= "Vector3" or type(speed) ~= "number" or speed <= 0 then
		return
	end

	local player = Players.LocalPlayer
	local character = player and player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("Root") or character.PrimaryPart
	if not root or not root:IsA("BasePart") then
		return
	end

	root.AssemblyLinearVelocity = direction.Unit * speed
end

function JumpPad:destroy()
	if self._clientConnection then
		self._clientConnection:Disconnect()
		self._clientConnection = nil
	end
	GadgetBase.destroy(self)
end

return JumpPad
