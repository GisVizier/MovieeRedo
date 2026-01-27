local HttpService = game:GetService("HttpService")

local GadgetUtils = {}

function GadgetUtils:findGadgetsFolder(mapInstance)
	if not mapInstance or not mapInstance.Parent then
		return nil
	end
	return mapInstance:FindFirstChild("Gadgets")
end

function GadgetUtils:getGadgetType(model, defaultType)
	if not model then
		return nil
	end
	local attr = model:GetAttribute("GadgetType")
	if type(attr) == "string" and attr ~= "" then
		return attr
	end
	return defaultType
end

function GadgetUtils:getOrCreateId(model)
	if not model then
		return nil
	end
	local id = model:GetAttribute("GadgetId")
	if type(id) ~= "string" or id == "" then
		id = HttpService:GenerateGUID(false)
		model:SetAttribute("GadgetId", id)
	end
	return id
end

function GadgetUtils:listGadgetModels(mapInstance)
	local gadgetsFolder = self:findGadgetsFolder(mapInstance)
	if not gadgetsFolder then
		return {}
	end

	local results = {}
	for _, typeFolder in ipairs(gadgetsFolder:GetChildren()) do
		if typeFolder:IsA("Folder") then
			local typeName = typeFolder.Name
			for _, model in ipairs(typeFolder:GetChildren()) do
				if model:IsA("Model") then
					local gadgetType = self:getGadgetType(model, typeName)
					if gadgetType == typeName then
						table.insert(results, {
							typeName = typeName,
							model = model,
						})
					end
				end
			end
		end
	end

	return results
end

return GadgetUtils
