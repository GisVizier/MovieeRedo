local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ViewmodelAppearance = {}

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
function ViewmodelAppearance.BindShirtToLocalRig(player: Player, viewmodel: Model): () -> ()
	local connections: { RBXScriptConnection } = {}

	local function cleanup()
		for _, c in ipairs(connections) do
			pcall(function()
				c:Disconnect()
			end)
		end
		table.clear(connections)
	end

	if not player or not viewmodel or not viewmodel.Parent then
		-- Viewmodel not parented yet is fine; we can still bind.
	end

	-- Rig location: workspace.Rigs/<PlayerName>_Rig
	local rigsFolder = Workspace:FindFirstChild("Rigs")
	if not rigsFolder then
		-- RigManager should create it, but don't yield forever.
		rigsFolder = Workspace:WaitForChild("Rigs", 5)
	end
	if not rigsFolder then
		return cleanup
	end

	local rigName = player.Name .. "_Rig"

	local function bindRig(rig: Model)
		-- Try immediately; if shirt isn't present yet, wait for it.
		if tryApplyFromRig(viewmodel, rig) then
			return
		end

		table.insert(connections, rig.ChildAdded:Connect(function(child)
			if child:IsA("Shirt") then
				tryApplyFromRig(viewmodel, rig)
			end
		end))
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

