--[[
	Aki Client Kit
	Minimal client-side handlers to forward ability/ultimate requests.
]]

local Aki = {}
Aki.__index = Aki

Aki.Ability = {}
Aki.Ultimate = {}

function Aki.Ability:OnStart(abilityRequest)
	abilityRequest.Send()
end

function Aki.Ability:OnEnded(_abilityRequest)
end

function Aki.Ability:OnInterrupt(_abilityRequest, _reason)
end

function Aki.Ultimate:OnStart(abilityRequest)
	abilityRequest.Send()
end

function Aki.Ultimate:OnEnded(_abilityRequest)
end

function Aki.Ultimate:OnInterrupt(_abilityRequest, _reason)
end

function Aki.new(ctx)
	local self = setmetatable({}, Aki)
	self._ctx = ctx
	self.Ability = Aki.Ability
	self.Ultimate = Aki.Ultimate
	return self
end

function Aki:Destroy()
end

return Aki
