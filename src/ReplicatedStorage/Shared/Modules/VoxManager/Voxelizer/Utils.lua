-- [ VARIABLES ]
local Utils = {}

-- [ FUNCTIONS ]

--! The squared distance from one point to another.
function Utils.distanceSqFromPointToAABB(point: Vector3, aabbCenter: Vector3, halfSize: Vector3)
	local dx = math.max(math.abs(point.X - aabbCenter.X) - halfSize.X, 0)
	local dy = math.max(math.abs(point.Y - aabbCenter.Y) - halfSize.Y, 0)
	local dz = math.max(math.abs(point.Z - aabbCenter.Z) - halfSize.Z, 0)
	return dx * dx + dy * dy + dz * dz
end

--! Check if bounding box of a part is inside a sphere part.
function Utils.isAABBInsideSphere(aabbCenter: Vector3, halfSize: Vector3, sphereCenter: Vector3, sphereRadius: number)
	-- Check all 8 corners to see if they are in.
	local corners = {
		Vector3.new(aabbCenter.X - halfSize.X, aabbCenter.Y - halfSize.Y, aabbCenter.Z - halfSize.Z),
		Vector3.new(aabbCenter.X + halfSize.X, aabbCenter.Y - halfSize.Y, aabbCenter.Z - halfSize.Z),
		Vector3.new(aabbCenter.X - halfSize.X, aabbCenter.Y + halfSize.Y, aabbCenter.Z - halfSize.Z),
		Vector3.new(aabbCenter.X + halfSize.X, aabbCenter.Y + halfSize.Y, aabbCenter.Z - halfSize.Z),
		Vector3.new(aabbCenter.X - halfSize.X, aabbCenter.Y - halfSize.Y, aabbCenter.Z + halfSize.Z),
		Vector3.new(aabbCenter.X + halfSize.X, aabbCenter.Y - halfSize.Y, aabbCenter.Z + halfSize.Z),
		Vector3.new(aabbCenter.X - halfSize.X, aabbCenter.Y + halfSize.Y, aabbCenter.Z + halfSize.Z),
		Vector3.new(aabbCenter.X + halfSize.X, aabbCenter.Y + halfSize.Y, aabbCenter.Z + halfSize.Z),
	}

	-- For each corner, check if it is using a loop. Use radius not diameter since diameter is full width of sphere.
	for _, corner in ipairs(corners) do
		if (corner - sphereCenter).Magnitude > sphereRadius then
			return false
		end
	end
	return true
end

--! Check if a bounding box of part is outside of a sphere part.
function Utils.isAABBOutsideSphere(aabbCenter: Vector3, halfSize: Vector3, sphereCenter: Vector3, sphereRadius: number)
	local distSq = Utils.distanceSqFromPointToAABB(sphereCenter, aabbCenter, halfSize)
	return distSq >= (sphereRadius * sphereRadius)
end

-- [ RETURNING ]
return Utils
