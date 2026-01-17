--[[
	Attack.lua (SniperRifle)

	Handles firing the SniperRifle weapon with client-side hitscan.
]]

local Attack = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseGun = require(Locations.Modules.Weapons.Actions.Gun.BaseGun)
local HitscanSystem = require(Locations.Modules.Weapons.Systems.HitscanSystem)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local Config = require(Locations.Modules.Config)

local localPlayer = Players.LocalPlayer

--[[
	Execute the attack action
	@param weaponInstance table - The weapon instance
]]
function Attack.Execute(weaponInstance)
	local player = weaponInstance.Player
	local config = weaponInstance.Config
	local state = weaponInstance.State

	-- Check if can fire
	if not BaseGun.CanFire(weaponInstance) then
		print("[SniperRifle] Cannot fire - conditions not met")

		-- Play dry fire sound if out of ammo
		if state.CurrentAmmo <= 0 then
			-- TODO: Play dry fire sound
			print("[SniperRifle] Out of ammo - dry fire")
		end

		return
	end

	-- Check fire rate cooldown
	local currentTime = tick()
	local cooldown = BaseGun.GetFireCooldown(weaponInstance)

	if currentTime - state.LastFireTime < cooldown then
		print("[SniperRifle] Cooldown not ready")
		return
	end

	print("[SniperRifle] Firing for player:", player.Name)

	-- Set attacking state
	state.IsAttacking = true
	state.LastFireTime = currentTime

	-- Consume ammo
	BaseGun.ConsumeAmmo(weaponInstance, 1)

	-- Perform client-side hitscan raycast
	local camera = workspace.CurrentCamera
	if not camera then
		warn("[SniperRifle] No camera found")
		return
	end

	local character = player.Character
	if not character then
		warn("[SniperRifle] No character found")
		return
	end

	-- Calculate the first-person camera position (where camera would be in first person)
	-- This ensures bullets shoot from the character's head even when in third person

	-- Get the humanoid head (visual head used by camera)
	local humanoidHead = CharacterLocations:GetHumanoidHead(character)
	if not humanoidHead then
		warn("[SniperRifle] No humanoid head found on character")
		return
	end

	-- Determine crouch state
	local normalHead = CharacterLocations:GetHead(character)
	local crouchHead = CharacterLocations:GetCrouchHead(character)
	local normalHeadVisible = normalHead and normalHead.Transparency < 1
	local crouchHeadVisible = crouchHead and crouchHead.Transparency < 1
	local isCrouching = crouchHeadVisible and not normalHeadVisible

	-- Detect camera mode based on distance from character
	local cameraDistance = (camera.CFrame.Position - humanoidHead.Position).Magnitude
	local isThirdPerson = cameraDistance > 2

	-- Get first-person camera offset from config
	local firstPersonOffset = Config.Controls.Camera.FirstPersonOffset or Vector3.new(0, 0, 0)

	local origin
	if isThirdPerson then
		-- THIRD PERSON: Calculate where first-person camera would be
		-- Match the camera's calculation: baseHeadPosition + crouchOffset, then apply rotation and offset
		local crouchHeightReduction = Config.Gameplay.Character.CrouchHeightReduction or 0
		local crouchOffset = isCrouching and -crouchHeightReduction or 0

		local baseHeadPosition = humanoidHead.Position
		local headCFrame = CFrame.new(baseHeadPosition + Vector3.new(0, crouchOffset, 0))
		local cameraYRotation = math.atan2(-camera.CFrame.LookVector.X, -camera.CFrame.LookVector.Z)
		local characterRotation = headCFrame * CFrame.Angles(0, cameraYRotation, 0)
		origin = (characterRotation * CFrame.new(firstPersonOffset)).Position
	else
		-- FIRST PERSON: Use actual camera position (already includes smooth crouch transition)
		origin = camera.CFrame.Position
	end
	local maxRange = config.Damage.MaxRange or 500
	local direction = camera.CFrame.LookVector * maxRange

	-- Check if this weapon is in shotgun mode
	local isShotgun = config.Shotgun ~= nil
	local pelletCount = isShotgun and config.Shotgun.PelletCount or 1
	local pelletSpread = isShotgun and config.Shotgun.PelletSpread or 0

	-- DEBUG: Print raycast details
	print("[SniperRifle] Raycast Origin:", origin)
	print("[SniperRifle] Raycast Direction:", direction)
	print("[SniperRifle] Raycast Max Range:", maxRange)
	if isShotgun then
		print("[SniperRifle] SHOTGUN MODE - Pellets:", pelletCount, "Spread:", pelletSpread)
	end

	-- Perform raycast(s) based on mode
	local raycastResults = {}

	if isShotgun then
		-- Shotgun mode: multiple raycasts with spread
		raycastResults = HitscanSystem:PerformSpreadRaycast(
			origin,
			direction,
			pelletSpread,
			pelletCount,
			character,
			tostring(player.UserId)
		)
	else
		-- Normal mode: single raycast
		local singleResult = HitscanSystem:PerformRaycast(origin, direction, character, tostring(player.UserId))
		if singleResult then
			raycastResults = {singleResult}
		end
	end

	-- DEBUG: Visualize all raycast paths
	for pelletIndex, raycastResult in ipairs(raycastResults) do
		local beamAttachment0 = Instance.new("Attachment")
		local beamAttachment1 = Instance.new("Attachment")
		local beam = Instance.new("Beam")

		beamAttachment0.Parent = workspace.Terrain
		beamAttachment1.Parent = workspace.Terrain
		beamAttachment0.WorldPosition = origin

		local isHeadshotHit = false
		if raycastResult then
			beamAttachment1.WorldPosition = raycastResult.Position

			-- Check if we hit a player's hitbox or just a wall/object
			local isHitboxHit = HitscanSystem:IsHitboxPart(raycastResult.Instance)

			if isHitboxHit then
				-- Check if headshot
				isHeadshotHit = HitscanSystem:IsHeadshot(raycastResult.Instance)

				if isHeadshotHit then
					beam.Color = ColorSequence.new(Color3.new(1, 0, 0)) -- Red = headshot
					print("[SniperRifle] DEBUG - Pellet", pelletIndex, "HEADSHOT!")
				else
					beam.Color = ColorSequence.new(Color3.new(0, 1, 0)) -- Green = body shot
					print("[SniperRifle] DEBUG - Pellet", pelletIndex, "HIT PLAYER BODY!")
				end
			else
				beam.Color = ColorSequence.new(Color3.new(0, 0, 0)) -- Black = wall/object hit
				print("[SniperRifle] DEBUG - Pellet", pelletIndex, "Hit wall/object (not a player)")
			end

			print("[SniperRifle] DEBUG - Pellet", pelletIndex, "Hit Instance:", raycastResult.Instance:GetFullName())
			print("[SniperRifle] DEBUG - Pellet", pelletIndex, "Hit Position:", raycastResult.Position)
			print("[SniperRifle] DEBUG - Pellet", pelletIndex, "Distance:", raycastResult.Distance)
		else
			beamAttachment1.WorldPosition = origin + direction
			beam.Color = ColorSequence.new(Color3.new(0, 0, 0)) -- Black = complete miss
			print("[SniperRifle] DEBUG - Pellet", pelletIndex, "No hit detected")
		end

		beam.Attachment0 = beamAttachment0
		beam.Attachment1 = beamAttachment1
		beam.Width0 = 0.1
		beam.Width1 = 0.1
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new(0) -- Start fully opaque
		beam.Parent = workspace.Terrain

		-- Fade out and cleanup after duration
		local fadeOutDuration = 0.5
		local totalDuration = 2

		task.delay(totalDuration - fadeOutDuration, function()
			if beam and beam.Parent then
				local startTime = tick()
				local fadeConnection
				fadeConnection = RunService.RenderStepped:Connect(function()
					local elapsed = tick() - startTime
					local alpha = math.min(elapsed / fadeOutDuration, 1)

					if beam and beam.Parent then
						beam.Transparency = NumberSequence.new(alpha)
					end

					if alpha >= 1 then
						if fadeConnection then
							fadeConnection:Disconnect()
						end
					end
				end)
			end
		end)

		task.delay(totalDuration, function()
			beam:Destroy()
			beamAttachment0:Destroy()
			beamAttachment1:Destroy()
		end)
	end

	-- Prepare hit data to send to server
	local hitData = {
		WeaponType = weaponInstance.WeaponType,
		WeaponName = weaponInstance.WeaponName,
		Origin = origin,
		Direction = direction,
		Timestamp = os.clock(),
		IsShotgun = isShotgun,
		PelletCount = pelletCount,
		Hits = {},
	}

	-- Process all raycast results
	for pelletIndex, raycastResult in ipairs(raycastResults) do
		if raycastResult then
			local hitInfo = {
				HitPosition = raycastResult.Position,
				HitPartName = raycastResult.Instance.Name,
				Distance = raycastResult.Distance,
			}

			-- Check if we hit a player's hitbox (not just a wall/object)
			local isHitboxHit = HitscanSystem:IsHitboxPart(raycastResult.Instance)

			if isHitboxHit then
				-- We hit a player's hitbox - add damage info
				hitInfo.IsHeadshot = HitscanSystem:IsHeadshot(raycastResult.Instance)
				hitInfo.TargetPlayer = HitscanSystem:GetPlayerFromHit(raycastResult.Instance)

				print("[SniperRifle] Pellet", pelletIndex, "HIT PLAYER!", {
					Player = hitInfo.TargetPlayer and hitInfo.TargetPlayer.Name or "Unknown",
					Part = raycastResult.Instance.Name,
					Distance = raycastResult.Distance,
					Headshot = hitInfo.IsHeadshot,
				})

				if hitInfo.IsHeadshot then
					print("[SniperRifle] Pellet", pelletIndex, "HEADSHOT CONFIRMED!")
				end
			else
				print("[SniperRifle] Pellet", pelletIndex, "HIT WALL/OBJECT", {
					Object = raycastResult.Instance:GetFullName(),
					Distance = raycastResult.Distance,
				})
			end

			table.insert(hitData.Hits, hitInfo)
		end
	end

	if #hitData.Hits == 0 then
		print("[SniperRifle] All pellets missed")
	end

	-- Send hit data to server for validation and damage application
	RemoteEvents:FireServer("WeaponFired", hitData)

	-- TODO: Play fire animation
	-- TODO: Play fire sound
	-- TODO: Show muzzle flash
	-- TODO: Apply recoil to camera

	print("[SniperRifle] Ammo remaining:", state.CurrentAmmo, "/", config.Ammo.MagSize)

	-- Release attacking state after a brief delay (for both Semi and Auto)
	-- This allows the fire rate cooldown to work properly
	task.wait(0.1)
	state.IsAttacking = false

	-- Auto reload if enabled and magazine is empty
	if state.CurrentAmmo <= 0 and config.Ammo.AutoReload and state.ReserveAmmo > 0 then
		print("[SniperRifle] Auto-reloading...")
		local WeaponManager = require(Locations.Modules.Weapons.Managers.WeaponManager)
		WeaponManager:ReloadWeapon(player, weaponInstance)
	end
end

return Attack
