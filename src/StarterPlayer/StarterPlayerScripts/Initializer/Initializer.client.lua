local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Net = require(Locations.Shared.Net.Net)
local Loader = require(Locations.Shared.Util.Loader)
local Registry = require(script.Parent:WaitForChild("Registry"):WaitForChild("Registry"))
local SoundManager = require(Locations.Shared.Util:WaitForChild("SoundManager"))

Net:Init()
SoundManager:Init()

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
}

Loader:Load(entries, registry, Net)

-- Initialize EmoteService early so replication listener is active
local EmoteService = require(Locations.Game:WaitForChild("Emotes"))
EmoteService.init()
