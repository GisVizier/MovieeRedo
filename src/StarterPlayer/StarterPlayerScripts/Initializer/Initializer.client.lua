local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- Disable Roblox Core UI (Chat, PlayerList, Backpack, Health, EmotesMenu)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Net = require(Locations.Shared.Net.Net)
local Loader = require(Locations.Shared.Util.Loader)
local Registry = require(script.Parent:WaitForChild("Registry"):WaitForChild("Registry"))
local SoundManager = require(Locations.Shared.Util:WaitForChild("SoundManager"))

Net:Init()
SoundManager:Init()

-- Initialize VFXRep early BEFORE controllers load to ensure OnClientEvent is connected
-- before any VFX events arrive from the server. This prevents "did you forget to implement OnClientEvent?" warnings.
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))
VFXRep:Init(Net, false)

-- Initialize VoxelDestruction early so its OnClientEvent handler is active for ALL clients,
-- not just the player who has HonoredOne equipped. Without this, destruction events from
-- the server are silently dropped on clients that never require the module.
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("VoxelDestruction"))

local registry = Registry.new()

local controllersFolder = script.Parent:WaitForChild("Controllers")
local entries = {
	{
		name = "Input",
		module = controllersFolder:WaitForChild("Input"):WaitForChild("InputController"),
	},
	{
		name = "UI",
		module = controllersFolder:WaitForChild("UI"):WaitForChild("UIController"),
	},
	{
		name = "Character",
		module = controllersFolder:WaitForChild("Character"):WaitForChild("CharacterController"),
	},
	{
		name = "Movement",
		module = controllersFolder:WaitForChild("Movement"):WaitForChild("MovementController"),
	},
	{
		name = "AnimationController",
		module = controllersFolder:WaitForChild("Character"):WaitForChild("AnimationController"),
	},
	{
		name = "Ping",
		module = controllersFolder:WaitForChild("Network"):WaitForChild("PingController"),
	},
	{
		name = "Replication",
		module = controllersFolder:WaitForChild("Replication"):WaitForChild("ReplicationController"),
	},
	{
		name = "Camera",
		module = controllersFolder:WaitForChild("Camera"):WaitForChild("CameraController"),
	},
	{
		name = "Viewmodel",
		module = controllersFolder:WaitForChild("Viewmodel"):WaitForChild("ViewmodelController"),
	},
	{
		name = "KitVFX",
		module = controllersFolder:WaitForChild("KitVFX"):WaitForChild("KitVFXController"),
	},
	{
		name = "Weapon",
		module = controllersFolder:WaitForChild("Weapon"):WaitForChild("WeaponController"),
	},
	{
		name = "Combat",
		module = controllersFolder:WaitForChild("Combat"):WaitForChild("CombatController"),
	},
	{
		name = "GadgetController",
		module = controllersFolder:WaitForChild("Gadgets"):WaitForChild("GadgetController"),
	},
	{
		name = "Knockback",
		module = controllersFolder:WaitForChild("Knockback"):WaitForChild("KnockbackController"),
	},
	{
		name = "Queue",
		module = controllersFolder:WaitForChild("Queue"):WaitForChild("QueueController"),
	},
	{
		name = "VoxelDebris",
		module = controllersFolder:WaitForChild("VoxelDebris"):WaitForChild("VoxelDebrisController"),
	},
}

Loader:Load(entries, registry, Net)

-- Signal server we can receive replication
Net:FireServer("ClientReplicationReady")
local localPlayer = game:GetService("Players").LocalPlayer
if localPlayer then
	localPlayer:SetAttribute("ClientReplicationReady", true)
end

-- Initialize EmoteService early so replication listener is active
local EmoteService = require(Locations.Game:WaitForChild("Emotes"))
EmoteService.init()
