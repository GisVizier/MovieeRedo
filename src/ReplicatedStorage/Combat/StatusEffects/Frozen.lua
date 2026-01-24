--[[
	Frozen.lua
	Status effect that stops movement completely, applies low friction for sliding,
	and breaks when the player takes damage
	
	Settings:
	- duration: number (required)
	- friction: number? (default 0.02 for ice-like sliding)
	- breakOnDamage: boolean? (default true)
	- source: Player?
]]

local Frozen = {}
Frozen.Id = "Frozen"
Frozen.DefaultTickRate = 0.1

-- Store saved physics per player
local SavedPhysics = {}

--[[
	Called when the effect is first applied
	Disables movement and applies low friction
]]
function Frozen:OnApply(target: Player, settings, combatResource)
	local character = target.Character
	if not character then return end
	
	-- Set Frozen attribute - MovementController checks this to zero VectorForce
	-- (Already set by StatusEffectManager)
	
	-- Apply low friction for sliding effect
	local root = character:FindFirstChild("Root") or character.PrimaryPart
	if root and root:IsA("BasePart") then
		-- Save current physics
		SavedPhysics[target.UserId] = root.CustomPhysicalProperties
		
		-- Apply icy friction
		local friction = settings.friction or 0.02
		root.CustomPhysicalProperties = PhysicalProperties.new(
			0.7,      -- Density
			friction, -- Friction (very low = sliding)
			0,        -- Elasticity
			1,        -- FrictionWeight
			1         -- ElasticityWeight
		)
	end
	
	-- Set visual attribute for client VFX (ice particles, etc.)
	character:SetAttribute("FrozenVFX", true)
	
	-- Default breakOnDamage to true
	if settings.breakOnDamage == nil then
		settings.breakOnDamage = true
	end
end

--[[
	Called every tick while the effect is active
	Returns false if effect should be removed early (damage taken)
]]
function Frozen:OnTick(target: Player, settings, deltaTime: number, combatResource)
	-- Check if player took damage (set by StatusEffectManager:NotifyDamage)
	if settings.breakOnDamage and settings._damageTaken then
		return false -- Remove effect
	end
	
	return true -- Continue effect
end

--[[
	Called when the effect is removed
	Restores movement and original physics
]]
function Frozen:OnRemove(target: Player, settings, reason: string, combatResource)
	local character = target.Character
	if not character then return end
	
	-- Restore physics
	local root = character:FindFirstChild("Root") or character.PrimaryPart
	if root and root:IsA("BasePart") then
		local saved = SavedPhysics[target.UserId]
		if saved then
			root.CustomPhysicalProperties = saved
		else
			-- Restore default physics from config
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local ok, Config = pcall(function()
				local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
				return require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
			end)
			
			if ok and Config and Config.Gameplay and Config.Gameplay.Character then
				local physicsProps = Config.Gameplay.Character.CustomPhysicalProperties
				if physicsProps then
					root.CustomPhysicalProperties = PhysicalProperties.new(
						physicsProps.Density,
						physicsProps.Friction,
						physicsProps.Elasticity,
						physicsProps.FrictionWeight,
						physicsProps.ElasticityWeight
					)
				end
			end
		end
		SavedPhysics[target.UserId] = nil
	end
	
	-- Clear visual attribute
	character:SetAttribute("FrozenVFX", nil)
end

return Frozen
