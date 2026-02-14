local State = {}

local modeBySlot = {}

function State.GetMode(slot)
	if type(slot) ~= "string" or slot == "" then
		return "burst"
	end
	return modeBySlot[slot] or "burst"
end

function State.SetMode(slot, mode)
	if type(slot) ~= "string" or slot == "" then
		return
	end
	if mode ~= "semi" and mode ~= "burst" then
		return
	end
	modeBySlot[slot] = mode
end

return State
