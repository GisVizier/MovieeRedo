local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inspect = require(script.Parent:WaitForChild("Inspect"))
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local HitPacketUtils = require(Locations.Shared.Util:WaitForChild("HitPacketUtils"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local DualPistolsState = require(script.Parent:WaitForChild("State"))

local Attack = {}

local runtimeByWeapon = setmetatable({}, { __mode = "k" })

local function getRuntime(weaponInstance)
	local runtime = runtimeByWeapon[weaponInstance]
	if not runtime then
		runtime = {
			token = 0,
			bursting = false,
			nextTriggerTime = 0,
			mode = "burst",
		}
		runtimeByWeapon[weaponInstance] = runtime
	end
	if not runtime.mode then
		runtime.mode = DualPistolsState.GetMode(weaponInstance.Slot)
	end
	return runtime
end

local function isWeaponStillActive(weaponInstance)
	if not weaponInstance then
		return false
	end

	local state = weaponInstance.State
	if not state or state.Equipped == false then
		return false
	end

	local weaponController = ServiceRegistry:GetController("Weapon")
		or ServiceRegistry:GetController("WeaponController")
	if not weaponController then
		return true
	end

	if type(weaponController.GetWeaponInstance) == "function" and weaponController:GetWeaponInstance() ~= weaponInstance then
		return false
	end

	local viewmodelController = weaponController._viewmodelController
	if viewmodelController and type(viewmodelController.GetActiveSlot) == "function" then
		local activeSlot = viewmodelController:GetActiveSlot()
		if activeSlot ~= weaponInstance.Slot then
			return false
		end
	end

	return true
end

local function getDualMuzzleAttachments(weaponInstance)
	local rightMuzzle = nil
	local leftMuzzle = nil
	local gunModel = nil

	if weaponInstance.GetRig then
		local rig = weaponInstance.GetRig()
		gunModel = rig and rig.Model or nil
	end
	if not gunModel then
		return nil, nil, nil
	end

	local rightGun = gunModel:FindFirstChild("RightGun", true)
	local leftGun = gunModel:FindFirstChild("LeftGun", true)

	if rightGun then
		local found = rightGun:FindFirstChild("MuzzleAttachment", true)
		if found and found:IsA("Attachment") then
			rightMuzzle = found
		end
	end

	if leftGun then
		local found = leftGun:FindFirstChild("MuzzleAttachment", true)
		if found and found:IsA("Attachment") then
			leftMuzzle = found
		end
	end

	return rightMuzzle, leftMuzzle, gunModel
end

local function consumeShotAmmo(weaponInstance, state)
	if weaponInstance.DecrementAmmo then
		local ok = weaponInstance.DecrementAmmo()
		if not ok then
			return false
		end
		if weaponInstance.GetCurrentAmmo then
			state.CurrentAmmo = weaponInstance.GetCurrentAmmo()
		end
	else
		state.CurrentAmmo = math.max((state.CurrentAmmo or 0) - 1, 0)
	end

	if weaponInstance.ApplyState then
		weaponInstance.ApplyState(state)
	end

	return true
end

local function fireShot(weaponInstance, side)
	local state = weaponInstance.State
	if not state then
		return false, "InvalidState"
	end
	if (state.CurrentAmmo or 0) <= 0 then
		return false, "NoAmmo"
	end

	local now = workspace:GetServerTimeNow()
	state.LastFireTime = now

	local ammoOk = consumeShotAmmo(weaponInstance, state)
	if not ammoOk then
		return false, "NoAmmo"
	end

	local animName = (side == "left") and "Fire2" or "Fire1"
	if weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack(animName, 0.03)
	elseif weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation(animName, 0.03, true)
	end

	local rightMuzzle, leftMuzzle, gunModel = getDualMuzzleAttachments(weaponInstance)
	local muzzleAttachment = (side == "left") and leftMuzzle or rightMuzzle

	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(false)
	if hitData then
		hitData.timestamp = now
		hitData.muzzleAttachment = muzzleAttachment
		hitData.gunModel = gunModel

		if weaponInstance.Net then
			local packet = HitPacketUtils:CreatePacket(hitData, weaponInstance.WeaponName)
			if packet then
				weaponInstance.Net:FireServer("WeaponFired", {
					packet = packet,
					weaponId = weaponInstance.WeaponName,
				})
			end
		end

		if weaponInstance.PlayFireEffects then
			weaponInstance.PlayFireEffects(hitData)
		end
	end

	return true
end

local function runBurstTail(weaponInstance, runtime, token, shotsPerBurst, shotInterval)
	local shotPattern = { "right", "left", "right" }
	for shotIndex = 2, shotsPerBurst do
		if runtime.token ~= token then
			break
		end
		if not isWeaponStillActive(weaponInstance) then
			break
		end

		local state = weaponInstance.State
		if not state or state.IsReloading then
			break
		end
		if (state.CurrentAmmo or 0) <= 0 then
			break
		end

		task.wait(shotInterval)

		if runtime.token ~= token then
			break
		end
		if not isWeaponStillActive(weaponInstance) then
			break
		end
		state = weaponInstance.State
		if not state or state.IsReloading or (state.CurrentAmmo or 0) <= 0 then
			break
		end

		local side = shotPattern[((shotIndex - 1) % #shotPattern) + 1]
		local ok = fireShot(weaponInstance, side)
		if not ok then
			break
		end
	end

	if runtime.token == token then
		runtime.bursting = false
	end
end

function Attack.Execute(weaponInstance, currentTime)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	Inspect.Cancel()

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local now = currentTime or workspace:GetServerTimeNow()
	local runtime = getRuntime(weaponInstance)

	if state.Equipped == false then
		return false, "NotEquipped"
	end
	if state.IsReloading then
		return false, "Reloading"
	end
	if not isWeaponStillActive(weaponInstance) then
		return false, "NotEquipped"
	end
	if runtime.bursting then
		return false, "Cooldown"
	end
	if now < (runtime.nextTriggerTime or 0) then
		return false, "Cooldown"
	end
	if (state.CurrentAmmo or 0) <= 0 then
		return false, "NoAmmo"
	end

	local burstConfig = config.burstProfile or {}
	local shotsPerBurst = burstConfig.shots or 3
	local burstShotInterval = burstConfig.shotInterval or 0.07
	local burstCooldown = burstConfig.burstCooldown or 0.24
	local semiInterval = 60 / (config.fireRate or 700)
	local mode = runtime.mode or DualPistolsState.GetMode(weaponInstance.Slot)
	runtime.mode = mode

	-- Partial reload state (one gun loaded): semi only, right gun only.
	if mode == "semi" then
		local ok, reason = fireShot(weaponInstance, "right")
		if not ok then
			return false, reason
		end

		runtime.nextTriggerTime = now + semiInterval
		runtime.token += 1
		runtime.bursting = false
		return true
	end

	-- Dual loaded mode: 3-shot burst pattern (Fire1 -> Fire2 -> Fire1).
	runtime.token += 1
	local token = runtime.token
	runtime.bursting = true
	runtime.nextTriggerTime = now + burstCooldown

	local firstOk, firstReason = fireShot(weaponInstance, "right")
	if not firstOk then
		runtime.bursting = false
		return false, firstReason
	end

	task.spawn(function()
		runBurstTail(weaponInstance, runtime, token, shotsPerBurst, burstShotInterval)
	end)

	return true
end

function Attack.Cancel(weaponInstance)
	if not weaponInstance then
		return
	end
	local runtime = getRuntime(weaponInstance)
	runtime.token += 1
	runtime.bursting = false
end

function Attack.SetFireMode(weaponInstance, mode)
	if not weaponInstance then
		return
	end
	local resolved = (mode == "semi") and "semi" or "burst"
	local runtime = getRuntime(weaponInstance)
	runtime.mode = resolved
	DualPistolsState.SetMode(weaponInstance.Slot, resolved)
end

return Attack
