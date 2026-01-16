local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local HonoredOne = {}

HonoredOne.Ability = {}

function HonoredOne.Ability.AbilityActivated(props)
	print("[HonoredOneVFX] AbilityActivated", props.event, props.position)
	-- Example:
	-- local pos = props.position
	-- local template = ReplicatedStorage.Assets.VFX.HonoredOne.Duality_Cast
	-- VFXPlayer:Play(template, pos)
end

function HonoredOne.Ability.AbilityEnded(_props)
	print("[HonoredOneVFX] AbilityEnded")
	-- Optional: play a release VFX.
end

function HonoredOne.Ability.AbilityInterrupted(_props)
	print("[HonoredOneVFX] AbilityInterrupted")
	-- Optional: play a fail/cancel VFX.
end

HonoredOne.Ultimate = {}

function HonoredOne.Ultimate.AbilityActivated(props)
	print("[HonoredOneVFX] Ultimate AbilityActivated", props.event, props.position)
	-- Example:
	-- local pos = props.position
	-- local template = ReplicatedStorage.Assets.VFX.HonoredOne.PurpleSingularity_Activate
	-- VFXPlayer:Play(template, pos)
end

function HonoredOne.Ultimate.AbilityEnded(props)
	print("[HonoredOneVFX] Ultimate AbilityEnded", props.event, props.position)
	-- Example:
	-- local pos = props.position
	-- local template = ReplicatedStorage.Assets.VFX.HonoredOne.PurpleSingularity_End
	-- VFXPlayer:Play(template, pos)
end

function HonoredOne.Ultimate.AbilityInterrupted(props)
	print("[HonoredOneVFX] Ultimate AbilityInterrupted", props.event, props.position)
	-- Example:
	-- local pos = props.position
	-- local template = ReplicatedStorage.Assets.VFX.HonoredOne.PurpleSingularity_Interrupt
	-- VFXPlayer:Play(template, pos)
end

return HonoredOne
