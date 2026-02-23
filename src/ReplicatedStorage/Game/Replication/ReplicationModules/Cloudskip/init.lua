--[[
	Cloudskip VFX Module (Airborne kit)

	Handles visual effects for Cloudskip / Updraft abilities.

	Caster (isLocal):
	  Runs the Clients/<action> sub-modules at timed marker offsets to
	  create wind-arm particles, jump beams/meshes, dash effects, etc.

	Spectator (isSpectate):
	  1. Plays the kit animation on the spectate viewmodel (via PlayKitAnimation).
	  2. Runs the SAME Clients/<action> sub-modules with the spectate viewmodel
	     and target character so the spectator sees 1:1 VFX.
	  3. Plays the ability sound at the target character's root.

	Data from Airborne ClientKit:
	  Action   : "cloudSkip" | "upDraft"
	  Animation: string (animation name, e.g. "CloudskipDash" or "Updraft")
	  position : Vector3  (caster HRP position)
	  ViewModel: Instance (caster rig — stripped before network, re-injected for spectators)
	  Character: Instance (target character — injected for spectators)
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local Util = require(script.Parent.Util)

local ACTION_INFO = {
	upDraft = {
		track = "Updraft",
		soundId = "rbxassetid://116592400788380",
		volume = 1,
		events = {
			{ name = "windhand", fn = "windhand", delay = 0.06 },
			{ name = "jump",     fn = "jump",     delay = 0.66 },
		},
	},
	cloudSkip = {
		track = "CloudskipDash",
		soundId = "rbxassetid://95386134717900",
		volume = 1,
		events = {
			{ name = "windhand", fn = "windhand", delay = 0.01 },
			{ name = "dash",     fn = "dash",     delay = 0.2  },
		},
	},
}

local Cloudskip = {}
Cloudskip._spectateCleanups = {}

function Cloudskip:Validate(_player, data)
	return typeof(data) == "table"
end

local function requireClient(actionName)
	local clients = script:FindFirstChild("Clients")
	if not clients then return nil end
	local mod = clients:FindFirstChild(actionName)
	if not mod then return nil end
	local ok, result = pcall(require, mod)
	if ok then return result end
	return nil
end

function Cloudskip:User(originUserId, data)
	if not data then return end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end

	local isLocal = localPlayer.UserId == originUserId
	local isSpectate = data._spectate == true
	if not isLocal and not isSpectate then return end

	local info = ACTION_INFO[data.Action]
	if not info then return end

	if isLocal then
		-- === CASTER PATH ===
		local player = Players:GetPlayerByUserId(originUserId)
		local character = player and player.Character
		local viewmodelController = ServiceRegistry:GetController("Viewmodel")
		local viewmodelRig = viewmodelController and viewmodelController:GetActiveRig()
		if not character or not viewmodelRig then return end

		local root = Util.getPlayerRoot(originUserId)
		if not root then return end

		local clientModule = requireClient(data.Action)
		if not clientModule then return end

		for _, event in ipairs(info.events) do
			task.delay(event.delay, function()
				if viewmodelController:GetActiveSlot() ~= "Fists" then return end
				if not viewmodelRig.Model:GetAttribute("PlayingAnimation_" .. (data.Animation or "")) then return end

				local fn = clientModule[event.fn]
				if fn then
					fn(nil, { Character = character, ViewModel = viewmodelRig.Model })
				end
			end)
		end

	else
		-- === SPECTATOR PATH ===
		local spectateController = ServiceRegistry:GetController("Spectate")

		-- Play kit animation on spectate viewmodel
		if spectateController and spectateController.PlayKitAnimation then
			spectateController:PlayKitAnimation(info.track)
		end

		-- Resolve viewmodel and character for VFX
		local viewmodelRig = data.ViewModel
		local viewmodelModel = viewmodelRig and (viewmodelRig.Model or viewmodelRig)
		local character = data.Character

		-- Run the same VFX sub-modules with the spectate viewmodel
		if viewmodelModel and character then
			local clientModule = requireClient(data.Action)
			if clientModule then
				for _, event in ipairs(info.events) do
					task.delay(event.delay, function()
						local fn = clientModule[event.fn]
						if fn then
							pcall(fn, nil, { Character = character, ViewModel = viewmodelModel })
						end
					end)
				end
			end
		end

		-- Play the ability sound at the target character's root
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local sound = Instance.new("Sound")
			sound.SoundId = info.soundId
			sound.Volume = info.volume
			sound.RollOffMaxDistance = 100
			sound.Parent = root
			sound:Play()
			Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 0.5)
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
