local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ViewmodelAppearance = {}

local function isLeftPart(name)
	local lower = string.lower(name)
	return string.find(lower, "left", 1, true) ~= nil
end

local function isRightPart(name)
	local lower = string.lower(name)
	return string.find(lower, "right", 1, true) ~= nil
end

local function findBodyColors(rig)
	-- Check direct children first
	local bc = rig:FindFirstChildOfClass("BodyColors")
	if bc then
		return bc
	end
	-- Search recursively
	for _, desc in ipairs(rig:GetDescendants()) do
		if desc:IsA("BodyColors") then
			return desc
		end
	end
	return nil
end

local function colorDescendants(instance, color)
	for _, desc in ipairs(instance:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Color = color
		end
	end
end

local function applyBodyColorsToViewmodel(viewmodel, bodyColors)
	if not bodyColors or not bodyColors:IsA("BodyColors") then
		return
	end

	local leftColor = bodyColors.LeftArmColor3
	local rightColor = bodyColors.RightArmColor3

	for _, child in ipairs(viewmodel:GetDescendants()) do
		if child:IsA("BasePart") or child:IsA("Folder") or child:IsA("Model") then
			if isLeftPart(child.Name) then
				if child:IsA("BasePart") then
					child.Color = leftColor
				end
				colorDescendants(child, leftColor)
			elseif isRightPart(child.Name) then
				if child:IsA("BasePart") then
					child.Color = rightColor
				end
				colorDescendants(child, rightColor)
			end
		end
	end
end

local function tryApplyBodyColors(viewmodel, rig)
	local bodyColors = findBodyColors(rig)
	if not bodyColors then
		return false
	end

	applyBodyColorsToViewmodel(viewmodel, bodyColors)
	return true
end

local function applyShirtTemplateToViewmodel(viewmodel, shirtTemplate)
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

local function tryApplyFromRig(viewmodel, rig)
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

