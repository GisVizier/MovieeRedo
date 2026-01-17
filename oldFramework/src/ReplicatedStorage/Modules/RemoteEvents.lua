local RemoteEvents = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)

local eventsFolder = nil
local events = {}

-- ADD NEW EVENTS HERE - DON'T FORGET TO UPDATE THIS LIST
local EVENT_DEFINITIONS = {
	{ name = "ServerReady", description = "Fired when server has finished initializing all services" },
	{ name = "CharacterSpawned", description = "Fired when a character is successfully spawned" },
	{ name = "CharacterRemoving", description = "Fired when a character is being removed" },
	{ name = "RequestCharacterSpawn", description = "Fired when client requests to spawn their character" },
	{ name = "RequestRespawn", description = "Fired when client requests to respawn their character" },
	{ name = "CharacterSetupComplete", description = "Fired when client has fully completed character setup" },

	{ name = "RequestNPCSpawn", description = "Fired when client requests to spawn an NPC" },
	{ name = "RequestNPCRemoveOne", description = "Fired when client requests to remove one NPC" },

	-- TEMPORARY: Remove when real player model rigs are added
	{ name = "CrouchStateChanged", description = "Fired when client crouch state changes for visual replication" },

	-- Audio system events
	{ name = "PlaySoundRequest", description = "Fired when client requests sound replication to other players" },
	{ name = "PlaySound", description = "Fired to play sound on other clients" },
	{
		name = "StopSoundRequest",
		description = "Fired when client requests to stop sound replication on other players",
	},
	{ name = "StopSound", description = "Fired to stop sound on other clients" },

	-- Round system events
	{ name = "PhaseChanged", description = "Fired when round phase changes (Intermission, MatchStart, etc.)" },
	{
		name = "PlayerStateChanged",
		description = "Fired when player state changes (Lobby, Runner, Tagger, Ghost, etc.)",
	},
	{ name = "NPCStateChanged", description = "Fired when NPC state changes (Lobby, Runner, Tagger, Ghost, etc.)" },
	{ name = "MapLoaded", description = "Fired when a new map is loaded" },
	{ name = "RoundResults", description = "Fired at round end with winners, tagged, and tagger lists" },
	{ name = "TaggerSelected", description = "Fired when a player is selected as tagger" },
	{ name = "PlayerTagged", description = "Fired when a runner is tagged by a tagger" },
	{ name = "AFKToggle", description = "Fired when player toggles AFK status" },

	-- Animation system events
	{ name = "PlayAnimation", description = "Fired when server tells client to play an animation on a character" },
	{ name = "StopAnimation", description = "Fired when server tells client to stop an animation on a character" },

	-- Weapon system events
	{ name = "WeaponFired", description = "Fired when client shoots a weapon (sends hit data for server validation)" },
	{
		name = "PlayerDamaged",
		description = "Fired when server applies damage to a player (for client visual feedback)",
	},

	-- Health system events
	{
		name = "PlayerHealthChanged",
		description = "Fired when player health changes (damage, healing, spawn)",
	},
	{ name = "PlayerDied", description = "Fired when client notifies server that player died" },
	{ name = "PlayerKilled", description = "Fired when a player is killed (broadcasted to all clients)" },
	{ name = "PlayerRagdolled", description = "Fired when a player ragdolls (for P2P ragdoll replication)" },

	-- Custom replication system events (using UnreliableRemoteEvent for high-frequency updates)
	-- UnreliableRemoteEvent is CRITICAL here - prevents Roblox throttling at 60Hz
	-- RemoteEvent at 60Hz causes ~24% artificial packet loss due to throttling
	-- UnreliableRemoteEvent allows true 60Hz with only natural network packet loss (~0-2%)
	{
		name = "CharacterStateUpdate",
		description = "Fired when client sends character state to server (position, rotation, velocity)",
		unreliable = true,
	},
	{
		name = "CharacterStateReplicated",
		description = "Fired when server broadcasts character states to all clients",
		unreliable = true,
	},
	{
		name = "ServerCorrection",
		description = "Fired when server corrects client's position (anti-cheat reconciliation)",
		unreliable = false,
	}, -- Keep reliable for corrections
	{
		name = "RequestInitialStates",
		description = "Fired when client is ready to receive initial player states (late-join sync)",
		unreliable = false,
	},

	{
		name = "ArmLookUpdate",
		description = "Fired when client sends arm/head look direction to server",
		unreliable = true,
	},
	{
		name = "ArmLookReplicated",
		description = "Fired when server broadcasts arm look directions to all clients",
		unreliable = true,
	},

	{ name = "RequestLoadout", description = "Client requests their loadout from server" },
	{ name = "LoadoutData", description = "Server sends loadout data to client" },
	{ name = "SwitchWeapon", description = "Client requests to switch weapon slot" },
	{ name = "WeaponSwitched", description = "Server confirms weapon switch to client" },
	{ name = "UpdateLoadoutSlot", description = "Client requests to change weapon in a slot" },

	-- VFX system events
	{ name = "PlayVFXRequest", description = "Client requests VFX replication to other players" },
	{ name = "PlayVFX", description = "Server broadcasts VFX to other clients" },
	{ name = "StopVFXRequest", description = "Client requests VFX stop replication" },
	{ name = "StopVFX", description = "Server broadcasts VFX stop to other clients" },

	{ name = "StartContinuousVFXRequest", description = "Client requests to start a continuous VFX on other clients" },
	{ name = "StartContinuousVFX", description = "Server broadcasts start of continuous VFX to other clients" },

	-- Kit system events
	{ name = "ActivateAbility", description = "Client requests ability activation" },
	{ name = "AbilityActivated", description = "Server confirms ability started (broadcast)" },
	{ name = "AbilityEnded", description = "Server notifies ability ended (broadcast)" },
	{ name = "AbilityInterrupted", description = "Server notifies ability interrupted (broadcast)" },
	{ name = "UltimateChargeUpdate", description = "Server updates client on ultimate charge" },
	{ name = "KitAssigned", description = "Server assigns kit to player" },
	{ name = "RequestKitState", description = "Client requests current kit state" },
	{ name = "KitStateUpdate", description = "Server sends kit state to client" },
}

function RemoteEvents:Init()
	Log:RegisterCategory("REMOTE", "RemoteEvent management and networking")

	eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "RemoteEvents"
		eventsFolder.Parent = ReplicatedStorage
	end

	for _, eventDef in pairs(EVENT_DEFINITIONS) do
		self:CreateEvent(eventDef.name, eventDef.description, eventDef.unreliable)
	end

	Log:Info("REMOTE", "Initialized RemoteEvents system", { EventCount = #EVENT_DEFINITIONS })
end

function RemoteEvents:CreateEvent(eventName, description, unreliable)
	local existingEvent = eventsFolder:FindFirstChild(eventName)

	-- CRITICAL: Delete existing event if unreliability doesn't match
	-- This ensures we recreate RemoteEvent → UnreliableRemoteEvent on config change
	if existingEvent then
		local isCurrentlyUnreliable = existingEvent:IsA("UnreliableRemoteEvent")
		local shouldBeUnreliable = unreliable or false

		if isCurrentlyUnreliable ~= shouldBeUnreliable then
			-- Type mismatch - delete and recreate
			Log:Warn("REMOTE", "Recreating event with different reliability", {
				Event = eventName,
				OldType = existingEvent.ClassName,
				NewType = unreliable and "UnreliableRemoteEvent" or "RemoteEvent",
			})
			existingEvent:Destroy()
		else
			-- Type matches - reuse existing
			events[eventName] = existingEvent
			return existingEvent
		end
	end

	-- Use UnreliableRemoteEvent for high-frequency position updates (more efficient, allows packet drops)
	local remoteEvent
	if unreliable then
		remoteEvent = Instance.new("UnreliableRemoteEvent")
	else
		remoteEvent = Instance.new("RemoteEvent")
	end

	remoteEvent.Name = eventName
	remoteEvent.Parent = eventsFolder

	if description then
		remoteEvent:SetAttribute("Description", description)
	end
	if unreliable then
		remoteEvent:SetAttribute("Unreliable", true)
	end

	events[eventName] = remoteEvent

	Log:Debug("REMOTE", "Created event", {
		Event = eventName,
		Description = description,
		Unreliable = unreliable or false,
	})
	return remoteEvent
end

function RemoteEvents:GetEvent(eventName)
	return events[eventName]
end

function RemoteEvents:GetAllEvents()
	return events
end

function RemoteEvents:AddEvent(eventName, description)
	table.insert(EVENT_DEFINITIONS, { name = eventName, description = description or "" })

	if eventsFolder then
		return self:CreateEvent(eventName, description)
	end

	return nil
end

function RemoteEvents:RemoveEvent(eventName)
	local event = events[eventName]
	if event then
		event:Destroy()
		events[eventName] = nil

		for i, eventDef in pairs(EVENT_DEFINITIONS) do
			if eventDef.name == eventName then
				table.remove(EVENT_DEFINITIONS, i)
				break
			end
		end

		Log:Debug("REMOTE_EVENTS", "Removed event", { EventName = eventName })
	end
end

function RemoteEvents:FireClient(eventName, player, ...)
	local event = self:GetEvent(eventName)
	if event then
		event:FireClient(player, ...)
	else
		Log:Warn("REMOTE", "Event not found", { Event = eventName })
	end
end

function RemoteEvents:FireAllClients(eventName, ...)
	local event = self:GetEvent(eventName)
	if event then
		event:FireAllClients(...)
	else
		Log:Warn("REMOTE", "Event not found", { Event = eventName })
	end
end

function RemoteEvents:FireServer(eventName, ...)
	local event = self:GetEvent(eventName)
	if event then
		event:FireServer(...)
	else
		Log:Warn("REMOTE", "Event not found", { Event = eventName })
	end
end

function RemoteEvents:ConnectServer(eventName, callback)
	local event = self:GetEvent(eventName)
	if event then
		return event.OnServerEvent:Connect(callback)
	else
		Log:Warn("REMOTE", "Event not found", { Event = eventName })
		return nil
	end
end

function RemoteEvents:ConnectClient(eventName, callback)
	local event = self:GetEvent(eventName)
	if event then
		return event.OnClientEvent:Connect(callback)
	else
		Log:Warn("REMOTE", "Event not found", { Event = eventName })
		return nil
	end
end

RemoteEvents:Init()

return RemoteEvents
