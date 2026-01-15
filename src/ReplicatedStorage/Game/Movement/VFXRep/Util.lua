local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = {}

function Util.getMovementTemplate(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local vfx = assets:FindFirstChild("VFX")
	local movement = vfx and vfx:FindFirstChild("MovementFX")
	local fromNew = movement and movement:FindFirstChild(name)
	if fromNew then
		return fromNew
	end
	local legacy = assets:FindFirstChild("MovementFX")
	return legacy and legacy:FindFirstChild(name) or nil
end

function Util.getPlayerRoot(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	return character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")) or nil
end

return Util
