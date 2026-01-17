local PathUtils = {}

function PathUtils.ReadPath(startInstance, pathString)
	if not pathString then
		return startInstance
	end

	local segments = string.split(pathString, ".")
	local current = startInstance

	for i = 1, #segments do
		if current == nil then
			return nil
		end
		current = current:FindFirstChild(segments[i])
	end

	return current
end

function PathUtils.WaitForPath(startInstance, pathString, timeout)
	if not pathString then
		return startInstance
	end

	local segments = string.split(pathString, ".")
	local current = startInstance
	local maxWait = timeout or 10

	for i = 1, #segments do
		if current == nil then
			return nil
		end
		current = current:WaitForChild(segments[i], maxWait)
		if current == nil then
			return nil
		end
	end

	return current
end

function PathUtils.PathExists(startInstance, pathString)
	return PathUtils.ReadPath(startInstance, pathString) ~= nil
end

return PathUtils
