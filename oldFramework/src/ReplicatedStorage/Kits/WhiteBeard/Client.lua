local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local VFXController = require(Locations.Modules.Systems.Core.VFXController)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

local Client = {}
Client.Config = require(script.Parent.Config)

local function getViewmodelSwapController()
	return ServiceRegistry:GetController("ViewmodelSwapController")
end

function Client.OnAbility(inputState)
	local player = game.Players.LocalPlayer
	if not player.Character or not player.Character.PrimaryPart then
		return false
	end

	local swapController = getViewmodelSwapController()
	if not swapController then
		warn("[WhiteBeard] ViewmodelSwapController not available")
		return false
	end

	if inputState == Enum.UserInputState.Begin then
		print("[WhiteBeard] Ability: Charge started")
		swapController:ShowAbilityViewmodel("WhiteBeard_Ability", "Charge", Client.Config.Ability.Animations)
		return false

	elseif inputState == Enum.UserInputState.End then
		print("[WhiteBeard] Ability: Release")

		swapController:PlayAnimationAndWait("WhiteBeard_Ability", "Release", true)

		local position = player.Character.PrimaryPart.Position

		VFXController:PlayVFXReplicated("WhiteBeard.QuakeBall", position, {
			Radius = 15,
			Owner = player.UserId
		})

		return true, {
			TargetPosition = position
		}
	end

	return false
end

function Client.OnUltimate()
	local player = game.Players.LocalPlayer
	if not player.Character or not player.Character.PrimaryPart then
		return false
	end

	local swapController = getViewmodelSwapController()
	if not swapController then
		warn("[WhiteBeard] ViewmodelSwapController not available")
		return false
	end

	print("[WhiteBeard] Ultimate: Activate")
	swapController:ShowAbilityViewmodel("WhiteBeard_Ultimate", "Activate", Client.Config.Ultimate.Animations)

	local mouse = player:GetMouse()
	local targetPos = mouse.Hit.Position

	task.delay(0.1, function()
		swapController:PlayAnimationAndWait("WhiteBeard_Ultimate", "Activate", true)
	end)

	return true, {
		TargetPosition = targetPos
	}
end

return Client
