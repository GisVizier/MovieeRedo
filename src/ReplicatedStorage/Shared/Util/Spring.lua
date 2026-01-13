--[[
	Spring.lua (Vector3 spring)

	Critically-damped-friendly second order spring for smooth motion.
	- frequency: how fast it responds (Hz)
	- damping: 1.0 = critical (no overshoot), >1 = overdamped (slower, still no overshoot)
]]

local Spring = {}
Spring.__index = Spring

local TAU = math.pi * 2

export type Spring = {
	x: Vector3,
	v: Vector3,
	g: Vector3,
	frequency: number,
	damping: number,
	Step: (self: Spring, dt: number) -> Vector3,
	SetGoal: (self: Spring, goal: Vector3) -> (),
	Snap: (self: Spring, value: Vector3) -> (),
}

function Spring.new(initial: Vector3?, frequency: number?, damping: number?): Spring
	local self = setmetatable({}, Spring)
	self.x = initial or Vector3.zero
	self.v = Vector3.zero
	self.g = self.x
	self.frequency = frequency or 12
	self.damping = damping or 1
	return (self :: any) :: Spring
end

function Spring:SetGoal(goal: Vector3)
	self.g = goal
end

function Spring:Snap(value: Vector3)
	self.x = value
	self.v = Vector3.zero
	self.g = value
end

function Spring:Step(dt: number): Vector3
	-- Defensive: treat insane dt as a small step (prevents explosions on hitch).
	if dt <= 0 then
		return self.x
	end
	if dt > 1 / 10 then
		dt = 1 / 10
	end

	local f = self.frequency
	local z = self.damping

	local w = TAU * f
	local k = w * w
	local c = 2 * z * w

	local x = self.x
	local v = self.v
	local g = self.g

	-- a = k(g - x) - c v
	local a = (g - x) * k - v * c
	v = v + a * dt
	x = x + v * dt

	self.v = v
	self.x = x
	return x
end

return Spring

