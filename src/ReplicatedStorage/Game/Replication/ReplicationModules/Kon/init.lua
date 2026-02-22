@ -11,6 +11,8 @@
	- selfLaunch(originUserId, data) - Server-triggered self-launch (uncrouch + launch up, ME only)
	- triggerTrap(originUserId, data) - Triggers trap: spawns Kon, plays VFX, despawns
	- destroyTrap(originUserId, data) - Cleans up trap marker
	- fireProjectile(originUserId, data) - Replicates flying Kon projectile on OTHER clients
	- projectileImpact(originUserId, data) - Smoke VFX at projectile impact point (ALL clients)
	
	data for createKon:
	- position: { X, Y, Z } (Kon spawn position)
@ -23,6 +25,15 @@
	data for triggerTrap:
	- position: { X, Y, Z } (trap position)
	
	data for fireProjectile:
	- startPosition: { X, Y, Z } (projectile start position)
	- direction: { X, Y, Z } (initial direction)
	- ownerId: number (UserId of the Aki player who fired)
	
	data for projectileImpact:
	- position: { X, Y, Z } (impact position)
	- ownerId: number (UserId of the Aki player who fired)
	
	data for User:
	- ViewModel: ViewmodelRig
	- forceAction: "start" | "bite" | "stop"
@ -206,11 +217,28 @@ local function playBiteVFX(konModel, position)
end

local function playSmokeVFX(konModel, position)
	-- Create a placeholder model if none provided (e.g. projectile impact — Kon already destroyed)
	-- The client FX module's "smoke" action reads Kon:GetChildren() so it must not be nil.
	local createdDummy = false
	if not konModel then
		konModel = Instance.new("Model")
		konModel.Name = "KonSmokeDummy"
		konModel.Parent = getEffectsFolder()
		createdDummy = true
	end

	ReplicateFX("kon", "smoke", { Character = game.Players.LocalPlayer.Character, Kon = konModel, Pivot = position})
	
	-- Play smoke sound at position
	local pos = typeof(position) == "CFrame" and position.Position or position
	playSoundAtPosition("smoke", pos)

	-- Clean up dummy after FX finishes
	if createdDummy then
		task.delay(15, function()
			if konModel and konModel.Parent then konModel:Destroy() end
		end)
	end
end

local function despawnKon(konModel, fadeTime)
@ -702,6 +730,179 @@ function Kon:selfLaunch(originUserId, data)
	end
end

--[[
	trapHitVoice - Plays the "Got you!" voice line when the trap activates
	
	Called via BroadcastVFX("Me") when _triggerTrap fires.
	
	data: (none required)
]]
function Kon:trapHitVoice(originUserId, data)
	local localPlayer = Players.LocalPlayer
	if not localPlayer or localPlayer.UserId ~= originUserId then return end
	
	local character = localPlayer.Character
	if not character then return end
	
	local root = character.PrimaryPart
		or character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Root")
	if not root then return end
	
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://138015603446992" -- "Got you!" voice line
	sound.Volume = 1
	sound.Parent = root
	sound:Play()
	
	sound.Ended:Once(function()
		if sound and sound.Parent then sound:Destroy() end
	end)
	task.delay(3, function()
		if sound and sound.Parent then sound:Destroy() end
	end)
end

--------------------------------------------------------------------------------
-- PROJECTILE VARIANT VFX (Main Variant)
--------------------------------------------------------------------------------

-- Active projectile Kon instances per player (for non-owner clients)
Kon._activeProjectiles = {}

--[[
	fireProjectile - Replicates the flying Kon projectile on OTHER clients
	
	Called via VFXRep:Fire("Others") when the caster launches the projectile.
	Other clients see a Kon model flying through the air with the fly animation.
	The caster already has their own local projectile — this is for spectators.
	
	data:
	- startPosition: { X, Y, Z }
	- direction: { X, Y, Z }
	- ownerId: number
]]
function Kon:fireProjectile(originUserId, data)
	if not data then return end
	
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end
	
	-- Don't show on caster (they have their own local projectile)
	if localPlayer.UserId == originUserId then return end
	
	local position = parsePosition(data.startPosition)
	if not position then return end
	local direction = parseLookVector(data.direction)
	
	-- Clean up any existing projectile for this player
	if self._activeProjectiles[originUserId] then
		local old = self._activeProjectiles[originUserId]
		if old.model and old.model.Parent then old.model:Destroy() end
		if old.connection then old.connection:Disconnect() end
		self._activeProjectiles[originUserId] = nil
	end
	
	-- Get konny template
	local template = getKonnyTemplate()
	if not template then return end
	
	local konModel = template:Clone()
	konModel.Name = "KonProjectile_" .. tostring(originUserId)
	konModel:ScaleTo(4) -- Same scale as local projectile
	konModel:PivotTo(CFrame.lookAt(position, position + direction) * CFrame.Angles(0, math.pi, 0))
	konModel.Parent = getEffectsFolder()
	
	-- Play flying animation
	playKonAnimationById(konModel, "138478054902806", true) -- PROJ_FLY_ANIM_ID
	
	-- Simple physics simulation for the visual (mirrors the caster's physics)
	local Locations2 = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
	local ProjectilePhysics2 = require(Locations2.Shared.Util:WaitForChild("ProjectilePhysics"))
	
	local physics = ProjectilePhysics2.new({
		speed = 130,
		gravity = 80,
		drag = 0.005,
		lifetime = 20,
	})
	
	local pos = position
	local vel = direction.Unit * 130
	local distTraveled = 0
	local maxRange = 500
	
	local projConn
	projConn = RunService.Heartbeat:Connect(function(dt)
		if not konModel or not konModel.Parent then
			if projConn then projConn:Disconnect() end
			return
		end
		
		if distTraveled >= maxRange then
			konModel:Destroy()
			projConn:Disconnect()
			self._activeProjectiles[originUserId] = nil
			return
		end
		
		-- Step physics (no collision on spectator — caster handles that)
		local newPos, newVel = physics:Step(pos, vel, dt, nil)
		distTraveled += (newPos - pos).Magnitude
		pos = newPos
		vel = newVel
		
		-- Update visual
		if vel.Magnitude > 0.1 then
			konModel:PivotTo(CFrame.lookAt(pos, pos + vel.Unit) * CFrame.Angles(0, math.pi, 0))
		end
	end)
	
	self._activeProjectiles[originUserId] = {
		model = konModel,
		connection = projConn,
	}
	
	-- Safety cleanup after lifetime
	task.delay(20, function()
		local entry = self._activeProjectiles[originUserId]
		if entry and entry.model == konModel then
			if entry.connection then entry.connection:Disconnect() end
			if konModel.Parent then konModel:Destroy() end
			self._activeProjectiles[originUserId] = nil
		end
	end)
end

--[[
	projectileImpact - Smoke VFX at the projectile impact point
	
	Called via VFXRep:Fire("All") when the projectile hits something.
	Destroys the spectator's flying Kon and plays smoke.
	
	data:
	- position: { X, Y, Z }
	- ownerId: number
]]
function Kon:projectileImpact(originUserId, data)
	if not data then return end
	
	local position = parsePosition(data.position)
	if not position then return end
	
	local ownerId = data.ownerId or originUserId
	
	-- Destroy the spectator projectile Kon (if viewing someone else's projectile)
	local entry = self._activeProjectiles[ownerId]
	if entry then
		if entry.connection then entry.connection:Disconnect() end
		if entry.model and entry.model.Parent then entry.model:Destroy() end
		self._activeProjectiles[ownerId] = nil
	end
	
	-- Impact FX will be added later by the user — no smoke for now
end

--[[
	destroyTrap - Clean up trap marker and any active Kon model
	
@ -742,6 +943,13 @@ Players.PlayerRemoving:Connect(function(player)
		trapMarker:Destroy()
		Kon._activeTraps[player.UserId] = nil
	end
	
	local projEntry = Kon._activeProjectiles[player.UserId]
	if projEntry then
		if projEntry.connection then projEntry.connection:Disconnect() end
		if projEntry.model and projEntry.model.Parent then projEntry.model:Destroy() end
		Kon._activeProjectiles[player.UserId] = nil
	end
end)

return Kon