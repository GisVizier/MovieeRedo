--[[
	Ragdoll.lua
	Default kill effect — ragdoll physics on the victim

	Triggers a server-authoritative ragdoll via CharacterService,
	with directional knockback from the killer toward the victim.
]]

local Ragdoll = {}
Ragdoll.Id = "Ragdoll"
Ragdoll.Name = "Ragdoll"

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

	-- Build knockback direction from killer toward victim
	local ragdollOptions = {}
	local victimChar = victim.Character
	local killerChar = killer and killer.Character

	if victimChar and killerChar then
		local victimRoot = victimChar:FindFirstChild("Root") or victimChar.PrimaryPart
		local killerRoot = killerChar:FindFirstChild("Root") or killerChar.PrimaryPart
		if victimRoot and killerRoot then
			local direction = (victimRoot.Position - killerRoot.Position).Unit
			ragdollOptions.Velocity = direction * 40 + Vector3.new(0, 30, 0)
		end
	end

	-- If no directional knockback (no killer, or missing roots),
	-- apply a random horizontal force so the ragdoll doesn't just sit in place
	if not ragdollOptions.Velocity then
		local angle = math.random() * math.pi * 2
		local horizontalForce = Vector3.new(math.cos(angle) * 20, 0, math.sin(angle) * 20)
		ragdollOptions.Velocity = horizontalForce + Vector3.new(0, 35, 0)
	end

	-- Ragdoll with no auto-recovery (server controls respawn timing)
	characterService:Ragdoll(victim, nil, ragdollOptions)
end

return Ragdoll
