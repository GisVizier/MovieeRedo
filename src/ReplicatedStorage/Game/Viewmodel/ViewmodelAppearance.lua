local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ViewmodelAppearance = {}

-- Maps body color properties to viewmodel part names
local LEFT_ARM_PARTS = {
	["Left Arm"] = true,
	["LeftUpperArm"] = true,
	["LeftLowerArm"] = true,
	["LeftHand"] = true,
}

local RIGHT_ARM_PARTS = {
	["Right Arm"] = true,
	["RightUpperArm"] = true,
	["RightLowerArm"] = true,
	["RightHand"] = true,
}

local function applyBodyColorsToViewmodel(viewmodel, bodyColors)
	if not bodyColors or not bodyColors:IsA("BodyColors") then
		return
	end

	local leftColor = bodyColors.LeftArmColor3
	local rightColor = bodyColors.RightArmColor3

	for _, desc in ipairs(viewmodel:GetDescendants()) do
		if desc:IsA("BasePart") then
			if LEFT_ARM_PARTS[desc.Name] then
				desc.Color = leftColor
			elseif RIGHT_ARM_PARTS[desc.Name] then
				desc.Color = rightColor
			end
		end
	end
end

local function tryApplyBodyColors(viewmodel, rig)
	local bodyColors = rig:FindFirstChildOfClass("BodyColors")
	if not bodyColors then
		return false
	end

	applyBodyColorsToViewmodel(viewmodel, bodyColors)
	return true
end

local function applyShirtTemplateToViewmodel(viewmodel: Model, shirtTemplate: string)
	if type(shirtTemplate) ~= "string" or shirtTemplate == "" then
		return
	end

	local fake = viewmodel:FindFirstChild("Fake", true)
	if not fake then
		return
	end

	for _, d in ipairs(fake:GetDescendants()) do
		if d:IsA("Decal") and d.Name == "ShirtTexture" then
			d.Texture = shirtTemplate
		end
	end
end

local function tryApplyFromRig(viewmodel: Model, rig: Model): boolean
	local shirt = rig:FindFirstChildOfClass("Shirt")
	if not shirt then
		return false
	end

	applyShirtTemplateToViewmodel(viewmodel, shirt.ShirtTemplate)
	return true
end

-- No fallback by design: only read from the workspace cosmetic rig.
-- Returns a cleanup function (disconnects listeners).
function ViewmodelAppearance.BindShirtToLocalRig(player, viewmodel)
	local connections = {}

	local function cleanup()
		for _, c in ipairs(connections) do
			pcall(function()
				c:Disconnect()
			end)
		end
		table.clear(connections)
	end

	if not player or not viewmodel then
		return cleanup
	end

	-- Rig location: workspace.Rigs/<PlayerName>_Rig
	local rigsFolder = Workspace:FindFirstChild("Rigs")
	if not rigsFolder then
		rigsFolder = Workspace:WaitForChild("Rigs", 5)
	end
	if not rigsFolder then
		return cleanup
	end

	local rigName = player.Name .. "_Rig"

	local function bindRig(rig)
		-- Apply shirt
		if not tryApplyFromRig(viewmodel, rig) then
			table.insert(connections, rig.ChildAdded:Connect(function(child)
				if child:IsA("Shirt") then
					tryApplyFromRig(viewmodel, rig)
				end
			end))
		end

		-- Apply body colors (skin color to arms)
		if not tryApplyBodyColors(viewmodel, rig) then
			table.insert(connections, rig.ChildAdded:Connect(function(child)
				if child:IsA("BodyColors") then
					tryApplyBodyColors(viewmodel, rig)
				end
			end))
		end
	end

	local existing = rigsFolder:FindFirstChild(rigName)
	if existing and existing:IsA("Model") then
		bindRig(existing)
		return cleanup
	end

	-- Wait for rig to be created.
	table.insert(connections, rigsFolder.ChildAdded:Connect(function(child)
		if child.Name == rigName and child:IsA("Model") then
			bindRig(child)
		end
	end))

	return cleanup
end

return ViewmodelAppearance

