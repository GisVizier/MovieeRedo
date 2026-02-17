local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inspect = require(script.Parent:WaitForChild("Inspect"))
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local HitPacketUtils = require(Locations.Shared.Util:WaitForChild("HitPacketUtils"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local DualPistolsState = require(script.Parent:WaitForChild("State"))
local DualPistolsVisuals = require(script.Parent:WaitForChild("Visuals"))

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
	return runtime
end

local function getOtherSide(side)
	return (side == "left") and "right" or "left"
end

local function getHipfirePatternSide(shotIndex)
	local shotPattern = { "right", "left", "right" }
	return shotPattern[((shotIndex - 1) % #shotPattern) + 1]
end

local function getFireAnimationName(side, isADS)
	if isADS then
		return (side == "left") and "SpecailLeftFire" or "SpecailRightFire"
	end
	return (side == "left") and "Fire2" or "Fire1"
end

local function getSideAmmo(slot, side)
	return DualPistolsState.GetGunAmmo(slot, side)
end

local function syncSlotAmmoState(weaponInstance, state, config)
	DualPistolsState.SyncToTotal(weaponInstance.Slot, state.CurrentAmmo or 0, config.clipSize or 16)
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

local function findGunAttachment(model, gunName, attachmentName)
	if not model then
		return nil
	end

	local partsFolder = model:FindFirstChild("Parts")
	if partsFolder and (partsFolder:IsA("Model") or partsFolder:IsA("Folder")) then
		local gunNode = partsFolder:FindFirstChild(gunName)
		if gunNode then
			local direct = gunNode:FindFirstChild(attachmentName, true)
			if direct and direct:IsA("Attachment") then
				return direct
			end
		end
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc.Name == gunName and (desc:IsA("BasePart") or desc:IsA("Model")) then
			local found = desc:FindFirstChild(attachmentName, true)
			if found and found:IsA("Attachment") then
				return found
			end
		end
	end

	return nil
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

	rightMuzzle = findGunAttachment(gunModel, "RightGun", "MuzzleAttachment")
	leftMuzzle = findGunAttachment(gunModel, "LeftGun", "MuzzleAttachment")

	return rightMuzzle, leftMuzzle, gunModel
end

local function consumeShotAmmo(weaponInstance, state, config, side)
	local clipSize = config.clipSize or 16
	if not DualPistolsState.TryConsumeGunAmmo(weaponInstance.Slot, side, 1) then
		if (state.CurrentAmmo or 0) <= 0 then
			return false, "NoAmmo"
		end
		return false, "SideEmpty"
	end

	if weaponInstance.DecrementAmmo then
		local ok = weaponInstance.DecrementAmmo()
		if not ok then
			DualPistolsState.AddGunAmmo(weaponInstance.Slot, side, 1, clipSize)
			return false, "NoAmmo"
		end
		if weaponInstance.GetCurrentAmmo then
			state.CurrentAmmo = weaponInstance.GetCurrentAmmo()
		end
	else
		state.CurrentAmmo = math.max((state.CurrentAmmo or 0) - 1, 0)
	end

	syncSlotAmmoState(weaponInstance, state, config)

	if weaponInstance.ApplyState then
		weaponInstance.ApplyState(state)
	end
	DualPistolsVisuals.UpdateAmmoVisibility(weaponInstance, state.CurrentAmmo or 0)

	return true
end

local function fireShot(weaponInstance, side, shotOptions)
	local state = weaponInstance.State
	local config = weaponInstance.Config
	if not state or not config then
		return false, "InvalidState"
	end
	if (state.CurrentAmmo or 0) <= 0 then
		return false, "NoAmmo"
	end
	if getSideAmmo(weaponInstance.Slot, side) <= 0 then
		return false, "SideEmpty"
	end

	local options = shotOptions or {}
	local now = workspace:GetServerTimeNow()
	state.LastFireTime = now

	local ammoOk, ammoReason = consumeShotAmmo(weaponInstance, state, config, side)
	if not ammoOk then
		return false, ammoReason or "NoAmmo"
	end

	local animName = options.animName or getFireAnimationName(side, options.adsShot == true)
	if weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack(animName, 0.03)
	elseif weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation(animName, 0.03, true)
	end

	local rightMuzzle, leftMuzzle, gunModel = getDualMuzzleAttachments(weaponInstance)
	local muzzleAttachment = (side == "left") and leftMuzzle or rightMuzzle

	local ignoreSpread = options.ignoreSpread == true
	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(ignoreSpread)
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
					adsShot = options.adsShot == true,
				})
			end
		end

		if weaponInstance.PlayFireEffects then
			weaponInstance.PlayFireEffects(hitData)
		end
	end

	return true
end

local function selectBurstSide(weaponInstance, shotIndex)
	local slot = weaponInstance.Slot
	local preferred = getHipfirePatternSide(shotIndex)
	if getSideAmmo(slot, preferred) > 0 then
		return preferred
	end

	local fallback = getOtherSide(preferred)
	if getSideAmmo(slot, fallback) > 0 then
		return fallback
	end

	return nil
end

local function selectSemiHipfireSide(weaponInstance)
	local slot = weaponInstance.Slot
	if getSideAmmo(slot, "right") > 0 then
		return "right"
	end
	if getSideAmmo(slot, "left") > 0 then
		return "left"
	end
	return nil
end

local function runBurstTail(weaponInstance, runtime, token, shotsPerBurst, shotInterval)
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

		local side = selectBurstSide(weaponInstance, shotIndex)
		if not side then
			break
		end

		local ok = fireShot(weaponInstance, side, {
			ignoreSpread = false,
			adsShot = false,
		})
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
	local slot = weaponInstance.Slot

	syncSlotAmmoState(weaponInstance, state, config)

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
	local mode = DualPistolsState.GetMode(slot)
	runtime.mode = mode

	local isADS = DualPistolsState.IsADSActive(slot)
	if isADS then
		local adsSide = DualPistolsState.GetSelectedADSSide(slot)
		local adsSideAmmo = getSideAmmo(slot, adsSide)
		if adsSideAmmo <= 0 then
			local otherAmmo = getSideAmmo(slot, getOtherSide(adsSide))
			if otherAmmo > 0 then
				return false, "SideEmpty"
			end
			return false, "NoAmmo"
		end

		local ok, reason = fireShot(weaponInstance, adsSide, {
			ignoreSpread = true,
			adsShot = true,
		})
		if not ok then
			return false, reason
		end

		runtime.nextTriggerTime = now + semiInterval
		runtime.token += 1
		runtime.bursting = false
		return true
	end

	if mode == "semi" then
		local side = selectSemiHipfireSide(weaponInstance)
		if not side then
			return false, "NoAmmo"
		end

		local ok, reason = fireShot(weaponInstance, side, {
			ignoreSpread = false,
			adsShot = false,
		})
		if not ok then
			return false, reason
		end

		runtime.nextTriggerTime = now + semiInterval
		runtime.token += 1
		runtime.bursting = false
		return true
	end

	runtime.token += 1
	local token = runtime.token
	runtime.bursting = true
	runtime.nextTriggerTime = now + burstCooldown

	local firstSide = selectBurstSide(weaponInstance, 1)
	if not firstSide then
		runtime.bursting = false
		return false, "NoAmmo"
	end

	local firstOk, firstReason = fireShot(weaponInstance, firstSide, {
		ignoreSpread = false,
		adsShot = false,
	})
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
