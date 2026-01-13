local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))

local ViewmodelRig = {}
ViewmodelRig.__index = ViewmodelRig

local function ensureAnimationController(model: Model): (AnimationController, Animator)
	-- Prefer an existing AnimationController; otherwise create one.
	local animController = model:FindFirstChildOfClass("AnimationController")
	if not animController then
		animController = Instance.new("AnimationController")
		animController.Name = "AnimationController"
		animController.Parent = model
	end

	local animator = animController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animController
	end

	return animController, animator
end

local function stripHumanoid(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
end

local function findAnchorPart(model: Model): BasePart?
	-- Preferred contract: a Part named "Camera" (per your viewmodels).
	local cameraPart = model:FindFirstChild("Camera", true)
	if cameraPart and cameraPart:IsA("BasePart") then
		return cameraPart
	end

	-- Safe fallbacks (no breaking changes if models change later).
	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end

	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end

	return nil
end

function ViewmodelRig.new(model: Model, name: string)
	local self = setmetatable({}, ViewmodelRig)
	self.Name = name
	self.Model = model
	self.Animator = nil
	self.Anchor = nil
	self._destroyed = false
	self._cleanupFns = {}

	stripHumanoid(model)
	local _, animator = ensureAnimationController(model)
	self.Animator = animator
	self.Anchor = findAnchorPart(model)

	if not self.Anchor then
		LogService:Warn("VIEWMODEL", "Viewmodel missing anchor part (Camera/HumanoidRootPart/PrimaryPart)", {
			Name = name,
			Model = model:GetFullName(),
		})
	end

	-- Ensure PrimaryPart is set to something stable if possible.
	if not model.PrimaryPart then
		local hrp = model:FindFirstChild("HumanoidRootPart", true)
		if hrp and hrp:IsA("BasePart") then
			model.PrimaryPart = hrp
		elseif self.Anchor and self.Anchor:IsA("BasePart") then
			model.PrimaryPart = self.Anchor
		end
	end

	return self
end

function ViewmodelRig:AddCleanup(fn: (() -> ())?)
	if type(fn) == "function" then
		table.insert(self._cleanupFns, fn)
	end
end

function ViewmodelRig:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true

	for _, fn in ipairs(self._cleanupFns) do
		pcall(fn)
	end
	table.clear(self._cleanupFns)

	if self.Model then
		self.Model:Destroy()
	end
	self.Model = nil
	self.Animator = nil
	self.Anchor = nil
end

return ViewmodelRig

