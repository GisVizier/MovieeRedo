
local WhiteBeard = {}
WhiteBeard.__index = WhiteBeard

WhiteBeard.Ability = {}


function WhiteBeard.Ability:OnStart(abilityRequest)
	warn(abilityRequest)
	-- Example: compute aim and replicate immediately.
	-- Replace this with your client hitbox + only-send-on-hit logic.
	local hrp = abilityRequest.humanoidRootPart
	local origin = hrp and hrp.Position or nil

	
	abilityRequest.Send({
		origin = origin,
		
		-- direction = ...,
	})
end

function WhiteBeard.Ability:OnEnded(abilityRequest)
	-- If you do charge/hold, send final charge amount here.
	abilityRequest.Send()
end

function WhiteBeard.Ability:OnInterrupt(_abilityRequest, _reason)
	-- Cancel local prediction (hitboxes, anims, sounds).
end

WhiteBeard.Ultimate = {}

function WhiteBeard.Ultimate:OnStart(abilityRequest)
	abilityRequest.Send()
end

function WhiteBeard.Ultimate:OnEnded(abilityRequest)
	abilityRequest.Send()
end

function WhiteBeard.Ultimate:OnInterrupt(_abilityRequest, _reason) end

function WhiteBeard.new(ctx)
	local self = setmetatable({}, WhiteBeard)
	self._ctx = ctx
	self.Ability = WhiteBeard.Ability
	self.Ultimate = WhiteBeard.Ultimate
	return self
end

function WhiteBeard:Destroy() end

return WhiteBeard

