local NumberUtils = {}

local suffixes = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nod",
	"Vg",
	"Uvg",
	"Dvg",
	"Tvg",
}

function NumberUtils.ToString(number, decimals)
	local precision = decimals or 1
	local absNumber = math.abs(number)
	local clampedNumber = math.max(1, absNumber)
	local magnitude = math.log(clampedNumber, 1000)
	local index = math.floor(magnitude)
	local suffix = suffixes[index + 1] or "e+" .. index
	local scaled = number * (10 ^ precision / 1000 ^ index)
	local rounded = math.floor(scaled) / 10 ^ precision

	return string.format("%." .. precision .. "f", rounded):gsub("%.?0+$", "") .. suffix
end

function NumberUtils.Comma(number)
	local str = tostring(number)
	while str:match("^(-?%d+)(%d%d%d)") do
		str = str:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	end
	return str
end

function NumberUtils.Round(number, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(number * mult + 0.5) / mult
end

return NumberUtils
