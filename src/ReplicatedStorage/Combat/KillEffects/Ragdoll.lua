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

local function resolveRootPosition(character)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return nil
	end

	local root = character:FindFirstChild("Root")
		or character.PrimaryPart
		or character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Torso")
		or character:FindFirstChildWhichIsA("BasePart", true)

	return root and root.Position or nil
end

local function randomHorizontalDirection()
	local angle = math.random() * math.pi * 2
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
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
function Ragdoll:Execute(victim: Player, killer: Player?, _weaponId: string?, _options: {[string]: any}?, context: {[string]: any}?)
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

	-- Build knockback direction
	local ragdollOptions = {}
	local sourcePosition = options.sourcePosition
	local hitPosition = options.hitPosition or resolveRootPosition(victimCharacter)

	-- If we didn't get hit-detection positions, fall back to live character locations.
	if typeof(sourcePosition) ~= "Vector3" and isPlayerInstance(killer) then
		sourcePosition = resolveRootPosition(killer.Character)
	end

	local launchDirection = nil
	if typeof(sourcePosition) == "Vector3" and typeof(hitPosition) == "Vector3" then
		local delta = hitPosition - sourcePosition
		if delta.Magnitude > 0.001 then
			launchDirection = delta.Unit
		end
	end

	local horizontalDirection = launchDirection
		and Vector3.new(launchDirection.X, 0, launchDirection.Z)
		or Vector3.zero

	-- If no valid horizontal direction, apply a random push so ragdolls still fling on death.
	if horizontalDirection.Magnitude <= 0.001 then
		horizontalDirection = randomHorizontalDirection()
	end

	ragdollOptions.Velocity = horizontalDirection.Unit * 95 + Vector3.new(0, 45, 0)

	if ragdollOptions.Velocity.Magnitude > 170 then
		ragdollOptions.Velocity = ragdollOptions.Velocity.Unit * 170
	end

	-- Real players use the existing player ragdoll path.
	if isPlayerInstance(victim) and characterService.Ragdoll then
		local ok = characterService:Ragdoll(victim, nil, ragdollOptions)
		if not ok then
			warn(string.format("[KillEffects/Ragdoll] CharacterService:Ragdoll returned false for %s", tostring(victim and victim.Name)))
		end
		return
	end

	-- Non-player victims (e.g. dummies) use model ragdoll.
	if characterService.RagdollCharacter then
		local ok = characterService:RagdollCharacter(victimCharacter, nil, ragdollOptions)
		if not ok then
			warn(string.format("[KillEffects/Ragdoll] RagdollCharacter returned false for %s", victimCharacter:GetFullName()))
		end
		return
	end

	warn("[KillEffects/Ragdoll] CharacterService missing RagdollCharacter for non-player victim")
end

return Ragdoll
