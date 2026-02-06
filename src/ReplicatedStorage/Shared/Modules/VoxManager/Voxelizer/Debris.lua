-- [ SERVICES ]
local DebrisService = game:GetService("Debris")

-- [ VARIABLES ]
local Debris = {}

-- Cached folder reference
local debrisFolder = nil

-- [ FUNCTIONS ]

--! Creates debris parts at the given position.
--  OPTIMIZED: Accepts position/radius directly (no hitbox Part needed), cached folder.
function Debris.makeDebris(debrisAmount: number, position: Vector3, radius: number, originalInfo: {}, debrisSizeMultiplier: number)
	local debrisCount = debrisAmount
	local diameter = radius * 2
	local minDebrisSize = diameter * debrisSizeMultiplier - (debrisSizeMultiplier / 4)
	local maxDebrisSize = diameter * debrisSizeMultiplier + (debrisSizeMultiplier / 4)
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

	-- Create debris
	for _ = 1, debrisCount do
		local debrisPart = Instance.new("Part")
		local s1 = math.clamp(random() * sizeRange + minDebrisSize, 0.1, 100)
		local s2 = math.clamp(random() * sizeRange + minDebrisSize, 0.1, 100)
		local s3 = math.clamp(random() * sizeRange + minDebrisSize, 0.1, 100)

		debrisPart.Size = Vector3.new(s1, s2, s3)
		debrisPart.Position = position
		debrisPart.Anchored = false
		debrisPart.Material = originalInfo.Material
		debrisPart.Color = originalInfo.Color
		debrisPart.Transparency = originalInfo.Transparency
		debrisPart.Reflectance = originalInfo.Reflectance
		debrisPart.Parent = debrisFolder

		-- Apply velocity to make the debris fly outward
		local randomDirection = Vector3.new(random() - 0.5, random() - 0.2, random() - 0.5).Unit
		local speed = random(5, 10)
		debrisPart.AssemblyLinearVelocity = randomDirection * speed
		debrisPart.AssemblyAngularVelocity = Vector3.new(random(-15, 15), random(-15, 15), random(-15, 15))

		DebrisService:AddItem(debrisPart, 2)
	end
end

-- [ RETURNING ]
return Debris
