local Signal = {}
Signal.__index = Signal

function Signal.new()
	local self = setmetatable({}, Signal)
	self._listeners = {}
	return self
end

function Signal:connect(callback)
	local connection = {
		_callback = callback,
		_connected = true,
	}

	function connection:disconnect()
		self._connected = false
	end

	table.insert(self._listeners, connection)
	return connection
end

function Signal:fire(...)
	for i = #self._listeners, 1, -1 do
		local connection = self._listeners[i]
		if connection and connection._connected and type(connection._callback) == "function" then
			task.spawn(connection._callback, ...)
		else
			table.remove(self._listeners, i)
		end
	end
end

function Signal:once(callback)
	local connection
	connection = self:connect(function(...)
		connection:disconnect()
		callback(...)
	end)
	return connection
end

function Signal:wait()
	local thread = coroutine.running()
	self:once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:disconnectAll()
	for _, connection in self._listeners do
		connection._connected = false
	end
	table.clear(self._listeners)
end

function Signal:destroy()
	self:disconnectAll()
	setmetatable(self, nil)
end

return Signal
