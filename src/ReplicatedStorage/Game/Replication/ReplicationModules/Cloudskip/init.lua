--[[
	Cloudskip VFX Module (Airborne kit)
	
	Handles visual effects for Airborne's Cloudskip (horizontal dash) and Updraft (vertical burst).
	
	Functions:
	- User(originUserId, data) - Viewmodel/position effects for caster and spectators
	
	Data:
	- position: Vector3 or { X, Y, Z }
	- ViewModel: ViewmodelRig
	- Action: "cloudSkip" | "upDraft"
	- Animation: string (animation name)
	
	Spectate: When _spectate is true, effects are shown for the spectated player.
	CleanupSpectateEffects() is called when spectating ends.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local Cloudskip = {}

-- Track spectate effects for cleanup (e.g. particles, trails that persist)
Cloudskip._spectateCleanups = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function ReplicateFX(module, action, fxData)
	local clientsFolder = script:FindFirstChild("Clients")
	if not clientsFolder then return nil end
	local nmodule = clientsFolder:FindFirstChild(module)
	if nmodule then
		local mod = require(nmodule)
		if mod[action] then
			return mod[action](nil, fxData)
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

function Cloudskip:Validate(_player, data)
	return typeof(data) == "table"
end

--------------------------------------------------------------------------------
-- User - Cloudskip/Updraft VFX for caster and spectators
--------------------------------------------------------------------------------

function Cloudskip:User(originUserId, data)
	if not data then return end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end

	local isLocal = localPlayer.UserId == originUserId
	local isSpectate = data._spectate == true
	if not isLocal and not isSpectate then
		return
	end

	local character = data.Character or (Players:GetPlayerByUserId(originUserId) and Players:GetPlayerByUserId(originUserId).Character) or localPlayer.Character
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	local ViewModel = data.ViewModel or (viewmodelController and viewmodelController:GetActiveRig())

	local action = data.Action -- "cloudSkip" or "upDraft"
	if not action then return end

	-- Play VFX via Clients submodule when it exists
	local fxCleanup = ReplicateFX("cloudskip", action, {
		Character = character,
		ViewModel = ViewModel,
		position = data.position,
		Animation = data.Animation,
	})

	if fxCleanup and type(fxCleanup) == "function" and isSpectate then
		table.insert(Cloudskip._spectateCleanups, { cleanup = fxCleanup })
	end
end

--------------------------------------------------------------------------------
-- Cleanup when spectating ends (Airborne Cloudskip/Updraft effects)
--------------------------------------------------------------------------------

function Cloudskip:CleanupSpectateEffects()
	for _, entry in ipairs(Cloudskip._spectateCleanups) do
		if entry.cleanup and type(entry.cleanup) == "function" then
			pcall(entry.cleanup)
		end
	end
	Cloudskip._spectateCleanups = {}
end

return Cloudskip
