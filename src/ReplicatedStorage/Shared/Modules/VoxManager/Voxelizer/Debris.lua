-- [ SERVICES ]
local DebrisService = game:GetService("Debris")

-- [ VARIABLES ]
local Debris = {}

-- Cached folder reference
local debrisFolder = nil

-- [ FUNCTIONS ]

--! Creates debris parts at the given position.
--  Debris size is based on debrisSizeMultiplier directly (NOT scaled by radius).
--  This produces small, consistent chunks regardless of explosion size.
function Debris.makeDebris(debrisAmount: number, position: Vector3, radius: number, originalInfo: {}, debrisSizeMultiplier: number)
	local debrisCount = debrisAmount

	-- Debris size is based purely on the multiplier (small chunks ~0.2-0.8 studs)
	-- debrisSizeMultiplier default is 0.3, so base sizes are 0.2 to 0.6 studs
	local baseSize = debrisSizeMultiplier * 2 -- e.g. 0.3 * 2 = 0.6
	local minDebrisSize = math.max(baseSize * 0.4, 0.1) -- e.g. 0.24, clamped to 0.1
	local maxDebrisSize = baseSize * 1.2 -- e.g. 0.72
	local sizeRange = maxDebrisSize - minDebrisSize

	-- Cache the folder
	if not debrisFolder or not debrisFolder.Parent then
		debrisFolder = workspace:FindFirstChild("VoxelDebris")
		if not debrisFolder then
			debrisFolder = Instance.new("Folder")
			debrisFolder.Name = "VoxelDebris"
			debrisFolder.Parent = workspace
		end
	end

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
		debrisPart.Material = originalInfo.Material
		debrisPart.Color = originalInfo.Color
		debrisPart.Transparency = originalInfo.Transparency
		debrisPart.Reflectance = originalInfo.Reflectance
		debrisPart.CanCollide = true
		debrisPart.Parent = debrisFolder

		-- Apply velocity to make the debris fly outward
		local randomDirection = Vector3.new(random() - 0.5, random() + 0.1, random() - 0.5).Unit
		local speed = random(8, 18)
		debrisPart.AssemblyLinearVelocity = randomDirection * speed
		debrisPart.AssemblyAngularVelocity = Vector3.new(random(-10, 10), random(-10, 10), random(-10, 10))

		DebrisService:AddItem(debrisPart, 2.5)
	end
end

-- [ RETURNING ]
return Debris
