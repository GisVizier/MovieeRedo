--[[
	Cloudskip VFX Module (Airborne kit)

	Receives SpectateVFXForward when a spectated player uses Cloudskip or Updraft,
	and ensures the kit animation plays on the spectate viewmodel.

	The caster's animation is already replicated via ViewmodelActionReplicated (reliable).
	This module acts as a fallback: SpectateVFXForward (unreliable) may arrive first,
	letting the spectator see the animation sooner.

	Data from Airborne ClientKit:
	- Action: "cloudSkip" | "upDraft"
	- Animation: string (animation name, e.g. "CloudskipDash" or "Updraft")
	- position: Vector3
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local ACTION_TO_TRACK = {
	upDraft = "Updraft",
	cloudSkip = "CloudskipDash",
}

local Cloudskip = {}
Cloudskip._spectateCleanups = {}

function Cloudskip:Validate(_player, data)
	return typeof(data) == "table"
end

function Cloudskip:User(originUserId, data)
	if not data then return end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end

	local isLocal = localPlayer.UserId == originUserId
	local isSpectate = data._spectate == true
	if not isLocal and not isSpectate then return end

	local action = data.Action
	if not action then return end

	if isSpectate then
		local trackName = ACTION_TO_TRACK[action]
		if trackName then
			local spectateController = ServiceRegistry:GetController("Spectate")
			if spectateController and spectateController.PlayKitAnimation then
				spectateController:PlayKitAnimation(trackName)
			end
		end
	end
end

function Cloudskip:CleanupSpectateEffects()
	for _, entry in ipairs(self._spectateCleanups) do
		if type(entry.cleanup) == "function" then
			pcall(entry.cleanup)
		end
	end
	self._spectateCleanups = {}
end

return Cloudskip
