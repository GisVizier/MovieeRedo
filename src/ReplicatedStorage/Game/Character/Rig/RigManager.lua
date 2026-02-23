local RigManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local CollisionUtils = require(Locations.Shared.Util:WaitForChild("CollisionUtils"))

-- Lazy load RagdollModule to avoid circular dependency
local RagdollModule = nil
local function getRagdollModule()
	if not RagdollModule then
		local success, module = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Ragdoll"):WaitForChild("Ragdoll"))
		end)
		if success then
			RagdollModule = module
		end
	end
	return RagdollModule
end

RigManager.ActiveRigs = {}
RigManager.RigContainer = nil

RigManager._descendantConnections = {} -- [rig] = RBXScriptConnection

local function applyV1RigPartRules(rig, part)
	if not part:IsA("BasePart") then
		return
	end

	-- v1 rules: rig is cosmetic; never collide/query/touch; always massless.
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false

	-- v1 critical rule: anchor the rig HRP to prevent falling/jitter.
	if part.Name == "HumanoidRootPart" and part.Parent == rig then
		part.Anchored = true
	end
end

local function configureRigDefault(rig)
	for _, part in ipairs(rig:GetDescendants()) do
		applyV1RigPartRules(rig, part)
	end
end

function RigManager:_bindRigDescendantAdded(rig)
	if self._descendantConnections[rig] then
		return
	end

	self._descendantConnections[rig] = rig.DescendantAdded:Connect(function(descendant)
		applyV1RigPartRules(rig, descendant)
	end)

	-- Cleanup connection when rig is destroyed.
	rig.Destroying:Connect(function()
		local conn = self._descendantConnections[rig]
		if conn then
			conn:Disconnect()
			self._descendantConnections[rig] = nil
		end
		-- Stop the ensure loop
		CollisionUtils:StopEnsuringNonCollideable(rig)
	end)
end

function RigManager:Init()
	if self.RigContainer then
		return
	end

	local container = Workspace:FindFirstChild("Rigs")
	if not container then
		container = Instance.new("Folder")
		container.Name = "Rigs"
		container.Parent = Workspace
	end

	self.RigContainer = container
end

function RigManager:GetRigContainer()
	if not self.RigContainer then
		self:Init()
	end
	return self.RigContainer
end

function RigManager:CreateRig(player, character)
	if not Config.Gameplay.Character.EnableRig then
		return nil
	end

	self:Init()

	local template = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not template then
		return nil
	end

	local templateRig = template:FindFirstChild("Rig")
	if not templateRig then
		return nil
	end

	local rig = templateRig:Clone()
	rig.Name = player.Name .. "_Rig"
	rig:SetAttribute("OwnerUserId", player.UserId)
	rig:SetAttribute("OwnerName", player.Name)
	rig:SetAttribute("IsActive", true)
	rig.Parent = self:GetRigContainer()

	configureRigDefault(rig)
	self:_bindRigDescendantAdded(rig)
	self.ActiveRigs[player] = rig
	
	-- BULLETPROOF: Use CollisionUtils to ensure rig NEVER has collision enabled.
	-- This runs a heartbeat loop that re-applies every 0.25s, catching any changes
	-- from ApplyDescription or other sources that might reset collision properties.
	CollisionUtils:EnsureNonCollideable(rig, {
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		UseHeartbeat = true,
		HeartbeatInterval = 0.25, -- Check 4 times per second
	})

	-- Apply player appearance to the rig (v1 behavior via HumanoidDescription).
	-- This is done async because GetHumanoidDescriptionFromUserId can yield.
	do
		local rigHumanoid = rig:FindFirstChildOfClass("Humanoid")
		if rigHumanoid and player and player.UserId and player.UserId > 0 then
			-- Ensure Animator exists (helps animation replication consistency)
			if not rigHumanoid:FindFirstChildOfClass("Animator") then
				local animator = Instance.new("Animator")
				animator.Parent = rigHumanoid
			end

			task.spawn(function()
				local ok, desc = pcall(function()
					return Players:GetHumanoidDescriptionFromUserId(player.UserId)
				end)

				if ok and desc and rigHumanoid.Parent then
					pcall(function()
						rigHumanoid:ApplyDescription(desc)
					end)
					-- Re-apply collision rules immediately after ApplyDescription
					configureRigDefault(rig)

					-- Signal that ApplyDescription finished. Other systems (e.g.
					-- AnimationController) listen for this to re-acquire the Animator
					-- and reload animation tracks, because ApplyDescription can
					-- destroy/recreate the Animator and invalidate all AnimationTracks.
					rig:SetAttribute("DescriptionApplied", tick())
				end
			end)
		end
	end

	-- Setup ragdoll system for this rig (client-only)
	if RunService:IsClient() then
		local ragdoll = getRagdollModule()
		if ragdoll and ragdoll.SetupRig then
			ragdoll.SetupRig(player, rig, character)
		end
	end

	return rig
end

function RigManager:GetActiveRig(player)
	local cached = self.ActiveRigs[player]
	if cached and cached.Parent then
		return cached
	end

	-- Rig is created server-side and replicates to clients. Look it up by attribute
	-- in the Rigs container so the client can find it without calling CreateRig.
	local container = self:GetRigContainer()
	if container and player then
		for _, child in ipairs(container:GetChildren()) do
			if child:GetAttribute("OwnerUserId") == player.UserId and child:GetAttribute("IsActive") == true then
				self.ActiveRigs[player] = child
				return child
			end
		end
	end

	return nil
end

function RigManager:GetRigForCharacter(character)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		return self.ActiveRigs[player]
	end

	local name = character.Name
	for _, rig in ipairs(self:GetRigContainer():GetChildren()) do
		if rig:GetAttribute("OwnerName") == name and rig:GetAttribute("IsActive") then
			return rig
		end
	end

	return nil
end

function RigManager:MarkRigAsDead(rig)
	if not rig then
		return
	end

	rig:SetAttribute("IsActive", false)
	rig:SetAttribute("IsDead", true)

	local ownerName = rig:GetAttribute("OwnerName") or "Unknown"
	rig.Name = ownerName .. "_Rig_Dead_" .. tostring(math.floor(tick()))

	for player, activeRig in pairs(self.ActiveRigs) do
		if activeRig == rig then
			self.ActiveRigs[player] = nil
			break
		end
	end
end

function RigManager:DestroyRig(rig)
	if rig then
		-- Cleanup ragdoll data (client-only)
		if RunService:IsClient() then
			local ragdoll = getRagdollModule()
			if ragdoll and ragdoll.CleanupRig then
				ragdoll.CleanupRig(rig)
			end
		end
		
		if rig.Parent then
			rig:Destroy()
		end
	end
end

return RigManager
