local Signal = require(script:WaitForChild("Signal"))

local Queue = {}
Queue.Cache = {}
Queue.__index = Queue

function Queue.Fetch(Token: any)
	assert(typeof(Token) ~= nil, "Argument #1 of Queue.New cannot be nil.")
	return Queue.Cache[Token]
end

function Queue.New(Token: any?, MassRun: boolean?)
	if Token ~= nil and Queue.Cache[Token] then
	end

	local self = {
		Token = Token,
		Queue = {},
		MassRun = MassRun or false,
		Paused = false,
		IsRunning = false,
		Completed = Signal.new(),
	}

	local Metatable = setmetatable(self, Queue)

	if Token then
		Queue.Cache[Token] = Metatable
	end

	return Metatable
end

type Function = (...any) -> any
function Queue:Add(func: Function, waits: boolean?, run: boolean?)
	assert(type(func) == "function", "Argument #1 must be a function.")
	assert(waits == nil or typeof(waits) == "boolean", "Argument #2 must be a boolean or nil")
	assert(run == nil or typeof(run) == "boolean", "Argument #3 must be a boolean or nil")

	local thread, signal, fired = nil, nil, false
	if waits then
		thread = coroutine.running()
		signal = Signal.new()
		signal:Connect(function()
			fired = true
			if coroutine.status(thread) == "suspended" then
				coroutine.resume(thread)
			end
		end)
	end

	table.insert(self.Queue, { func = func, completeSignal = signal })

	if self.IsRunning == false and run == true then
		self:Run()
	end

	if waits and not fired then
		coroutine.yield(thread)
	end

	if signal then
		signal = nil
	end
end

function Queue:Run(waits: boolean?)
	if self.IsRunning == true then
		return
	end
	self.IsRunning = true

	local function process()
		while #self.Queue > 0 do
			if self.Paused then
				wait()
			else
				local item = table.remove(self.Queue, 1)

				local success, error_message = pcall(item.func)
				if not success then
					warn("[VoxelDestruction.Queue] Task failed for token", tostring(self.Token), tostring(error_message))
				end

				if item.completeSignal then
					item.completeSignal:Fire()
				end
			end
		end
		self.IsRunning = false

		self.Completed:Fire()
	end

	if waits then
		process()
	elseif not waits then
		coroutine.resume(coroutine.create(function()
			process()
		end))
	end
end

function Queue:Clear(RunFunctions: boolean?)
	assert(
		RunFunctions == nil or type(RunFunctions) == "boolean",
		"Argument #1 of Queue.Clear must be a boolean or nil."
	)

	if RunFunctions then
		for _, item in pairs(self.Queue) do
			coroutine.resume(coroutine.create(function()
				local success, err = pcall(item.func)
				if not success then
					warn("[VoxelDestruction.Queue] Clear task failed for token", tostring(self.Token), tostring(err))
				end
				item.completeSignal:Fire()
			end))
		end
	end

	self.Queue = {}
end

function Queue:Pause()
	self.Paused = true
end

function Queue:Resume()
	self.Paused = false
	if not self.IsRunning then
		self:Run()
	end
end

function Queue:Destroy()
	Queue.Cache[self.Token] = nil
end

return Queue
