-- [ SERVICES ]
local DebrisService = game:GetService("Debris")

-- [ VARIABLES ]
local Debris = {}

-- [ FUNCTIONS ]

--! The squared distance from one point to another.
function Debris.makeDebris(debrisAmount: number, sphereHitbox: Part, originalInfo: {}, debrisSizeMultiplier: number)
	local debrisCount = debrisAmount
	local minDebrisSize = sphereHitbox.Size.X * debrisSizeMultiplier - (debrisSizeMultiplier / 4)
	local maxDebrisSize = sphereHitbox.Size.X * debrisSizeMultiplier + (debrisSizeMultiplier / 4)

	local debrisFolder = workspace:FindFirstChild("VoxelDebris")
	if not debrisFolder then
		debrisFolder = Instance.new("Folder")
		debrisFolder.Name = "VoxelDebris"
		debrisFolder.Parent = workspace
	end

	-- Create debris
	for i = 1, debrisCount do
		local debrisPart = Instance.new("Part")
		local randomSize = Vector3.new(
			math.clamp(math.random() * (maxDebrisSize - minDebrisSize) + minDebrisSize, 0, 100),
			math.clamp(math.random() * (maxDebrisSize - minDebrisSize) + minDebrisSize, 0, 100),
			math.clamp(math.random() * (maxDebrisSize - minDebrisSize) + minDebrisSize, 0, 100)
		)

		debrisPart.Size = randomSize
		debrisPart.Position = sphereHitbox.Position
		debrisPart.Anchored = false
		debrisPart.Material = originalInfo.Material
		debrisPart.Color = originalInfo.Color
		debrisPart.Transparency = originalInfo.Transparency
		debrisPart.Reflectance = originalInfo.Reflectance
		debrisPart.Parent = debrisFolder

		-- Apply velocity to make the debris fly outward
		local randomDirection = Vector3.new(math.random() - 0.5, math.random() - 0.2, math.random() - 0.5).unit
		local speed = math.random(5, 10)
		debrisPart.Velocity = randomDirection * speed

		-- Add random rotation too.
		debrisPart.RotVelocity = Vector3.new(math.random(-15, 15), math.random(-15, 15), math.random(-15, 15))

		DebrisService:AddItem(debrisPart, 2)
	end
end

-- [ RETURNING ]
return Debris
