local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Global = require(ReplicatedStorage.Modules.Global)

local Races = require(ReplicatedStorage.Modules.Global.Libraries.Races)
local RarityHandler = require(ReplicatedStorage.Modules.Global.Utility.RarityHandler)

local PickItem = RarityHandler.PickItem

return function(Data)
	Data.FirstJoin = Global.osTime(true)

	local FirstRace = PickItem(Races)
	warn("SPAWNED IN WITH THE RACE:", FirstRace)
	Data.Race = { Name = FirstRace }
end
