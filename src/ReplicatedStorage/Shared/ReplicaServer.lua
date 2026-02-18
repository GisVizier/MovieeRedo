--[[
MAD STUDIO

-[Replica]---------------------------------------
	
	State replication with life cycle handling and individual client subscription control.
	
	WARNING: Avoid numeric tables with gaps & non string/numeric keys - They can't be replicated!
			
	Members:
	
		Replica.ReadyPlayers:        {[Player]: true}
		Replica.NewReadyPlayer:      Signal<Player>
		Replica.RemovingReadyPlayer: Signal<Player>
	
	Functions:
	
		Replica.Token(token: string): ReplicaToken -- Only one token object can be created for each unique "token: string"
	
		Replica.New(params): Replica
			params: {
					Token: ReplicaToken,
					-- Optional:
					Tags: {}?,
					Data: {}?,
					WriteLib: ModuleScript?,
				}
		
		Replica.FromId(id: number): Replica?
		
	Members [Replica]:
	
		Replica.Tags:          {}
		Replica.Data:          {}
		Replica.Id:            number
		Replica.Token:         string
		Replica.Parent:        Replica?
		Replica.Children:      {[Replica]: true}
		Replica.BoundInstance: Instance?
		Replica.OnServerEvent: Signal<Player, ...>
		Replica.Maid:          Maid?
	
	Methods [Replica]:
	
		Replica:Set(path: {string | number}, value: any)
		Replica:SetValues(path: {string | number}, values: {[string]: any})
		Replica:TableInsert(path: {string | number}, value: any, index: number?): number
		Replica:TableRemove(path: {string | number}, index: number): any
		Replica:Write(function_name: string, ...): ...
		Replica:FireClient(player: Player, ...)
		Replica:FireAllClients(...)
		Replica:UFireClient(player: Player, ...)
		Replica:UFireAllClients(...)
		Replica:SetParent(replica: Replica)
		Replica:BindToInstance(instance: Instance)
		Replica:Replicate()
		Replica:DontReplicate()
		Replica:Subscribe(player)
		Replica:Unsubscribe(player)
		Replica:ListenToSet(path, listener)  -- Server-side: fire when path is Set
		Replica:ListenToChange(listener)     -- Server-side: fire on any change
		Replica:Identify(): string
		Replica:IsActive(): boolean
		Replica:Destroy()
	
--]]

----- Dependencies -----

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicaShared = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ReplicaShared")
local RateLimit = require(ReplicaShared:WaitForChild("RateLimit"))
local Remote = require(ReplicaShared:WaitForChild("Remote"))
local Signal = require(ReplicaShared:WaitForChild("Signal"))
local Maid = require(ReplicaShared:WaitForChild("Maid"))

----- Private -----

local BIND_TAG = "Bind"
local CS_TAG = "REPLICA"
local REPLICATION_ALL = "ALL"
local MAID_LOCK = {}
local EMPTY_TABLE = {}

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local GlobalRateLimit = RateLimit.New(120)

local ReadyPlayers: { [Player]: boolean } = {}

local Replicas = {}
local TopReplicas = {}
local ReplicationAllReplicas = {}
local SelectiveSubscriptions = {}

local RemoteRequestData = Remote.New("ReplicaRequestData")

local RemoteSet = Remote.New("ReplicaSet")
local RemoteSetValues = Remote.New("ReplicaSetValues")
local RemoteTableInsert = Remote.New("ReplicaTableInsert")
local RemoteTableRemove = Remote.New("ReplicaTableRemove")
local RemoteWrite = Remote.New("ReplicaWrite")
local RemoteSignal = Remote.New("ReplicaSignal")
local RemoteParent = Remote.New("ReplicaParent")
local RemoteCreate = Remote.New("ReplicaCreate")
local RemoteBind = Remote.New("ReplicaBind")
local RemoteDestroy = Remote.New("ReplicaDestroy")
local RemoteSignalUnreliable = Remote.New("ReplicaSignalUnreliable", true)

local Index = 0

local WriteLibCache: { [ModuleScript]: { [string | number]: { Id: number, fn: (...any) -> ...any } } } = {}
local WriteFlag = false
local Tokens: { [string]: boolean } = {}
local TokenValidate = {}

local BindValuePrefab = Instance.new("NumberValue")
BindValuePrefab.Name = "ReplicaBind"
CollectionService:AddTag(BindValuePrefab, CS_TAG)

local function IterateGroup(replica, fn)
	fn(replica)
	for child in pairs(replica.Children) do
		IterateGroup(child, fn)
	end
end

local function LoadWriteLib(module: ModuleScript)
	local write_lib = WriteLibCache[module]

	if write_lib ~= nil then
		return write_lib
	end

	if typeof(module) ~= "Instance" or module:IsA("ModuleScript") ~= true then
		error('[ReplicaServer]: "WriteLib" is not a ModuleScript')
	elseif module:IsDescendantOf(ReplicatedStorage) == false then
		error('[ReplicaServer]: "WriteLib" module must be a descendant of ReplicatedStorage')
	end

	local loaded_module = require(module)

	if type(loaded_module) ~= "table" then
		error('[ReplicaServer]: A "WriteLib" ModuleScript must return a table')
	end

	local function_list = {}

	for key, value in pairs(loaded_module) do
		if type(key) ~= "string" then
			error('[ReplicaServer]: "WriteLib" table keys must be strings')
		elseif type(value) ~= "function" then
			error('[ReplicaServer]: "WriteLib" table values must be functions')
		end
		table.insert(function_list, { key, value })
	end

	table.sort(function_list, function(item1, item2)
		return item1[1] < item2[1]
	end)

	write_lib = {}

	for fn_id, fn_entry in ipairs(function_list) do
		local entry_table = { Id = fn_id, fn = fn_entry[2] }
		write_lib[fn_entry[1]] = entry_table
		write_lib[fn_id] = entry_table
	end

	WriteLibCache[module] = write_lib

	return write_lib
end

local function GenerateCreation(replica)
	local replication = {}
	local creation = {}
	IterateGroup(replica, function(group_replica)
		local self_creation = group_replica.self_creation
		self_creation[4] = if group_replica.Parent == nil then 0 else group_replica.Parent.Id
		creation[tostring(group_replica.Id)] = self_creation
		group_replica.creation = creation
		group_replica.replication = replication
	end)
end

----- Public -----

export type Replica = {
	Tags: { [any]: any },
	Data: { [any]: any },
	Id: number,
	Token: string,
	Parent: Replica?,
	Children: { [Replica]: boolean? },
	BoundInstance: Instance?,
	OnServerEvent: { Connect: (self: any, listener: (Player, ...any) -> ()) -> { Disconnect: (self: any) -> () } },
	Maid: typeof(Maid),

	Set: (self: any, path: { string }, value: any) -> (),
	SetValues: (self: any, path: { string }, values: { [string]: any }) -> (),
	TableInsert: (self: any, path: { string }, value: any, index: number?) -> number,
	TableRemove: (self: any, path: { string }, index: number) -> any,
	Write: (self: any, function_name: string, ...any) -> ...any,
	FireClient: (self: any, player: Player, ...any) -> (),
	FireAllClients: (self: any, ...any) -> (),
	UFireClient: (self: any, player: Player, ...any) -> (),
	UFireAllClients: (self: any, ...any) -> (),
	SetParent: (self: any, new_parent: Replica) -> (),
	BindToInstance: (self: any, instance: Instance) -> (),
	Replicate: (self: any) -> (),
	DontReplicate: (self: any) -> (),
	Subscribe: (self: any, player: Player) -> (),
	Unsubscribe: (self: any, player: Player) -> (),
	Identify: (self: any) -> string,
	IsActive: (self: any) -> boolean,
	Destroy: (self: any) -> (),
}

local Replica = {
	ReadyPlayers = ReadyPlayers,
	NewReadyPlayer = Signal.New(),
	RemovingReadyPlayer = Signal.New(),
}
Replica.__index = Replica

local ReplicaToken = {}
ReplicaToken.__index = ReplicaToken

local LockedReplica = {}
LockedReplica.__index = LockedReplica

function Replica.Token(name: string)
	if type(name) ~= "string" then
		error("[ReplicaServer]: name must be a string")
	end

	if Tokens[name] == true then
		error('[ReplicaServer]: Token "' .. name .. '" duplicate')
	end

	Tokens[name] = true

	local self = setmetatable({
		Name = name,
	}, ReplicaToken)

	TokenValidate[self] = true

	return self
end

function Replica.New(params: { Token: any, Tags: {}?, Data: {}?, WriteLib: ModuleScript? }): Replica
	local token = params.Token
	local tags = params.Tags or {}
	local data = params.Data or {}
	local write_lib = nil

	if TokenValidate[token] == nil then
		error('[ReplicaServer]: "Token" is not valid (' .. tostring(token) .. ")")
	elseif type(tags) ~= "table" then
		error('[ReplicaServer]: "Tags" is not a table')
	elseif type(data) ~= "table" then
		error('[ReplicaServer]: "Data" is not a table')
	elseif tags[BIND_TAG] ~= nil then
		error('[ReplicaServer]: "Tags.' .. BIND_TAG .. '" key is reserved')
	end

	if params.WriteLib ~= nil then
		write_lib = LoadWriteLib(params.WriteLib)
	end

	Index += 1

	local self = setmetatable({
		Tags = tags,
		Data = data,
		Id = Index,
		Token = token.Name,
		Parent = nil,
		Children = {},
		BoundInstance = nil,
		OnServerEvent = Signal.New(),
		Maid = Maid.New(MAID_LOCK),

		self_creation = { token.Name, tags, data, 0, params.WriteLib },
		creation = nil,
		replication = nil,

		write_lib = write_lib,
		write_lib_module = params.WriteLib,
		bind_value = nil,

		set_listeners = {},
		changed_listeners = Signal.New(),
	}, Replica)

	Replicas[Index] = self

	return self
end

function Replica.FromId(id: number): Replica?
	return Replicas[id]
end

function Replica.Test()
	return {
		Replicas = Replicas,
		TopReplicas = TopReplicas,
		ReplicationAllReplicas = ReplicationAllReplicas,
		SelectiveSubscriptions = SelectiveSubscriptions,
	}
end

function Replica:Set(path: { string }, value: any)
	local pointer = self.Data
	for i = 1, #path - 1 do
		pointer = pointer[path[i]]
	end
	local last_key = path[#path]
	local old_value = pointer[last_key]
	pointer[last_key] = value

	if self.set_listeners and next(self.set_listeners) ~= nil then
		local path_key = table.concat(path, ".")
		local listeners = self.set_listeners[path_key]
		if listeners then
			listeners:Fire(value, old_value)
		end
	end
	if self.changed_listeners then
		self.changed_listeners:Fire("Set", path, value, old_value)
	end

	if WriteFlag == false then
		local self_id = self.Id
		if self.replication ~= nil then
			if self.replication[REPLICATION_ALL] == true then
				for player in pairs(ReadyPlayers) do
					RemoteSet:FireClient(player, self_id, path, value)
				end
			else
				for player in pairs(self.replication) do
					RemoteSet:FireClient(player, self_id, path, value)
				end
			end
		end
	end
end

-- Listen to Set on a specific path. Returns connection with :Disconnect().
function Replica:ListenToSet(path: { string }, listener: (value: any, oldValue: any?) -> ())
	local path_key = table.concat(path, ".")
	local listeners = self.set_listeners[path_key]
	if not listeners then
		listeners = Signal.New()
		self.set_listeners[path_key] = listeners
	end
	return listeners:Connect(listener)
end

-- Listen to any change (Set, SetValues, TableInsert, TableRemove).
function Replica:ListenToChange(listener: (action: string, path: { any }, param1: any, param2: any?) -> ())
	return self.changed_listeners:Connect(listener)
end

function Replica:SetValues(path: { string }, values: { [string]: any })
	local pointer = self.Data
	for _, key in ipairs(path) do
		pointer = pointer[key]
	end
	for key, value in pairs(values) do
		pointer[key] = value
	end

	if self.changed_listeners then
		self.changed_listeners:Fire("SetValues", path, values)
	end

	if WriteFlag == false then
		local self_id = self.Id
		if self.replication ~= nil then
			if self.replication[REPLICATION_ALL] == true then
				for player in pairs(ReadyPlayers) do
					RemoteSetValues:FireClient(player, self_id, path, values)
				end
			else
				for player in pairs(self.replication) do
					RemoteSetValues:FireClient(player, self_id, path, values)
				end
			end
		end
	end
end

function Replica:TableInsert(path: { string }, value: any, index: number?): number
	local pointer = self.Data
	for _, key in ipairs(path) do
		pointer = pointer[key]
	end
	if index ~= nil then
		table.insert(pointer, index, value)
	else
		table.insert(pointer, value)
	end

	if WriteFlag == false then
		local self_id = self.Id
		if self.replication ~= nil then
			if self.replication[REPLICATION_ALL] == true then
				for player in pairs(ReadyPlayers) do
					RemoteTableInsert:FireClient(player, self_id, path, value, index)
				end
			else
				for player in pairs(self.replication) do
					RemoteTableInsert:FireClient(player, self_id, path, value, index)
				end
			end
		end
	end

	return index or #pointer
end

function Replica:TableRemove(path: { string }, index: number): any
	local pointer = self.Data
	for _, key in ipairs(path) do
		pointer = pointer[key]
	end
	local removed_value = table.remove(pointer, index)

	if WriteFlag == false then
		local self_id = self.Id
		if self.replication ~= nil then
			if self.replication[REPLICATION_ALL] == true then
				for player in pairs(ReadyPlayers) do
					RemoteTableRemove:FireClient(player, self_id, path, index)
				end
			else
				for player in pairs(self.replication) do
					RemoteTableRemove:FireClient(player, self_id, path, index)
				end
			end
		end
	end

	return removed_value
end

function Replica:Write(function_name: string, ...): ...any
	local write_lib_entry = self.write_lib[function_name]

	if WriteFlag == true then
		return write_lib_entry.fn(self, ...)
	end

	WriteFlag = true
	local return_params = table.pack(pcall(write_lib_entry.fn, self, ...))
	WriteFlag = false

	if return_params[1] ~= true then
		error("[ReplicaServer]: (WriteLib) " .. tostring(return_params[2]))
	end

	table.remove(return_params, 1)

	local self_id = self.Id
	local fn_id = write_lib_entry.Id

	if self.replication ~= nil then
		if self.replication[REPLICATION_ALL] == true then
			for player in pairs(ReadyPlayers) do
				RemoteWrite:FireClient(player, self_id, fn_id, ...)
			end
		else
			for player in pairs(self.replication) do
				RemoteWrite:FireClient(player, self_id, fn_id, ...)
			end
		end
	end

	return table.unpack(return_params)
end

function Replica:FireClient(player, ...)
	if self.replication ~= nil then
		if
			(self.replication[REPLICATION_ALL] == true and ReadyPlayers[player] == true)
			or self.replication[player] ~= nil
		then
			RemoteSignal:FireClient(player, self.Id, ...)
		end
	end
end

function Replica:FireAllClients(...)
	local self_id = self.Id
	if self.replication ~= nil then
		if self.replication[REPLICATION_ALL] == true then
			for player in pairs(ReadyPlayers) do
				RemoteSignal:FireClient(player, self_id, ...)
			end
		else
			for player in pairs(self.replication) do
				RemoteSignal:FireClient(player, self_id, ...)
			end
		end
	end
end

function Replica:UFireClient(player, ...)
	if self.replication ~= nil then
		if
			(self.replication[REPLICATION_ALL] == true and ReadyPlayers[player] == true)
			or self.replication[player] ~= nil
		then
			RemoteSignalUnreliable:FireClient(player, self.Id, ...)
		end
	end
end

function Replica:UFireAllClients(...)
	local self_id = self.Id
	if self.replication ~= nil then
		if self.replication[REPLICATION_ALL] == true then
			for player in pairs(ReadyPlayers) do
				RemoteSignalUnreliable:FireClient(player, self_id, ...)
			end
		else
			for player in pairs(self.replication) do
				RemoteSignalUnreliable:FireClient(player, self_id, ...)
			end
		end
	end
end

function Replica:SetParent(new_parent)
	if type(new_parent) ~= "table" or getmetatable(new_parent) ~= Replica then
		error("[ReplicaServer]: new_parent is not a Replica (" .. tostring(new_parent) .. ")")
	elseif Replicas[new_parent.Id] == nil then
		error("[ReplicaServer]: Can't set destroyed Replica as parent")
	end

	if TopReplicas[self] ~= nil then
		error("[ReplicaServer]: Can't change parent for top level Replica")
	end

	if self.BoundInstance ~= nil then
		error("[ReplicaServer]: Can't change parent for bound Replica")
	end

	local recursion_check = new_parent

	while recursion_check ~= nil do
		recursion_check = recursion_check.Parent
		if recursion_check == self then
			error("[ReplicaServer]: Can't set descendant Replica as parent")
		end
	end

	local old_parent = self.Parent

	if old_parent == new_parent then
		return
	end

	self.Parent = new_parent

	if old_parent ~= nil then
		old_parent.Children[self] = nil
	end

	new_parent.Children[self] = true

	IterateGroup(self, function(group_replica)
		local string_id = tostring(group_replica.Id)
		if old_parent ~= nil and old_parent.creation ~= nil then
			old_parent.creation[string_id] = nil
		end
		if new_parent.creation ~= nil then
			local self_creation = group_replica.self_creation
			self_creation[4] = group_replica.Parent.Id
			new_parent.creation[string_id] = self_creation
		end
		group_replica.creation = new_parent.creation
		group_replica.replication = new_parent.replication
	end)

	local self_id = self.Id
	local parent_id = new_parent.Id
	local parent_creation = new_parent.creation

	local old_subscriptions = EMPTY_TABLE

	if old_parent ~= nil and old_parent.replication ~= nil then
		if old_parent.replication[REPLICATION_ALL] == true then
			old_subscriptions = ReadyPlayers
		else
			old_subscriptions = old_parent.replication
		end
	end

	local new_subscriptions = EMPTY_TABLE

	if new_parent ~= nil and new_parent.replication ~= nil then
		if new_parent.replication[REPLICATION_ALL] == true then
			new_subscriptions = ReadyPlayers
		else
			new_subscriptions = new_parent.replication
		end
	end

	if old_parent ~= nil and old_parent.replication ~= nil then
		if new_parent.replication ~= old_parent.replication and new_subscriptions ~= ReadyPlayers then
			for player in pairs(old_subscriptions) do
				if new_subscriptions[player] == nil then
					RemoteDestroy:FireClient(player, self_id)
				end
			end
		end
	end

	if new_parent.replication ~= nil then
		local custom_creation

		for player in pairs(new_subscriptions) do
			if old_subscriptions[player] == true then
				RemoteParent:FireClient(player, self_id, parent_id)
			else
				if custom_creation == nil then
					custom_creation = {}
					IterateGroup(self, function(group_replica)
						local string_id = tostring(group_replica.Id)
						custom_creation[string_id] = parent_creation[string_id]
					end)
				end
				RemoteCreate:FireClient(player, custom_creation, self_id)
			end
		end
	end
end

function Replica:BindToInstance(instance: Instance)
	if typeof(instance) ~= "Instance" then
		error('[ReplicaServer]: "instance" argument is not an Instance (' .. tostring(instance) .. ")")
	end

	if self.Parent ~= nil then
		error("[ReplicaServer]: Can't bind Replica parented to another Replica")
	end

	if self.BoundInstance ~= nil then
		error("[ReplicaServer]: Can't change Replica bind to another Instance")
	end

	if
		instance:IsA("Model") == true
		and (
			instance.ModelStreamingMode == Enum.ModelStreamingMode.Default
			or instance.ModelStreamingMode == Enum.ModelStreamingMode.Nonatomic
		)
	then
		warn(
			'[ReplicaServer]: Bound Replica to a model that has improper "ModelStreamingMode" setup; Traceback:\n'
				.. debug.traceback()
		)
	end

	local bind_value = BindValuePrefab:Clone()
	bind_value.Value = self.Id

	self.Tags[BIND_TAG] = true
	self.BoundInstance = instance
	self.bind_value = bind_value

	bind_value.Parent = instance

	local self_id = self.Id
	if self.replication ~= nil then
		if self.replication[REPLICATION_ALL] == true then
			for player in pairs(ReadyPlayers) do
				RemoteBind:FireClient(player, self_id)
			end
		else
			for player in pairs(self.replication) do
				RemoteBind:FireClient(player, self_id)
			end
		end
	end
end

function Replica:Replicate()
	if self.Parent ~= nil then
		error("[ReplicaServer]: Can't selectively replicate Replica parented to another Replica")
	end

	if self.creation == nil then
		GenerateCreation(self)
		TopReplicas[self] = true
	elseif self.replication[REPLICATION_ALL] == true then
		return
	end

	local creation = self.creation
	local replication = self.replication

	for player in pairs(ReadyPlayers) do
		if replication[player] == nil then
			RemoteCreate:FireClient(player, creation)
		else
			local selective_lookup = SelectiveSubscriptions[player]
			selective_lookup[self] = nil
		end
	end

	table.clear(replication)
	replication[REPLICATION_ALL] = true
	ReplicationAllReplicas[self] = true
end

function Replica:DontReplicate()
	if self.Parent ~= nil then
		error("[ReplicaServer]: Can't selectively replicate Replica parented to another Replica")
	end

	local replication = self.replication

	if replication == nil or next(replication) == nil then
		return
	end

	ReplicationAllReplicas[self] = nil

	local self_id = self.Id

	if replication[REPLICATION_ALL] == true then
		for player in pairs(ReadyPlayers) do
			RemoteDestroy:FireClient(player, self_id)
		end
	else
		for player in pairs(replication) do
			RemoteDestroy:FireClient(player, self_id)
			SelectiveSubscriptions[player][self] = nil
		end
	end

	table.clear(replication)
end

function Replica:Subscribe(player: Player)
	if self.Parent ~= nil then
		error("[ReplicaServer]: Can't selectively replicate Replica parented to another Replica")
	end

	if self.creation == nil then
		GenerateCreation(self)
		TopReplicas[self] = true
	elseif self.replication[REPLICATION_ALL] == true then
		error('[ReplicaServer]: "Subscribe()" is locked after calling "Replicate()"')
	end

	if ReadyPlayers[player] == nil then
		warn('[ReplicaServer]: Called "Subscribe()" on a non-ready player; Traceback:\n' .. debug.traceback())
		return
	end

	local creation = self.creation
	local replication = self.replication

	if replication[player] ~= nil then
		return
	end

	replication[player] = true
	SelectiveSubscriptions[player][self] = true
	RemoteCreate:FireClient(player, creation)
end

function Replica:Unsubscribe(player: Player)
	if self.Parent ~= nil then
		error("[ReplicaServer]: Can't selectively replicate Replica parented to another Replica")
	end

	local replication = self.replication

	if replication == nil then
		return
	end

	if replication[REPLICATION_ALL] == true then
		error('[ReplicaServer]: "Unsubscribe()" is locked after calling "Replicate()"')
	end

	if replication[player] ~= nil then
		replication[player] = nil
		SelectiveSubscriptions[player][self] = nil
		RemoteDestroy:FireClient(player, self.Id)
	end
end

function Replica:Identify(): string
	local tag_string = ""
	local first_tag = true
	for key, value in pairs(self.Tags) do
		tag_string = tag_string .. (first_tag and "" or ";") .. tostring(key) .. "=" .. tostring(value)
		first_tag = false
	end
	return "[Id:" .. self.Id .. ";Token:" .. self.Token .. ";Tags:[" .. tag_string .. "]]"
end

function Replica:IsActive(): boolean
	return self.Maid:IsActive()
end

local function DestroyReplica(replica)
	for child in pairs(replica.Children) do
		DestroyReplica(child)
	end

	local id = replica.Id
	Replicas[id] = nil
	replica.Maid:Unlock(MAID_LOCK)
	replica.Maid:Cleanup()
	if replica.BoundInstance ~= nil then
		replica.BoundInstance = nil
		replica.bind_value:Destroy()
		replica.bind_value = nil
	end
	if replica.creation ~= nil then
		replica.creation[tostring(id)] = nil
	end
	setmetatable(replica, LockedReplica)
end

function Replica:Destroy()
	local self_id = self.Id

	if Replicas[self_id] == nil then
		return
	end

	local is_top = TopReplicas[self] == true

	if self.replication ~= nil then
		if self.replication[REPLICATION_ALL] == true then
			for player in pairs(ReadyPlayers) do
				RemoteDestroy:FireClient(player, self_id)
			end
		else
			for player in pairs(self.replication) do
				RemoteDestroy:FireClient(player, self_id)
				if is_top == true then
					SelectiveSubscriptions[player][self] = nil
				end
			end
		end
	end

	TopReplicas[self] = nil
	ReplicationAllReplicas[self] = nil

	if self.Parent ~= nil then
		self.Parent.Children[self] = nil
	end

	DestroyReplica(self)
end

----- LockedReplica -----

do
	local keep_methods = {
		Identify = true,
		Destroy = true,
	}

	for name, fn in pairs(Replica) do
		if name ~= "__index" then
			if keep_methods[name] == true then
				LockedReplica[name] = fn
			else
				LockedReplica[name] = function(self)
					error(
						'[ReplicaServer]: Tried to call method "'
							.. name
							.. '" for a destroyed replica; '
							.. self:Identify()
					)
				end
			end
		end
	end
end

----- Init -----

RemoteRequestData.OnServerEvent:Connect(function(player: Player)
	if ReadyPlayers[player] ~= nil and player:IsDescendantOf(Players) == true then
		return
	end

	local creation = {}

	for replica in pairs(ReplicationAllReplicas) do
		table.insert(creation, replica.creation)
	end
	RemoteCreate:FireClient(player, creation)

	RemoteRequestData:FireClient(player)

	ReadyPlayers[player] = true
	SelectiveSubscriptions[player] = {}
	Replica.NewReadyPlayer:Fire(player)
end)

local function RemoteSignalHandle(player: Player, id: number, ...)
	if ReadyPlayers[player] == nil or GlobalRateLimit:CheckRate(player) == false or type(id) ~= "number" then
		return
	end

	local replica = Replicas[id]

	if replica ~= nil then
		if
			replica.replication ~= nil
			and (replica.replication[REPLICATION_ALL] == true or replica.replication[player] ~= nil)
		then
			replica.OnServerEvent:Fire(player, ...)
		end
	end
end

RemoteSignal.OnServerEvent:Connect(RemoteSignalHandle)
RemoteSignalUnreliable.OnServerEvent:Connect(RemoteSignalHandle)

Players.PlayerRemoving:Connect(function(player)
	if ReadyPlayers[player] == nil then
		return
	end

	for replica in pairs(SelectiveSubscriptions[player]) do
		replica.replication[player] = nil
	end

	ReadyPlayers[player] = nil
	SelectiveSubscriptions[player] = nil
	Replica.RemovingReadyPlayer:Fire(player)
end)

return Replica
