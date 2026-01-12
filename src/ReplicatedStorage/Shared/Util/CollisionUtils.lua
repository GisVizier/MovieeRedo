local CollisionUtils = {}

function CollisionUtils:CreateExclusionOverlapParams(excludedInstances, options)
	options = options or {}

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludedInstances
	params.RespectCanCollide = options.RespectCanCollide ~= nil and options.RespectCanCollide or true
	params.MaxParts = options.MaxParts or 20

	if options.CollisionGroup then
		params.CollisionGroup = options.CollisionGroup
	end

	return params
end

return CollisionUtils
