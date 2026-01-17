--!strict
-- WeldUtils.lua
-- Utility functions for creating and configuring welds
-- Reduces code duplication across CrouchUtils and NPCService

local WeldUtils = {}

--[[
	Creates a weld with specified configuration
	@param part0 - The first part (weld parent)
	@param part1 - The second part
	@param name - Name of the weld
	@param c0 - CFrame offset for Part0 (default CFrame.new())
	@param c1 - CFrame offset for Part1 (default CFrame.new())
	@return The created Weld instance
]]
function WeldUtils:CreateWeld(part0: BasePart, part1: BasePart, name: string, c0: CFrame?, c1: CFrame?): Weld
	local weld = Instance.new("Weld")
	weld.Name = name
	weld.Part0 = part0
	weld.Part1 = part1
	weld.C0 = c0 or CFrame.new()
	weld.C1 = c1 or CFrame.new()
	weld.Parent = part0
	return weld
end

--[[
	Creates a weld for bean-shaped character parts (used in custom character system)
	This is the common pattern used for body/head/face parts
	@param root - The root part (weld parent)
	@param part - The part to weld
	@param name - Name of the weld
	@param positionOffset - Optional position offset (default CFrame.new())
	@return The created Weld instance
]]
function WeldUtils:CreateBeanShapeWeld(root: BasePart, part: BasePart, name: string, positionOffset: CFrame?): Weld
	return self:CreateWeld(
		root,
		part,
		name,
		positionOffset or CFrame.new(),
		CFrame.Angles(0, 0, math.rad(90)) -- Standard 90-degree rotation for bean shape
	)
end

--[[
	Destroys a weld by name if it exists on the part
	@param part - The part to check
	@param weldName - Name of the weld to destroy
]]
function WeldUtils:DestroyWeld(part: BasePart, weldName: string)
	local weld = part:FindFirstChild(weldName)
	if weld and weld:IsA("Weld") then
		weld:Destroy()
	end
end

--[[
	Updates the C0/C1 offsets of an existing weld
	@param weld - The weld to update
	@param c0 - New C0 offset (optional)
	@param c1 - New C1 offset (optional)
]]
function WeldUtils:UpdateWeldOffsets(weld: Weld, c0: CFrame?, c1: CFrame?)
	if c0 then
		weld.C0 = c0
	end
	if c1 then
		weld.C1 = c1
	end
end

return WeldUtils
