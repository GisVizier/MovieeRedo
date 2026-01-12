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

function Kit:OnAbility(_inputState, _clientData)
	return true
end

function Kit:OnUltimate(_inputState, _clientData)
	return true
end

return Kit
