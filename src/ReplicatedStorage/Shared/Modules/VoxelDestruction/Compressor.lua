local bit32 = bit32

local CFrameCompressor = {}

local function randomFloat(min, max)
	return math.random() * (max - min) + min
end

function CFrameCompressor.GenerateCFrames(count, range)
	range = range or 1000
	local cframes = {}
	for _ = 1, count do
		local x = randomFloat(-range, range)
		local y = randomFloat(-range, range)
		local z = randomFloat(-range, range)
		local rx = randomFloat(-math.pi, math.pi)
		local ry = randomFloat(-math.pi, math.pi)
		local rz = randomFloat(-math.pi, math.pi)
		local cf = CFrame.new(x, y, z) * CFrame.Angles(rx, ry, rz)
		table.insert(cframes, cf)
	end
	return cframes
end

local POS_SCALE = 1000
local ROT_SCALE = 10000

local function zigzagEncode(n)
	return bit32.bxor(bit32.lshift(n, 1), bit32.arshift(n, 31))
end

local function zigzagDecode(n)
	return bit32.bxor(bit32.rshift(n, 1), -(bit32.band(n, 1)))
end

local function encodeVarint(value)
	value = zigzagEncode(value)
	local bytes = {}
	repeat
		local byte = bit32.band(value, 0x7F)
		value = bit32.rshift(value, 7)
		if value ~= 0 then
			byte = bit32.bor(byte, 0x80)
		end
		table.insert(bytes, string.char(byte))
	until value == 0
	return table.concat(bytes)
end

local function decodeVarint(data, offset)
	local result = 0
	local shift = 0
	local pos = offset
	while true do
		local byte = data:byte(pos)
		if not byte then
			error("Unexpected end of data decoding varint")
		end
		pos = pos + 1
		result = bit32.bor(result, bit32.lshift(bit32.band(byte, 0x7F), shift))
		if bit32.band(byte, 0x80) == 0 then
			break
		end
		shift = shift + 7
		if shift > 35 then
			error("Varint too big")
		end
	end
	return zigzagDecode(result), pos
end

local function quantizePosition(v)
	return math.floor(v * POS_SCALE + 0.5)
end

local function quantizeRotation(r)
	return math.floor(r * ROT_SCALE + 0.5)
end

function CFrameCompressor.CompressCFrames(cframeList)
	local buffer = {}

	local prevPx, prevPy, prevPz = 0, 0, 0
	local prevR1, prevR2, prevR3 = 0, 0, 0

	for _, cf in ipairs(cframeList) do
		local pos = cf.Position
		local rx, ry, rz = cf:ToEulerAnglesXYZ()

		local px = quantizePosition(pos.X)
		local py = quantizePosition(pos.Y)
		local pz = quantizePosition(pos.Z)
		local r1 = quantizeRotation(rx)
		local r2 = quantizeRotation(ry)
		local r3 = quantizeRotation(rz)

		local dx, dy, dz = px - prevPx, py - prevPy, pz - prevPz
		local dr1, dr2, dr3 = r1 - prevR1, r2 - prevR2, r3 - prevR3

		prevPx, prevPy, prevPz = px, py, pz
		prevR1, prevR2, prevR3 = r1, r2, r3

		table.insert(buffer, encodeVarint(dx))
		table.insert(buffer, encodeVarint(dy))
		table.insert(buffer, encodeVarint(dz))
		table.insert(buffer, encodeVarint(dr1))
		table.insert(buffer, encodeVarint(dr2))
		table.insert(buffer, encodeVarint(dr3))
	end

	return table.concat(buffer)
end

function CFrameCompressor.DecompressCFrames(data)
	local cframes = {}

	local prevPx, prevPy, prevPz = 0, 0, 0
	local prevR1, prevR2, prevR3 = 0, 0, 0

	local offset = 1
	local length = #data

	while offset <= length do
		local dx, pos1 = decodeVarint(data, offset)
		local dy, pos2 = decodeVarint(data, pos1)
		local dz, pos3 = decodeVarint(data, pos2)
		local dr1, pos4 = decodeVarint(data, pos3)
		local dr2, pos5 = decodeVarint(data, pos4)
		local dr3, pos6 = decodeVarint(data, pos5)

		offset = pos6

		local px = prevPx + dx
		local py = prevPy + dy
		local pz = prevPz + dz
		local r1 = prevR1 + dr1
		local r2 = prevR2 + dr2
		local r3 = prevR3 + dr3

		prevPx, prevPy, prevPz = px, py, pz
		prevR1, prevR2, prevR3 = r1, r2, r3

		local x = px / POS_SCALE
		local y = py / POS_SCALE
		local z = pz / POS_SCALE
		local rx = r1 / ROT_SCALE
		local ry = r2 / ROT_SCALE
		local rz = r3 / ROT_SCALE

		table.insert(cframes, CFrame.new(x, y, z) * CFrame.Angles(rx, ry, rz))
	end

	return cframes
end

function CFrameCompressor.PrintSize(value)
	if typeof(value) == "string" then
		local size = #value
	else
	end
end

return CFrameCompressor
