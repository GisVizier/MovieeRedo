local ConnectionManager = {}
ConnectionManager.__index = ConnectionManager

function ConnectionManager.new()
	local self = setmetatable({}, ConnectionManager)
	self._groups = {}
	self._ungrouped = {}
	return self
end

function ConnectionManager:add(connection, groupName)
	if not connection then
		return
	end

	if groupName then
		if not self._groups[groupName] then
			self._groups[groupName] = {}
		end
		table.insert(self._groups[groupName], connection)
	else
		table.insert(self._ungrouped, connection)
	end

	return connection
end

function ConnectionManager:track(instance, eventName, callback, groupName)
	local event = instance[eventName]
	if not event then
		warn("[ConnectionManager] Event not found:", eventName, "on", instance.Name)
		return nil
	end

	local connection = event:Connect(callback)
	return self:add(connection, groupName)
end

function ConnectionManager:cleanupGroup(groupName)
	local group = self._groups[groupName]
	if not group then
		return
	end

	for _, connection in group do
		if typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		elseif type(connection) == "table" and connection.disconnect then
			connection:disconnect()
		elseif type(connection) == "table" and connection.Destroy then
			connection:Destroy()
		end
	end

	self._groups[groupName] = nil
end

function ConnectionManager:cleanupAll()
	for groupName in self._groups do
		self:cleanupGroup(groupName)
	end

	for _, connection in self._ungrouped do
		if typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		elseif type(connection) == "table" and connection.disconnect then
			connection:disconnect()
		elseif type(connection) == "table" and connection.Destroy then
			connection:Destroy()
		end
	end

	table.clear(self._ungrouped)
end

function ConnectionManager:getGroupCount(groupName)
	local group = self._groups[groupName]
	return group and #group or 0
end

function ConnectionManager:getTotalCount()
	local count = #self._ungrouped
	for _, group in self._groups do
		count += #group
	end
	return count
end

function ConnectionManager:destroy()
	self:cleanupAll()
	setmetatable(self, nil)
end

return ConnectionManager
