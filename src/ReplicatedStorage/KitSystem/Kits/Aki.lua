--[[
	Aki Server Kit
	Minimal server-side implementation for ability/ultimate activation.
]]

local Kit = {}
Kit.__index = Kit

function Kit.new(ctx)
	local self = setmetatable({}, Kit)
	self._ctx = ctx
	return self
end

function Kit:SetCharacter(character)
	self._ctx.character = character
end

function Kit:Destroy()
end

function Kit:OnEquipped()
end

function Kit:OnUnequipped()
end

function Kit:OnAbility(inputState, _clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end

	local player = self._ctx.player
	local service = self._ctx.service
	if player and service then
		service:StartCooldown(player)
	end

	return true
end

function Kit:OnUltimate(inputState, _clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end

	return true
end

return Kit
