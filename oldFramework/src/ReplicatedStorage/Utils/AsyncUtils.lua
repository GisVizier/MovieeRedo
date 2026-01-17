local AsyncUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)

-- Safe waiting with timeout and error handling
function AsyncUtils:SafeWaitForChild(parent, childName, timeout)
	timeout = timeout or 10

	local child = parent:FindFirstChild(childName)
	if child then
		return child
	end

	local startTime = tick()
	local connection

	connection = parent.ChildAdded:Connect(function(newChild)
		if newChild.Name == childName then
			connection:Disconnect()
			child = newChild
		end
	end)

	-- Wait with timeout
	while not child and (tick() - startTime) < timeout do
		task.wait(0.1)
	end

	if connection then
		connection:Disconnect()
	end

	if not child then
		Log:Warn("ASYNC_UTILS", "Failed to find child within timeout", {
			Child = childName,
			Parent = parent:GetFullName(),
			Timeout = timeout,
		})
	end

	return child
end

-- Wait for multiple children with single timeout
function AsyncUtils:WaitForChildren(parent, childNames, timeout)
	timeout = timeout or 10
	local results = {}
	local remaining = {}

	-- Check what already exists
	for _, name in ipairs(childNames) do
		local child = parent:FindFirstChild(name)
		if child then
			results[name] = child
		else
			table.insert(remaining, name)
		end
	end

	if #remaining == 0 then
		return results
	end

	-- Wait for remaining children
	local startTime = tick()
	local connection

	connection = parent.ChildAdded:Connect(function(newChild)
		for i = #remaining, 1, -1 do
			if newChild.Name == remaining[i] then
				results[remaining[i]] = newChild
				table.remove(remaining, i)
				break
			end
		end

		if #remaining == 0 then
			connection:Disconnect()
		end
	end)

	-- Wait with timeout
	while #remaining > 0 and (tick() - startTime) < timeout do
		task.wait(0.1)
	end

	if connection then
		connection:Disconnect()
	end

	-- Warn about missing children
	for _, name in ipairs(remaining) do
		Log:Warn("ASYNC_UTILS", "Failed to find child within timeout", {
			Child = name,
			Parent = parent:GetFullName(),
			Timeout = timeout,
		})
	end

	return results
end

-- Wait for a path like "Folder1/Folder2/Target"
function AsyncUtils:WaitForPath(root, path, timeout)
	timeout = timeout or 10
	local segments = {}

	for segment in string.gmatch(path, "[^/]+") do
		table.insert(segments, segment)
	end

	local current = root
	for _, segment in ipairs(segments) do
		current = self:SafeWaitForChild(current, segment, timeout)
		if not current then
			Log:Warn("ASYNC_UTILS", "Failed to traverse path", {
				Path = path,
				FailedSegment = segment,
			})
			return nil
		end
	end

	return current
end

-- Immediately check for child, no waiting
function AsyncUtils:TryGetChild(parent, childName)
	return parent:FindFirstChild(childName)
end

-- Get child or create it if missing (for containers)
function AsyncUtils:GetOrCreateChild(parent, childName, className)
	local child = parent:FindFirstChild(childName)
	if not child then
		child = Instance.new(className or "Folder")
		child.Name = childName
		child.Parent = parent
	end
	return child
end

return AsyncUtils
