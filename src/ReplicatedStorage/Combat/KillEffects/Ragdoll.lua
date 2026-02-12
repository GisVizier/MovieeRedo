--[[
	Ragdoll.lua
	Default kill effect — ragdoll physics on the victim

	Triggers a server-authoritative ragdoll via CharacterService,
	with directional knockback from the killer toward the victim.
]]

local Ragdoll = {}
Ragdoll.Id = "Ragdoll"
Ragdoll.Name = "Ragdoll"

local function isPlayerInstance(entity)
	return typeof(entity) == "Instance" and entity:IsA("Player")
end

local function getRootPosition(character)
	if not character then return nil end
	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function getDeterministicHorizontalDirection(victim, killer, victimCharacter)
	local victimPos = getRootPosition(victimCharacter)
	if victimPos and killer and killer.Character then
		local killerPos = getRootPosition(killer.Character)
		if killerPos then
			local delta = victimPos - killerPos
			local horiz = Vector3.new(delta.X, 0, delta.Z)
			if horiz.Magnitude > 0.001 then
				return horiz.Unit
			end
		end
	end
	if victimCharacter then
		local root = victimCharacter:FindFirstChild("Root") or victimCharacter:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local look = root.CFrame.LookVector
			local horiz = Vector3.new(look.X, 0, look.Z)
			if horiz.Magnitude > 0.001 then
				return horiz.Unit
			end
		end
	end
	return Vector3.new(1, 0, 0)
end

local function resolveCharacter(entity, fallbackCharacter)
	if typeof(fallbackCharacter) == "Instance" and fallbackCharacter:IsA("Model") then
		return fallbackCharacter
	end

	if isPlayerInstance(entity) then
		return entity.Character
	end

	if typeof(entity) == "Instance" and entity:IsA("Model") then
		return entity
	end

	if type(entity) == "table" then
		local character = rawget(entity, "Character")
		if typeof(character) == "Instance" and character:IsA("Model") then
			return character
		end
	end

	return nil
end

--[[
	Executes the ragdoll kill effect.
	@param victim Player - The player who died
	@param killer Player? - The player who caused the death
	@param _weaponId string? - The weapon used (unused)
	@param _options table? - Additional options (unused)
	@param context table? - Contains { registry } for service access
]]
function Ragdoll:Execute(
	victim: Player,
	killer: Player?,
	_weaponId: string?,
	_options: { [string]: any }?,
	context: { [string]: any }?
)
	local registry = context and context.registry
	if not registry then
		warn("[KillEffects/Ragdoll] No registry in context — cannot ragdoll")
		return
	end

	local characterService = registry:TryGet("CharacterService")
	if not characterService then
		warn("[KillEffects/Ragdoll] CharacterService not found in registry")
		return
	end

	local options = _options or {}
	local victimCharacter = resolveCharacter(victim, options.victimCharacter)
	if not victimCharacter then
		warn("[KillEffects/Ragdoll] Could not resolve victim character")
		return
	end

	-- Build knockback direction from where they were shot (source -> hit = push away from shooter)
	local ragdollOptions = {}
	local sourcePosition = options.sourcePosition
	local hitPosition = options.hitPosition

	-- Use victim/killer positions as fallbacks when shot data is partial
	if not sourcePosition and killer and killer.Character then
		sourcePosition = getRootPosition(killer.Character)
	end
	if not hitPosition and victimCharacter then
		hitPosition = getRootPosition(victimCharacter)
	end

	local launchDirection = nil
	local impactDirection = options.impactDirection
	if typeof(impactDirection) == "Vector3" and impactDirection.Magnitude > 0.001 then
		launchDirection = impactDirection.Unit
	end

	if not launchDirection and typeof(sourcePosition) == "Vector3" and typeof(hitPosition) == "Vector3" then
		local delta = hitPosition - sourcePosition
		if delta.Magnitude > 0.001 then
			launchDirection = delta.Unit
		end
	end

	local horizontalDirection = launchDirection and Vector3.new(launchDirection.X, 0, launchDirection.Z) or Vector3.zero

	-- If no valid horizontal direction, use full launchDirection (vertical shots) or deterministic fallback
	if horizontalDirection.Magnitude <= 0.001 then
		horizontalDirection = (launchDirection and launchDirection.Magnitude > 0.001 and launchDirection.Unit)
			or getDeterministicHorizontalDirection(victim, killer, victimCharacter)
	end

	ragdollOptions.Velocity = horizontalDirection.Unit * 95 + Vector3.new(0, 45, 0)

	if ragdollOptions.Velocity.Magnitude > 170 then
		ragdollOptions.Velocity = ragdollOptions.Velocity.Unit * 170
	end

	-- Real players use the existing player ragdoll path.
	if isPlayerInstance(victim) and characterService.Ragdoll then
		local ok = characterService:Ragdoll(victim, nil, ragdollOptions)
		if not ok then
			warn(
				string.format(
					"[KillEffects/Ragdoll] CharacterService:Ragdoll returned false for %s",
					tostring(victim and victim.Name)
				)
			)
		end
		return
	end

	-- Non-player victims (e.g. dummies) use model ragdoll.
	if characterService.RagdollCharacter then
		local ok = characterService:RagdollCharacter(victimCharacter, nil, ragdollOptions)
		if not ok then
			warn(
				string.format(
					"[KillEffects/Ragdoll] RagdollCharacter returned false for %s",
					victimCharacter:GetFullName()
				)
			)
		end
		return
	end

	warn("[KillEffects/Ragdoll] CharacterService missing RagdollCharacter for non-player victim")
end

return Ragdoll
