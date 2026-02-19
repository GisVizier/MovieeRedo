local function resolveShotgunModule()
	local parent = script.Parent
	if parent then
		local direct = parent:FindFirstChild("Shotgun")
		if direct then
			return direct
		end
	end

	local grandParent = parent and parent.Parent
	if grandParent then
		local fromGrandParent = grandParent:FindFirstChild("Shotgun")
		if fromGrandParent then
			return fromGrandParent
		end
	end

	error("[Shorty] Could not resolve Shotgun module: " .. script:GetFullName())
end

return require(resolveShotgunModule())
