local collectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local runService = game:GetService("RunService")

local global = require(replicatedStorage.Global)

local module = {}

local function init()
	repeat
		runService.Heartbeat:Wait()
	until global.ModulesLoaded

	for _, character in global.SharedModules["EthoTag"].GetTagged("Humanoids") do
		if character:IsDescendantOf(workspace.World.Live) and not character:GetAttribute("NotActualRig") then
			--warn(`sucessfully set up ragdoll for {character.Name}`)
			global.ServerModules["Ragdoll"]:Setup(character)
		end
	end

	collectionService:GetInstanceAddedSignal("Humanoids"):Connect(function(character: Model)
		if character:IsDescendantOf(workspace.World.Live) and not character:GetAttribute("NotActualRig") then
			--warn(`sucessfully set up ragdoll for {character.Name}`)
			global.ServerModules["Ragdoll"]:Setup(character)
		end
	end)
end

task.spawn(init)

return module
