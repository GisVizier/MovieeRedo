local Airborne = {}
Airborne.__index = Airborne

Airborne.Ability = {}

function Airborne.Ability:OnStart(abilityRequest)
	abilityRequest.Send()
end

function Airborne.Ability:OnEnded(abilityRequest)
	abilityRequest.Send()
end

function Airborne.Ability:OnInterrupt(_abilityRequest, _reason)
	-- Cancel local-only effects here if needed.
end

Airborne.Ultimate = {}

function Airborne.Ultimate:OnStart(abilityRequest)
	abilityRequest.Send()
end

function Airborne.Ultimate:OnEnded(abilityRequest)
	abilityRequest.Send()
end

function Airborne.Ultimate:OnInterrupt(_abilityRequest, _reason)
	-- Cancel local-only effects here if needed.
end

function Airborne.new(ctx)
	local self = setmetatable({}, Airborne)
	self._ctx = ctx
	self.Ability = Airborne.Ability
	self.Ultimate = Airborne.Ultimate
	return self
end

function Airborne:Destroy() end

return Airborne
