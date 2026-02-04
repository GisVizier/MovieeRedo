local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local GadgetUtils = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("GadgetUtils"))
local Net = require(Locations.Shared.Net.Net)

local TrainingRangeShot = {}

local STATE = {} -- [gadgetId] = { count, move, practiceActive }
local LAST_HIT = {} -- [gadgetId] = time
local DEBOUNCE_SECONDS = 0.2
local MIN_COUNT = 1
local MAX_COUNT = 8

-- Debug flag
local function findDescendantByName(root, name)
	if not root then
		return nil
	end
	for _, desc in ipairs(root:GetDescendants()) do
		if desc.Name == name then
			return desc
		end
	end
	return nil
end

local function findTrainingRangeModel(instance)
	local current = instance
	while current and current.Parent do
		if current:IsA("Model") and current:GetAttribute("GadgetType") == "TrainingRange" then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getSurfaceGuiAndPart(model)
	if not model then
		return nil, nil
	end
	local surfaceGui = model:FindFirstChild("SurfaceGui", true)
	if not surfaceGui then
		return nil, nil
	end
	local part = surfaceGui.Adornee
	if not part or not part:IsA("BasePart") then
		local parent = surfaceGui.Parent
		if parent and parent:IsA("BasePart") then
			part = parent
		end
	end
	if not part then
		return nil, nil
	end
	return surfaceGui, part
end

local function worldToSurfaceUV(part, surfaceGui, worldPos)
	if not part or not surfaceGui then
		return nil
	end
	local size = part.Size
	local localPos = part.CFrame:PointToObjectSpace(worldPos)
	local face = surfaceGui.Face
	local u, v

	if face == Enum.NormalId.Front then
		u = 0.5 + (localPos.X / size.X)
		v = 0.5 - (localPos.Y / size.Y)
	elseif face == Enum.NormalId.Back then
		u = 0.5 - (localPos.X / size.X)
		v = 0.5 - (localPos.Y / size.Y)
	elseif face == Enum.NormalId.Right then
		u = 0.5 - (localPos.Z / size.Z)
		v = 0.5 - (localPos.Y / size.Y)
	elseif face == Enum.NormalId.Left then
		u = 0.5 + (localPos.Z / size.Z)
		v = 0.5 - (localPos.Y / size.Y)
	elseif face == Enum.NormalId.Top then
		u = 0.5 + (localPos.X / size.X)
		v = 0.5 + (localPos.Z / size.Z)
	elseif face == Enum.NormalId.Bottom then
		u = 0.5 + (localPos.X / size.X)
		v = 0.5 - (localPos.Z / size.Z)
	else
		return nil
	end

	if not u or not v then
		return nil
	end
	if u < 0 or u > 1 or v < 0 or v > 1 then
		return nil
	end

	local guiSize = surfaceGui.AbsoluteSize
	if guiSize.X <= 0 or guiSize.Y <= 0 then
		return nil
	end

	return Vector2.new(u * guiSize.X, v * guiSize.Y)
end

-- Check if point is inside a frame's bounds with padding
local function isPointInFrame(frame, point, padding)
	if not frame then
		return false
	end
	padding = padding or 0
	local pos = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	local minX = pos.X - padding
	local maxX = pos.X + size.X + padding
	local minY = pos.Y - padding
	local maxY = pos.Y + size.Y + padding
	return point.X >= minX and point.X <= maxX and point.Y >= minY and point.Y <= maxY
end

-- Get distance from point to frame center
local function getDistanceToFrame(frame, point)
	if not frame then
		return math.huge
	end
	local pos = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	local centerX = pos.X + size.X / 2
	local centerY = pos.Y + size.Y / 2
	local dx = point.X - centerX
	local dy = point.Y - centerY
	return math.sqrt(dx * dx + dy * dy)
end

-- Hit detection with priority for closest frame
-- Returns: "exit", "practice", "move_on", "move_off", "amount_up", "amount_down", or nil
local function getHitZone(point, surfaceGui)
	if not point or not surfaceGui then
		return nil
	end

	-- Padding for forgiveness (in pixels)
	local PADDING = 15

	-- Find all interactive frames
	local exitFrame = findDescendantByName(surfaceGui, "Exit")
	local practiceFrame = findDescendantByName(surfaceGui, "Practice")
	local moveFrame = findDescendantByName(surfaceGui, "Move")
	local amountFrame = findDescendantByName(surfaceGui, "DummyAmount")

	-- Get checkboxes
	local moveCheck1 = moveFrame and findDescendantByName(moveFrame, "Check1")
	local moveCheck2 = moveFrame and findDescendantByName(moveFrame, "Check2")
	local amountCheck1 = amountFrame and findDescendantByName(amountFrame, "Check1")
	local amountCheck2 = amountFrame and findDescendantByName(amountFrame, "Check2")

	-- Build list of all possible hits with their distances
	local candidates = {}

	-- Check all frames and add to candidates if hit
	if isPointInFrame(exitFrame, point, PADDING) then
		table.insert(candidates, { zone = "exit", dist = getDistanceToFrame(exitFrame, point) })
	end

	if isPointInFrame(practiceFrame, point, PADDING) then
		table.insert(candidates, { zone = "practice", dist = getDistanceToFrame(practiceFrame, point) })
	end

	-- For Move, check the checkboxes directly (more precise)
	if isPointInFrame(moveCheck1, point, PADDING) then
		table.insert(candidates, { zone = "move_on", dist = getDistanceToFrame(moveCheck1, point) })
	end
	if isPointInFrame(moveCheck2, point, PADDING) then
		table.insert(candidates, { zone = "move_off", dist = getDistanceToFrame(moveCheck2, point) })
	end

	-- For Amount, check the checkboxes directly (more precise)
	if isPointInFrame(amountCheck1, point, PADDING) then
		table.insert(candidates, { zone = "amount_down", dist = getDistanceToFrame(amountCheck1, point) })
	end
	if isPointInFrame(amountCheck2, point, PADDING) then
		table.insert(candidates, { zone = "amount_up", dist = getDistanceToFrame(amountCheck2, point) })
	end

	-- If no candidates, check if we're in parent Move/Amount frames and use distance fallback
	if #candidates == 0 then
		if isPointInFrame(moveFrame, point, PADDING) and moveCheck1 and moveCheck2 then
			-- Use distance to determine which checkbox
			local dist1 = getDistanceToFrame(moveCheck1, point)
			local dist2 = getDistanceToFrame(moveCheck2, point)
			if dist1 < dist2 then
				table.insert(candidates, { zone = "move_on", dist = dist1 })
			else
				table.insert(candidates, { zone = "move_off", dist = dist2 })
			end
		end

		if isPointInFrame(amountFrame, point, PADDING) and amountCheck1 and amountCheck2 then
			-- Use distance to determine which checkbox
			local dist1 = getDistanceToFrame(amountCheck1, point)
			local dist2 = getDistanceToFrame(amountCheck2, point)
			if dist1 < dist2 then
				table.insert(candidates, { zone = "amount_down", dist = dist1 })
			else
				table.insert(candidates, { zone = "amount_up", dist = dist2 })
			end
		end
	end

	-- No hits at all
	if #candidates == 0 then
		return nil
	end

	-- Sort by distance (closest first)
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)

	-- Return the closest one
	local winner = candidates[1]
	return winner.zone
end

-- Visual feedback: Flash Bar (1 -> 0 -> 1)
local function flashBarIn(checkFrame)
	if not checkFrame then
		return
	end
	local bar = findDescendantByName(checkFrame, "Bar")
	if not bar then
		return
	end

	-- Flash: 1 -> 0 (show), then 0 -> 1 (hide)
	bar.BackgroundTransparency = 1
	bar.BackgroundColor3 = Color3.new(1, 1, 1) -- White

	local tweenIn = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenOut = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local fadeIn = TweenService:Create(bar, tweenIn, { BackgroundTransparency = 0 })
	local fadeOut = TweenService:Create(bar, tweenOut, { BackgroundTransparency = 1 })

	fadeIn:Play()
	fadeIn.Completed:Connect(function()
		fadeOut:Play()
	end)
end

-- Update Move OutCome text only (bar is handled by flash, not persistent selection)
local function updateMoveText(moveFrame, moveEnabled)
	if not moveFrame then
		return
	end

	local moveOutcome = findDescendantByName(moveFrame, "OutCome")
	if moveOutcome and moveOutcome:IsA("TextLabel") then
		moveOutcome.Text = moveEnabled and "On" or "Off"
	end
end

-- Update Practice frame text only (no flash - flash is handled separately when button is pressed)
local function updatePracticeText(practiceFrame, isActive)
	if not practiceFrame then
		return
	end

	-- Find text label (could be named "Text" or "Label" or be the frame itself)
	local textLabel = findDescendantByName(practiceFrame, "Text")
		or findDescendantByName(practiceFrame, "Label")
		or findDescendantByName(practiceFrame, "TextLabel")

	-- Also check if Practice frame has a TextLabel child directly
	if not textLabel then
		for _, child in ipairs(practiceFrame:GetDescendants()) do
			if child:IsA("TextLabel") then
				textLabel = child
				break
			end
		end
	end

	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = isActive and "Reset" or "Practice"
	end
end

local function getState(gadgetId)
	if not STATE[gadgetId] then
		STATE[gadgetId] = {
			count = 4,
			move = false,
			practiceActive = false, -- Tracks if practice is currently running
		}
	end
	return STATE[gadgetId]
end

local function refreshOutcome(surfaceGui, state)
	if not surfaceGui or not state then
		return
	end
	local amountFrame = findDescendantByName(surfaceGui, "DummyAmount")
	local moveFrame = findDescendantByName(surfaceGui, "Move")
	local practiceFrame = findDescendantByName(surfaceGui, "Practice")
	local amountOutcome = amountFrame and findDescendantByName(amountFrame, "OutCome")
	local moveOutcome = moveFrame and findDescendantByName(moveFrame, "OutCome")

	if amountOutcome and amountOutcome:IsA("TextLabel") then
		amountOutcome.Text = tostring(state.count)
	end
	if moveOutcome and moveOutcome:IsA("TextLabel") then
		moveOutcome.Text = state.move and "On" or "Off"
	end

	-- Update practice button text (no flash here)
	updatePracticeText(practiceFrame, state.practiceActive)

	-- Update move text
	updateMoveText(moveFrame, state.move)
end

local function sendApply(gadgetId, state)
	Net:FireServer("GadgetUseRequest", gadgetId, {
		action = "apply",
		count = state.count,
		move = state.move,
	})
end

local function sendStop(gadgetId)
	Net:FireServer("GadgetUseRequest", gadgetId, {
		action = "stop",
	})
end

function TrainingRangeShot:TryHandleHit(hitInstance, hitPosition)
	local model = findTrainingRangeModel(hitInstance)
	if not model then
		return false
	end

	local gadgetId = GadgetUtils:getOrCreateId(model)
	if not gadgetId then
		return false
	end

	local now = os.clock()
	local last = LAST_HIT[gadgetId]
	if last and (now - last) < DEBOUNCE_SECONDS then
		return true
	end

	local surfaceGui, part = getSurfaceGuiAndPart(model)
	if not surfaceGui or not part then
		return false
	end

	local point = worldToSurfaceUV(part, surfaceGui, hitPosition)
	if not point then
		return false
	end

	local state = getState(gadgetId)
	local handled = false
	local zone = getHitZone(point, surfaceGui)

	local amountFrame = findDescendantByName(surfaceGui, "DummyAmount")
	local moveFrame = findDescendantByName(surfaceGui, "Move")

	if zone == "exit" then
		-- Exit/Stop - reset state and stop dummies
		state.practiceActive = false
		sendStop(gadgetId)
		handled = true
	elseif zone == "practice" then
		-- Practice button - toggle practice on/off
		local practiceFrame = findDescendantByName(surfaceGui, "Practice")

		if state.practiceActive then
			-- Currently active -> Reset: stop dummies, reset to defaults, respawn
			sendStop(gadgetId)

			-- Reset state to defaults
			state.count = 4
			state.move = false

			-- Update UI to show default values
			local amountOutcome = findDescendantByName(amountFrame, "OutCome")
			if amountOutcome and amountOutcome:IsA("TextLabel") then
				amountOutcome.Text = tostring(state.count)
			end
			updateMoveText(moveFrame, state.move)

			task.wait(0.1) -- Brief delay before respawning
			sendApply(gadgetId, state)
		else
			-- Not active -> Start practice with current count/move settings
			state.practiceActive = true
			sendApply(gadgetId, state)
		end

		-- Flash the bar ONLY when Practice button is actually pressed
		flashBarIn(practiceFrame)
		handled = true
	elseif zone == "move_on" then
		-- Move YES - update local state
		local wasOff = not state.move
		state.move = true
		updateMoveText(moveFrame, state.move)
		-- Flash the bar to show button was pressed (Check1 = YES)
		local check1 = findDescendantByName(moveFrame, "Check1")
		flashBarIn(check1)

		-- If practice is active and move changed from OFF to ON, auto-reset dummies
		if state.practiceActive and wasOff then
			sendStop(gadgetId)
			task.wait(0.1)
			sendApply(gadgetId, state)
		end

		handled = true
	elseif zone == "move_off" then
		-- Move NO - update local state
		state.move = false
		updateMoveText(moveFrame, state.move)
		-- Flash the bar to show button was pressed (Check2 = NO)
		local check2 = findDescendantByName(moveFrame, "Check2")
		flashBarIn(check2)
		handled = true
	elseif zone == "move_toggle" then
		local wasOff = not state.move
		state.move = not state.move
		updateMoveText(moveFrame, state.move)

		-- If practice is active and move changed from OFF to ON, auto-reset dummies
		if state.practiceActive and state.move and wasOff then
			sendStop(gadgetId)
			task.wait(0.1)
			sendApply(gadgetId, state)
		end

		handled = true
	elseif zone == "amount_up" then
		-- Increase count - just update local state, don't apply until Practice is pressed
		state.count = math.clamp(state.count + 1, MIN_COUNT, MAX_COUNT)
		-- Flash the bar to show button was pressed (Check2 = add / +)
		local check2 = findDescendantByName(amountFrame, "Check2")
		flashBarIn(check2)
		-- Update outcome text
		local amountOutcome = findDescendantByName(amountFrame, "OutCome")
		if amountOutcome and amountOutcome:IsA("TextLabel") then
			amountOutcome.Text = tostring(state.count)
		end
		handled = true
	elseif zone == "amount_down" then
		-- Decrease count - just update local state, don't apply until Practice is pressed
		state.count = math.clamp(state.count - 1, MIN_COUNT, MAX_COUNT)
		-- Flash the bar to show button was pressed (Check1 = subtract / -)
		local check1 = findDescendantByName(amountFrame, "Check1")
		flashBarIn(check1)
		-- Update outcome text
		local amountOutcome = findDescendantByName(amountFrame, "OutCome")
		if amountOutcome and amountOutcome:IsA("TextLabel") then
			amountOutcome.Text = tostring(state.count)
		end
		handled = true
	end

	if not handled then
		return false
	end

	LAST_HIT[gadgetId] = now

	-- Refresh practice button text (no flash - flash only happens when practice is actually pressed)
	local practiceFrame = findDescendantByName(surfaceGui, "Practice")
	updatePracticeText(practiceFrame, state.practiceActive)

	return true
end

return TrainingRangeShot
