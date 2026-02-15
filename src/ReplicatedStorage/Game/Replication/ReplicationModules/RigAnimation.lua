--[[
	RigAnimation VFXRep stub.
	Server requires this to exist so it relays events to clients.
	All real logic lives in AnimationController (registered as VFXRep.Modules["RigAnimation"]).
]]
return {
	Play = function() end,
	Stop = function() end,
	StopAll = function() end,
}
