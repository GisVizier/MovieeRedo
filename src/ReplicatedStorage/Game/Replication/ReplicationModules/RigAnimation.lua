--[[
	DEPRECATED: RigAnimation VFXRep module is no longer used.

	Rig animations are now played server-side via RigAnimationService.
	The server owns the rig Animator and Roblox replicates animations
	to all clients automatically. Client sends requests via the reliable
	"RigAnimationRequest" remote instead of unreliable VFXRep.

	This stub is kept so the VFXRep server relay doesn't error if any
	old code path still references the module name.
]]
return {
	Play = function() end,
	Stop = function() end,
	StopAll = function() end,
}
