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
--  OPTIMIZED: No table/Vector3 allocations. Pure inline math with squared magnitude.
function Utils.isAABBInsideSphere(aabbCenter: Vector3, halfSize: Vector3, sphereCenter: Vector3, sphereRadius: number)
	local rSq = sphereRadius * sphereRadius
	local cx, cy, cz = aabbCenter.X, aabbCenter.Y, aabbCenter.Z
	local hx, hy, hz = halfSize.X, halfSize.Y, halfSize.Z
	local sx, sy, sz = sphereCenter.X, sphereCenter.Y, sphereCenter.Z

	-- Check all 8 corners inline without allocating any tables or Vector3s
	for x = -1, 1, 2 do
		local dx = cx + hx * x - sx
		for y = -1, 1, 2 do
			local dy = cy + hy * y - sy
			for z = -1, 1, 2 do
				local dz = cz + hz * z - sz
				if dx * dx + dy * dy + dz * dz > rSq then
					return false
				end
			end
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
