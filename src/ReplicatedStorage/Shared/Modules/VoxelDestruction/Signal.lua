local freeRunnerThread

local function acquireRunnerThreadAndCallEventHandler(func, ...)
	local acquiredRunnerThread = freeRunnerThread
	freeRunnerThread = nil
	func(...)
	freeRunnerThread = acquiredRunnerThread
end

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, fn)
	return setmetatable({
		_connected = true,
		_signal = signal,
		_fn = fn,
		_next = false,
	}, Connection)
end

function Connection:Disconnect()
	assert(self._connected, "Connection already disconnected.")
	self._connected = false

	if self._signal._handlerListHead == self then
		self._signal._handlerListHead = self._next
	else
		local prev = self._signal._handlerListHead
		while prev and prev._next ~= self do
			prev = prev._next
		end
		if prev then
			prev._next = self._next
		end
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlerListHead = false }, Signal)
end

function Signal:Connect(fn)
	local connection = Connection.new(self, fn)
	connection._next = (self._handlerListHead and self._handlerListHead) or connection._next
	self._handlerListHead = connection
	return connection
end

function Signal:Fire(...)
	local item = self._handlerListHead
	while item do
		if item._connected then
			if not freeRunnerThread then
				freeRunnerThread = coroutine.create(function(...)
					acquireRunnerThreadAndCallEventHandler(...)
					while true do
						acquireRunnerThreadAndCallEventHandler(coroutine.yield())
					end
				end)
			end
			task.spawn(freeRunnerThread, item._fn, ...)
		end
		item = item._next
	end
end

function Signal:Wait()
	local waitingcoroutine = coroutine.running()
	local connect
	connect = self:Connect(function(...)
		connect:Disconnect()
		task.spawn(waitingcoroutine, ...)
	end)
	return coroutine.yield()
end

return Signal
