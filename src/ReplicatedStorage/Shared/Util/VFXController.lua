local VFXController = {}

VFXController._active = {}

function VFXController:PlayVFXReplicated(_name, _position)
	-- No-op stub for v2
end

function VFXController:StartContinuousVFXReplicated(name, _part)
	self._active[name] = true
end

function VFXController:UpdateContinuousVFXOrientation(_name, _direction, _part)
	-- No-op stub for v2
end

function VFXController:StopContinuousVFX(name)
	self._active[name] = nil
end

function VFXController:IsContinuousVFXActive(name)
	return self._active[name] ~= nil
end

return VFXController
