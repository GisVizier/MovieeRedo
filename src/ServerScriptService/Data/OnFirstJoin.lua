--[[
	Called when a player joins for the first time.
	Seeds starter data.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataGlobal = require(script.Parent.DataGlobal)

return function(Data)
	Data.FirstJoin = DataGlobal.osTime(true)
	print("[Data] First join! FirstJoin timestamp set")
	-- Starter items are already in Default; add any first-join bonuses here if needed
end
