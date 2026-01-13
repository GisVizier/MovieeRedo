-- Client-only kit input template.
-- This runs on the local client and is responsible for:
-- - local prediction (animations, sounds, UI)
-- - client-owned hitboxes
-- - deciding when/if to replicate to server via abilityRequest.Send(extraData)

local Template = {}
Template.__index = Template

Template.Ability = {}

function Template.Ability:OnStart(abilityRequest)
	-- Default behavior: replicate immediately.
	abilityRequest.Send()
end

function Template.Ability:OnEnded(abilityRequest)
	abilityRequest.Send()
end

function Template.Ability:OnInterrupt(_abilityRequest, _reason)
	-- Cancel local-only effects here if needed.
end

Template.Ultimate = {}

function Template.Ultimate:OnStart(abilityRequest)
	abilityRequest.Send()
end

function Template.Ultimate:OnEnded(abilityRequest)
	abilityRequest.Send()
end

function Template.Ultimate:OnInterrupt(_abilityRequest, _reason)
	-- Cancel local-only effects here if needed.
end

function Template.new(ctx)
	local self = setmetatable({}, Template)
	self._ctx = ctx
	self.Ability = Template.Ability
	self.Ultimate = Template.Ultimate

	return self
end

function Template:Destroy() end

return Template

