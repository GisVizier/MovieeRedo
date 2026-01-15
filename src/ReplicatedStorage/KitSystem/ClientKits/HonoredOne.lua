-- Client-only kit input handlers for Honored One.
local HonoredOne = {}
HonoredOne.__index = HonoredOne

HonoredOne.Ability = {}

function HonoredOne.Ability:OnStart(abilityRequest)
	abilityRequest.Send()
end

function HonoredOne.Ability:OnEnded(abilityRequest)
	abilityRequest.Send()
end

function HonoredOne.Ability:OnInterrupt(_abilityRequest, _reason)
end

HonoredOne.Ultimate = {}

function HonoredOne.Ultimate:OnStart(abilityRequest)
	abilityRequest.Send()
end

function HonoredOne.Ultimate:OnEnded(abilityRequest)
	abilityRequest.Send()
end

function HonoredOne.Ultimate:OnInterrupt(_abilityRequest, _reason)
end

function HonoredOne.new(ctx)
	local self = setmetatable({}, HonoredOne)
	self._ctx = ctx
	self.Ability = HonoredOne.Ability
	self.Ultimate = HonoredOne.Ultimate
	return self
end

function HonoredOne:Destroy() end

return HonoredOne
