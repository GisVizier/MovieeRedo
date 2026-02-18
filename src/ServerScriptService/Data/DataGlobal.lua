--[[
	Shared utilities for the Data module.
]]

local DataGlobal = {}

local activeReplicaTable = {}

function DataGlobal.GetReplicaTable()
	return activeReplicaTable
end

function DataGlobal.FillTable(target: { [string]: any }, template: { [string]: any }): { [string]: any }
	for key, templateValue in template do
		local targetValue = target[key]
		if targetValue == nil then
			target[key] = (typeof(templateValue) == "table" and not templateValue.ClassName)
					and DataGlobal.FillTable({}, templateValue)
				or templateValue
		elseif typeof(targetValue) == "table" and typeof(templateValue) == "table" and not templateValue.ClassName then
			DataGlobal.FillTable(targetValue, templateValue)
		end
	end
	return target
end

function DataGlobal.osTime(utc: boolean?): number
	if utc then
		return os.time(os.date("!*t"))
	end
	return os.time()
end

return DataGlobal
