local Special = {}

function Special.Execute(_weaponInstance, _isPressed)
	return false, "Disabled"
end

function Special.Cancel() end

function Special.IsActive()
	return false
end

return Special
