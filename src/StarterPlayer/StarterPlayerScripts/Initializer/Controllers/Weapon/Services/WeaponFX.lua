local Workspace = game:GetService("Workspace")

local WeaponFX = {}
WeaponFX.__index = WeaponFX

function WeaponFX.new(loadoutConfig, logService)
	local self = setmetatable({}, WeaponFX)
	self._loadoutConfig = loadoutConfig
	self._logService = logService
	return self
end

function WeaponFX:RenderBulletTracer(hitData)
	if not hitData then
		return
	end

	local weaponConfig = self._loadoutConfig.getWeapon(hitData.weaponId)
	if not weaponConfig then
		return
	end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	local distance = (hitData.hitPosition - hitData.origin).Magnitude
	part.Size = Vector3.new(0.1, 0.1, distance)
	part.CFrame = CFrame.lookAt((hitData.origin + hitData.hitPosition) / 2, hitData.hitPosition)
	part.Color = weaponConfig.tracerColor or Color3.fromRGB(255, 200, 100)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.3
	part.Parent = Workspace

	task.spawn(function()
		for i = 1, 20 do
			part.Transparency = 0.3 + (i / 20) * 0.7
			task.wait(0.02)
		end
		part:Destroy()
	end)
end

function WeaponFX:ShowHitmarker(hitData)
	self._logService:Debug("WEAPON", "Hitmarker", { damage = hitData.damage, headshot = hitData.isHeadshot })
end

function WeaponFX:ShowDamageIndicator(hitData)
	self._logService:Debug("WEAPON", "Taking damage", { damage = hitData.damage })
end

return WeaponFX
