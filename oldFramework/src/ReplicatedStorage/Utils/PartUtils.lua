--!strict
-- PartUtils.lua
-- Utility functions for common part property manipulations
-- Reduces code duplication across CharacterService, CrouchUtils, NPCService, etc.

local PartUtils = {}

--[[
	Makes a part invisible and non-interactive (common pattern for collision/placeholder parts)
	@param part - The part to make invisible
	@param options - Optional table with:
		- Massless: boolean (default true)
		- CanCollide: boolean (default false)
		- CanQuery: boolean (default false)
		- CanTouch: boolean (default false)
]]
function PartUtils:MakePartInvisible(
	part: BasePart,
	options: {
		Massless: boolean?,
		CanCollide: boolean?,
		CanQuery: boolean?,
		CanTouch: boolean?,
	}?
)
	options = options or {}

	part.Transparency = 1
	part.CanCollide = if options.CanCollide ~= nil then options.CanCollide else false
	part.CanQuery = if options.CanQuery ~= nil then options.CanQuery else false
	part.CanTouch = if options.CanTouch ~= nil then options.CanTouch else false

	if options.Massless ~= false then -- Default true unless explicitly set to false
		part.Massless = true
	end
end

--[[
	Makes a part visible and interactive
	@param part - The part to make visible
	@param options - Optional table with:
		- Transparency: number (default 0)
		- CanCollide: boolean (default true)
		- CanQuery: boolean (default true)
		- CanTouch: boolean (default false)
]]
function PartUtils:MakePartVisible(
	part: BasePart,
	options: {
		Transparency: number?,
		CanCollide: boolean?,
		CanQuery: boolean?,
		CanTouch: boolean?,
	}?
)
	options = options or {}

	part.Transparency = options.Transparency or 0
	part.CanCollide = if options.CanCollide ~= nil then options.CanCollide else true
	part.CanQuery = if options.CanQuery ~= nil then options.CanQuery else true
	part.CanTouch = if options.CanTouch ~= nil then options.CanTouch else false
end

--[[
	Configures multiple properties on a part at once
	@param part - The part to configure
	@param properties - Table of property names and values
]]
function PartUtils:ConfigureProperties(part: BasePart, properties: { [string]: any })
	for propertyName, propertyValue in pairs(properties) do
		(part :: any)[propertyName] = propertyValue
	end
end

--[[
	Recursively sets properties on all BaseParts in a model
	@param model - The model to process
	@param properties - Table of property names and values
]]
function PartUtils:SetPropertiesRecursive(model: Model, properties: { [string]: any })
	for _, descendant in pairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			self:ConfigureProperties(descendant, properties)
		end
	end
end

return PartUtils
