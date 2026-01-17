local MathUtils = {}

-- Performance optimizations
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local math_floor = math.floor
local math_pi = math.pi

function MathUtils.Clamp(value, min, max)
	return math_max(min, math_min(max, value))
end

function MathUtils.Lerp(a, b, t)
	return a + (b - a) * t
end

function MathUtils.InverseLerp(a, b, value)
	if a == b then
		return 0
	end
	return (value - a) / (b - a)
end

function MathUtils.Map(value, inMin, inMax, outMin, outMax)
	return MathUtils.Lerp(outMin, outMax, MathUtils.InverseLerp(inMin, inMax, value))
end

function MathUtils.Round(number, decimals)
	local mult = 10 ^ (decimals or 0)
	return math_floor(number * mult + 0.5) / mult
end

function MathUtils.Sign(number)
	if number > 0 then
		return 1
	end
	if number < 0 then
		return -1
	end
	return 0
end

function MathUtils.IsNearlyEqual(a, b, epsilon)
	epsilon = epsilon or 1e-6
	return math_abs(a - b) <= epsilon
end

function MathUtils.Wrap(value, min, max)
	local range = max - min
	if range <= 0 then
		return min
	end
	return ((value - min) % range) + min
end

function MathUtils.WrapAngle(angle)
	local wrapped = angle % (2 * math_pi)
	if wrapped > math_pi then
		wrapped = wrapped - 2 * math_pi
	elseif wrapped < -math_pi then
		wrapped = wrapped + 2 * math_pi
	end
	return wrapped
end

function MathUtils.AngleDifference(target, current)
	local diff = target - current
	if diff > math_pi then
		diff = diff - 2 * math_pi
	elseif diff < -math_pi then
		diff = diff + 2 * math_pi
	end
	return diff
end

return MathUtils
