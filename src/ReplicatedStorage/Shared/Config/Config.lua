local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Global = ReplicatedStorage:WaitForChild("Global")
local Character = require(Global:WaitForChild("Character"))
local Movement = require(Global:WaitForChild("Movement"))
local Controls = require(Global:WaitForChild("Controls"))
local Camera = require(Global:WaitForChild("Camera"))
local System = require(Global:WaitForChild("System"))

local Config = {
	Controls = Controls,
	Camera = Camera,
	Gameplay = {
		Character = Character,
		Sliding = Movement.Sliding,
		Cooldowns = Movement.Cooldowns,
		VFX = Movement.VFX,
	},
	System = System,
}

return Config
