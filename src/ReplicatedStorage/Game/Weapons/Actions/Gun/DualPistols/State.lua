local State = {}

local stateBySlot = {}

local function getSideCapacity(clipSize)
	local resolved = math.floor(tonumber(clipSize) or 16)
	return math.max(math.floor(resolved / 2), 1)
end

local function clampAmmo(value, maxAmmo)
	local resolved = math.floor(tonumber(value) or 0)
	return math.clamp(resolved, 0, math.max(math.floor(tonumber(maxAmmo) or 0), 0))
end

local function getSlotState(slot)
	if type(slot) ~= "string" or slot == "" then
		return nil
	end

	local entry = stateBySlot[slot]
	if not entry then
		entry = {
			mode = "burst",
			gunAmmo = {
				right = 0,
				left = 0,
			},
			ads = {
				active = false,
				side = "right",
				lastSide = nil,
			},
		}
		stateBySlot[slot] = entry
	end

	return entry
end

local function getOtherSide(side)
	return (side == "left") and "right" or "left"
end

local function resolveSide(side)
	return (side == "left") and "left" or "right"
end

local function sumGunAmmo(entry)
	return (entry.gunAmmo.right or 0) + (entry.gunAmmo.left or 0)
end

local function normalizeTotal(totalAmmo, clipSize)
	local sideCapacity = getSideCapacity(clipSize)
	local clipCapacity = sideCapacity * 2
	local resolved = math.floor(tonumber(totalAmmo) or 0)
	return math.clamp(resolved, 0, clipCapacity)
end

local function syncToTotal(entry, totalAmmo, clipSize)
	local sideCapacity = getSideCapacity(clipSize)
	local targetTotal = normalizeTotal(totalAmmo, clipSize)

	entry.gunAmmo.right = clampAmmo(entry.gunAmmo.right, sideCapacity)
	entry.gunAmmo.left = clampAmmo(entry.gunAmmo.left, sideCapacity)

	local runningTotal = sumGunAmmo(entry)
	if runningTotal > targetTotal then
		local excess = runningTotal - targetTotal

		local drainLeft = math.min(entry.gunAmmo.left, excess)
		entry.gunAmmo.left -= drainLeft
		excess -= drainLeft

		if excess > 0 then
			local drainRight = math.min(entry.gunAmmo.right, excess)
			entry.gunAmmo.right -= drainRight
		end
	elseif runningTotal < targetTotal then
		local needed = targetTotal - runningTotal

		local addRight = math.min(sideCapacity - entry.gunAmmo.right, needed)
		entry.gunAmmo.right += addRight
		needed -= addRight

		if needed > 0 then
			local addLeft = math.min(sideCapacity - entry.gunAmmo.left, needed)
			entry.gunAmmo.left += addLeft
		end
	end
end

function State.GetMode(slot)
	local entry = getSlotState(slot)
	if not entry then
		return "burst"
	end
	return entry.mode or "burst"
end

function State.SetMode(slot, mode)
	local entry = getSlotState(slot)
	if not entry then
		return
	end
	if mode ~= "semi" and mode ~= "burst" then
		return
	end
	entry.mode = mode
end

function State.SyncToTotal(slot, totalAmmo, clipSize)
	local entry = getSlotState(slot)
	if not entry then
		return
	end
	syncToTotal(entry, totalAmmo, clipSize)
end

function State.GetGunAmmo(slot, side)
	local entry = getSlotState(slot)
	if not entry then
		return 0
	end
	local resolvedSide = resolveSide(side)
	return entry.gunAmmo[resolvedSide] or 0
end

function State.SetGunAmmo(slot, side, amount, clipSize)
	local entry = getSlotState(slot)
	if not entry then
		return
	end
	local resolvedSide = resolveSide(side)
	local sideCapacity = getSideCapacity(clipSize)
	entry.gunAmmo[resolvedSide] = clampAmmo(amount, sideCapacity)
end

function State.AddGunAmmo(slot, side, amount, clipSize)
	local entry = getSlotState(slot)
	if not entry then
		return 0
	end
	local resolvedSide = resolveSide(side)
	local sideCapacity = getSideCapacity(clipSize)
	local current = entry.gunAmmo[resolvedSide] or 0
	local toAdd = clampAmmo(amount, sideCapacity)
	local final = math.min(current + toAdd, sideCapacity)
	local applied = final - current
	entry.gunAmmo[resolvedSide] = final
	return applied
end

function State.TryConsumeGunAmmo(slot, side, amount)
	local entry = getSlotState(slot)
	if not entry then
		return false
	end
	local resolvedSide = resolveSide(side)
	local current = entry.gunAmmo[resolvedSide] or 0
	local requested = math.max(math.floor(tonumber(amount) or 1), 1)
	if current < requested then
		return false
	end
	entry.gunAmmo[resolvedSide] = current - requested
	return true
end

function State.GetSelectedADSSide(slot)
	local entry = getSlotState(slot)
	if not entry then
		return "right"
	end
	return resolveSide(entry.ads.side)
end

function State.IsADSActive(slot)
	local entry = getSlotState(slot)
	if not entry then
		return false
	end
	return entry.ads.active == true
end

function State.EnterADS(slot, totalAmmo, clipSize)
	local entry = getSlotState(slot)
	if not entry then
		return "right"
	end

	syncToTotal(entry, totalAmmo, clipSize)

	local nextSide
	if entry.ads.lastSide == nil then
		nextSide = "right"
	else
		nextSide = getOtherSide(entry.ads.lastSide)
	end

	if (entry.gunAmmo[nextSide] or 0) <= 0 then
		local fallback = getOtherSide(nextSide)
		if (entry.gunAmmo[fallback] or 0) > 0 then
			nextSide = fallback
		end
	end

	entry.ads.side = nextSide
	entry.ads.active = true
	return nextSide
end

function State.ExitADS(slot)
	local entry = getSlotState(slot)
	if not entry then
		return
	end
	entry.ads.active = false
	entry.ads.lastSide = resolveSide(entry.ads.side)
end

return State
