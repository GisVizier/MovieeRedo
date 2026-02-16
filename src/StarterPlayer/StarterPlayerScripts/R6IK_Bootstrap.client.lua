--[[
	R6IK Bootstrap — Minimal drag-and-drop integration
	==================================================

	REQUIREMENTS:
	  1. R6IKSolver module in ReplicatedStorage
	  2. Avatar RigType = R6 (StarterPlayer > Character)

	TARGETS:
	  Arms drive toward Solver attachment positions (Left Arm.Solver, Right Arm.Solver)
	  on a child model (e.g. Shorty_Default). If no Solver attachments found, falls
	  back to mouse position.

	USAGE:
	  - Copy this script into StarterPlayer > StarterPlayerScripts
	  - Copy R6IKSolver.luau into ReplicatedStorage
	  - Set RigType to R6
	  - Attach a model with Left Arm/Right Arm, each with a "Solver" Attachment
]]

--[[ R6IK DISABLED - remove this block comment to re-enable
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local R6IKSolver = require(ReplicatedStorage:WaitForChild("R6IKSolver"))

local player = Players.LocalPlayer
local ik = nil
local overlayModel = nil  -- model with Solver attachments (e.g. Shorty clone)

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Torso")
	character:WaitForChild("HumanoidRootPart")
	overlayModel = nil

	if character:FindFirstChildOfClass("Humanoid").RigType ~= Enum.HumanoidRigType.R6 then
		warn("[R6IK] Not R6 — skipping IK setup")
		return
	end

	-- Find overlay model with Solver attachments
	for _, child in character:GetChildren() do
		if child:IsA("Model") then
			local rArm = child:FindFirstChild("Right Arm")
			local lArm = child:FindFirstChild("Left Arm")
			if (rArm and rArm:FindFirstChild("Solver")) and (lArm and lArm:FindFirstChild("Solver")) then
				overlayModel = child
				break
			end
		end
	end

	ik = R6IKSolver.new(character, {
		smoothing = 0.4,
		overrideAnimation = true,
	})
	ik:setEnabled("RightArm", true)
	ik:setEnabled("LeftArm", true)
end)

player.CharacterRemoving:Connect(function()
	if ik then
		ik:destroy()
		ik = nil
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not ik then return end
	local char = player.Character
	if not char then return end

	local torso = char:FindFirstChild("Torso")
	if not torso then return end

	-- Re-detect overlay if not found or destroyed
	if not overlayModel or overlayModel.Parent ~= char then
		overlayModel = nil
		for _, child in char:GetChildren() do
			if child:IsA("Model") then
				local rArm, lArm = child:FindFirstChild("Right Arm"), child:FindFirstChild("Left Arm")
				if (rArm and rArm:FindFirstChild("Solver")) and (lArm and lArm:FindFirstChild("Solver")) then
					overlayModel = child
					break
				end
			end
		end
	end

	-- Get targets from Solver attachments (Left Arm.Solver, Right Arm.Solver)
	local rightTarget, leftTarget
	if overlayModel then
		local rArm = overlayModel:FindFirstChild("Right Arm")
		local lArm = overlayModel:FindFirstChild("Left Arm")
		local rSolver = rArm and rArm:FindFirstChild("Solver")
		local lSolver = lArm and lArm:FindFirstChild("Solver")
		if rSolver and rSolver:IsA("Attachment") then rightTarget = rSolver.WorldPosition end
		if lSolver and lSolver:IsA("Attachment") then leftTarget = lSolver.WorldPosition end
	end

	-- Fallback: mouse position (when no overlay with Solver)
	if not rightTarget and not leftTarget then
		local mouse = player:GetMouse()
		local ray = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { char }
		params.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
		local target = result and result.Position or (ray.Origin + ray.Direction * 10)
		rightTarget = target
		leftTarget = target
	end

	local pole = torso.Position + torso.CFrame.LookVector * -2 + Vector3.new(0, -1, 0)
	if rightTarget then ik:setArmTarget("Right", rightTarget, pole) end
	if leftTarget then ik:setArmTarget("Left", leftTarget, pole) end
	ik:update(dt)

	-- Zero overlay arm animations when IK is solving (legs stay animated)
	if (rightTarget or leftTarget) and overlayModel then
		local hrp = overlayModel:FindFirstChild("HumanoidRootPart")
		if hrp then
			local lm, rm = hrp:FindFirstChild("Left Arm"), hrp:FindFirstChild("Right Arm")
			if lm and lm:IsA("Motor6D") then lm.Transform = CFrame.new() end
			if rm and rm:IsA("Motor6D") then rm.Transform = CFrame.new() end
		end
	end
end)
--]]
