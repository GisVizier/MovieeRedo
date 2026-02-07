--[[
	VoxelDebrisController.lua
	Client-side debris creation for voxel explosions
	
	Handles debris physics and visuals on the client for better performance.
]]

local DebrisService = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local VoxelDebrisController = {}

VoxelDebrisController._net = nil
VoxelDebrisController._initialized = false
VoxelDebrisController._debrisFolder = nil

function VoxelDebrisController:Init(registry, net)
	self._net = net
	
	ServiceRegistry:RegisterController("VoxelDebris", self)
	
	-- Create debris folder
	self._debrisFolder = workspace:FindFirstChild("VoxelDebris")
	if not self._debrisFolder then
		self._debrisFolder = Instance.new("Folder")
		self._debrisFolder.Name = "VoxelDebris"
		self._debrisFolder.Parent = workspace
	end
	
	-- Listen for debris creation events from server
	self._net:ConnectClient("VoxelDebris", function(data)
		self:_onDebrisData(data)
	end)
	
	self._initialized = true
end

function VoxelDebrisController:Start()
	-- No-op
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

function VoxelDebrisController:_onDebrisData(data)
	if not data then return end
	
	-- Extract data
	local position = Vector3.new(data.position.X, data.position.Y, data.position.Z)
	local radius = data.radius or 10
	local amount = data.amount or 8
	local sizeMultiplier = data.sizeMultiplier or 0.3
	local originalInfo = data.originalInfo or {}
	
	-- Create debris client-side
	self:_createDebris(position, radius, amount, sizeMultiplier, originalInfo)
end

-- =============================================================================
-- DEBRIS CREATION
-- =============================================================================

function VoxelDebrisController:_createDebris(position: Vector3, radius: number, debrisAmount: number, debrisSizeMultiplier: number, originalInfo: {})
	local debrisCount = debrisAmount

	-- Debris size is based purely on the multiplier (small chunks ~0.2-0.8 studs)
	local baseSize = debrisSizeMultiplier * 2 -- e.g. 0.3 * 2 = 0.6
	local minDebrisSize = math.max(baseSize * 0.4, 0.1) -- e.g. 0.24, clamped to 0.1
	local maxDebrisSize = baseSize * 1.2 -- e.g. 0.72
	local sizeRange = maxDebrisSize - minDebrisSize

	local random = math.random

	-- Spread debris within the explosion radius for more natural look
	local spreadRadius = radius * 0.6

	-- Create debris
	for _ = 1, debrisCount do
		local debrisPart = Instance.new("Part")
		local s1 = random() * sizeRange + minDebrisSize
		local s2 = random() * sizeRange + minDebrisSize
		local s3 = random() * sizeRange + minDebrisSize

		debrisPart.Size = Vector3.new(s1, s2, s3)

		-- Scatter debris spawn positions around the explosion center
		local offsetX = (random() - 0.5) * spreadRadius
		local offsetY = (random() - 0.3) * spreadRadius -- slightly biased upward
		local offsetZ = (random() - 0.5) * spreadRadius
		debrisPart.Position = position + Vector3.new(offsetX, offsetY, offsetZ)

		debrisPart.Anchored = false
		
		-- Apply material properties from originalInfo
		if originalInfo.Material then
			debrisPart.Material = originalInfo.Material
		end
		if originalInfo.Color then
			debrisPart.Color = Color3.new(originalInfo.Color.R, originalInfo.Color.G, originalInfo.Color.B)
		end
		if originalInfo.Transparency ~= nil then
			debrisPart.Transparency = originalInfo.Transparency
		end
		if originalInfo.Reflectance ~= nil then
			debrisPart.Reflectance = originalInfo.Reflectance
		end
		
		debrisPart.CanCollide = true
		debrisPart.Parent = self._debrisFolder

		-- Apply velocity to make the debris fly outward
		local randomDirection = Vector3.new(random() - 0.5, random() + 0.1, random() - 0.5).Unit
		local speed = random(8, 18)
		debrisPart.AssemblyLinearVelocity = randomDirection * speed
		debrisPart.AssemblyAngularVelocity = Vector3.new(random(-10, 10), random(-10, 10), random(-10, 10))

		-- Auto-cleanup after 2.5 seconds
		DebrisService:AddItem(debrisPart, 2.5)
	end
end

--! Cleans up all debris manually (called by VoxManager:cleanupDebris on server)
function VoxelDebrisController:Cleanup()
	if self._debrisFolder then
		self._debrisFolder:ClearAllChildren()
	end
end

return VoxelDebrisController
