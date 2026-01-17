local ViewmodelAppearance = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)

function ViewmodelAppearance:Init()
	Log:Debug("VIEWMODEL", "ViewmodelAppearance initialized")
end

function ViewmodelAppearance:GetPlayerRig(player)
	local rigsFolder = Workspace:FindFirstChild("Rigs")
	if not rigsFolder then
		print("[APPEARANCE] No Rigs folder in Workspace")
		return nil
	end
	
	local rigName = player.Name .. "_Rig"
	local rig = rigsFolder:FindFirstChild(rigName)
	
	if rig then
		print("[APPEARANCE] Found rig:", rigName)
		return rig
	end
	
	print("[APPEARANCE] Rig not found:", rigName)
	return nil
end

function ViewmodelAppearance:ApplyPlayerAppearance(viewmodel, player)
	if not viewmodel or not player then
		return
	end

	task.spawn(function()
		self:ApplySkinColor(viewmodel, player)
		self:ApplyShirtTexture(viewmodel, player)
	end)
end

function ViewmodelAppearance:ApplySkinColor(viewmodel, player)
	local skinColor = nil
	
	local rig = self:GetPlayerRig(player)
	if rig then
		local bodyColors = rig:FindFirstChildOfClass("BodyColors")
		if bodyColors then
			skinColor = bodyColors.LeftArmColor3
			print("[SKIN] Got from rig BodyColors:", tostring(skinColor))
		else
			local leftArm = rig:FindFirstChild("Left Arm")
			if leftArm and leftArm:IsA("BasePart") then
				skinColor = leftArm.Color
				print("[SKIN] Got from rig Left Arm:", tostring(skinColor))
			end
		end
	end

	if not skinColor then
		local success, description = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(player.UserId)
		end)
		if success and description then
			skinColor = description.LeftArmColor
			print("[SKIN] Got from HumanoidDescription:", tostring(skinColor))
		end
	end

	if not skinColor then
		skinColor = Color3.fromRGB(255, 204, 153)
		print("[SKIN] Using fallback")
	end

	local partsColored = 0
	for _, descendant in ipairs(viewmodel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local shouldSkip = false
			local current = descendant
			while current and current ~= viewmodel do
				if current:GetAttribute("skipColor") then
					shouldSkip = true
					break
				end
				current = current.Parent
			end
			
			if not shouldSkip then
				descendant.Color = skinColor
				partsColored = partsColored + 1
			end
		end
	end

	print("[SKIN] Colored", partsColored, "parts")
end

function ViewmodelAppearance:ApplyShirtTexture(viewmodel, player)
	local shirtTemplate = nil
	
	local rig = self:GetPlayerRig(player)
	if rig then
		local shirt = rig:FindFirstChildOfClass("Shirt")
		if shirt then
			shirtTemplate = shirt.ShirtTemplate
			print("[SHIRT] Got from rig Shirt:", shirtTemplate)
		else
			print("[SHIRT] No Shirt on rig - children:")
			for _, child in ipairs(rig:GetChildren()) do
				print("  -", child.Name, child.ClassName)
			end
		end
	end

	if not shirtTemplate or shirtTemplate == "" then
		print("[SHIRT] No shirt template found")
		return
	end

	local fakeModel = viewmodel:FindFirstChild("Fake")
	if not fakeModel then
		print("[SHIRT] No Fake folder in viewmodel")
		return
	end

	local texturesApplied = 0

	local leftArmModel = fakeModel:FindFirstChild("LeftArm")
	if leftArmModel then
		local shirtDecal = leftArmModel:FindFirstChild("ShirtTexture")
		if shirtDecal then
			shirtDecal.Texture = shirtTemplate
			texturesApplied = texturesApplied + 1
			print("[SHIRT] Applied to LeftArm")
		end
	end

	local rightArmModel = fakeModel:FindFirstChild("RightArm")
	if rightArmModel then
		local shirtDecal = rightArmModel:FindFirstChild("ShirtTexture")
		if shirtDecal then
			shirtDecal.Texture = shirtTemplate
			texturesApplied = texturesApplied + 1
			print("[SHIRT] Applied to RightArm")
		end
	end

	print("[SHIRT] Applied to", texturesApplied, "decals")
end

return ViewmodelAppearance
