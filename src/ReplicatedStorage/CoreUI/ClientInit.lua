local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreUI = require(ReplicatedStorage.CoreUI)
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
local KitController = require(ReplicatedStorage.KitSystem.KitController)

local ClientInit = {}

function ClientInit.start(screenGui)

	PlayerDataTable.init()

	local ui = CoreUI.new(screenGui)

	ui:init()

	local kitController = KitController.new(Players.LocalPlayer, ui)
	kitController:init()
	ui._kitController = kitController

	ui:on("EquipKitRequest", function(kitId)
		if ui._kitController then
			ui._kitController:requestEquipKit(kitId)
		end
	end)

	-- NOTE: AnimeFPSProject uses StarterPlayerScripts/Initializer/Controllers/UI/UIController.lua
	-- for wiring and Net integration; this file is kept only as reference for RojoUiReference.
	-- It intentionally does not connect remotes here.
	-- (RojoUiReference had a StartMatch remote listener here.)

	ui:on("LoadoutComplete", function(data)
		-- Rojo UI testing flow (no HUD): stop here.
	end)


	return ui
end

return ClientInit
