local TableUtils = {}

function TableUtils.DeepCopy(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end

	local copy = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			copy[k] = TableUtils.DeepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

function TableUtils.ShallowCopy(tbl)
	return table.clone(tbl)
end

function TableUtils.Shuffle(tbl)
	local t = TableUtils.ShallowCopy(tbl)
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

function TableUtils.Find(tbl, value)
	for i = 1, #tbl do
		if tbl[i] == value then
			return i
		end
	end
	return nil
end

function TableUtils.Contains(tbl, value)
	return TableUtils.Find(tbl, value) ~= nil
end

function TableUtils.Remove(tbl, value)
	local index = TableUtils.Find(tbl, value)
	if index then
		table.remove(tbl, index)
		return true
	end
	return false
end

function TableUtils.IsEmpty(tbl)
	return next(tbl) == nil
end

function TableUtils.Count(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

function TableUtils.Keys(tbl)
	local keys = {}
	for k in pairs(tbl) do
		table.insert(keys, k)
	end
	return keys
end

function TableUtils.Values(tbl)
	local values = {}
	for _, v in pairs(tbl) do
		table.insert(values, v)
	end
	return values
end

return TableUtils
