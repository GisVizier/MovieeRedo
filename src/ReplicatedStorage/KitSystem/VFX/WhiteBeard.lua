local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local WhiteBeard = {}

-- Example "effect" table: effect == "Ability" (matches KitService payload.effect for ability)
WhiteBeard.Ability = {}

function WhiteBeard.Ability.AbilityActivated(props)
	print("[WhiteBeardVFX] AbilityActivated", props.event, props.position)
	-- Example:
	-- local pos = props.position
	-- local template = ReplicatedStorage.Assets.VFX.WhiteBeard.QuakeBall_Cast
	-- VFXPlayer:Play(template, pos)
end

function WhiteBeard.Ability.AbilityEnded(_props)
	print("[WhiteBeardVFX] AbilityEnded")
	-- Optional: play a release VFX.
end

function WhiteBeard.Ability.AbilityInterrupted(_props)
	print("[WhiteBeardVFX] AbilityInterrupted")
	-- Optional: play a fail/cancel VFX.
end

-- Example of a custom server event routed through the same "effect" table:
function WhiteBeard.Ability.TargetHit(props)
	print("[WhiteBeardVFX] TargetHit", props.event, props.position)
	-- Example:
	-- local pos = props.position
	-- local template = ReplicatedStorage.Assets.VFX.WhiteBeard.QuakeBall_Hit
	-- VFXPlayer:Play(template, pos)
end

-- Ultimate handlers (effect == "Ultimate")
WhiteBeard.Ultimate = {}

function WhiteBeard.Ultimate.AbilityActivated(props)
	print("[WhiteBeardVFX] Ultimate AbilityActivated", props.event, props.position)
	-- Example:
	-- local pos = props.position
	-- local template = ReplicatedStorage.Assets.VFX.WhiteBeard.Ultimate_Activate
	-- VFXPlayer:Play(template, pos)
end

function WhiteBeard.Ultimate.AbilityEnded(props)
	print("[WhiteBeardVFX] Ultimate AbilityEnded", props.event, props.position)
	-- Example:
	-- local pos = props.position
	-- local template = ReplicatedStorage.Assets.VFX.WhiteBeard.Ultimate_End
	-- VFXPlayer:Play(template, pos)
end

function WhiteBeard.Ultimate.AbilityInterrupted(props)
	print("[WhiteBeardVFX] Ultimate AbilityInterrupted", props.event, props.position)
	-- Example:
	-- local pos = props.position
	-- local template = ReplicatedStorage.Assets.VFX.WhiteBeard.Ultimate_Interrupt
	-- VFXPlayer:Play(template, pos)
end

return WhiteBeard

