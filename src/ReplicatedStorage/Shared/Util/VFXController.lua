-- VFXController (client dispatcher)
--
-- Routes kit events to per-kit VFX modules:
--   Modules[kitId][effect][event](props)
--
-- Contract:
-- - Message is a `KitState` remote payload with:
--   - kind = "Event"
--   - kitId: string
--   - effect: string
--   - event: string
--   - extraData: { position = Vector3 }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXController = {}

VFXController._cache = {}

local function loadKitModule(kitId: string)
	if VFXController._cache[kitId] ~= nil then
		return VFXController._cache[kitId]
	end

	local root = ReplicatedStorage:FindFirstChild("KitSystem")
	local vfxFolder = root and root:FindFirstChild("VFX")
	local moduleScript = vfxFolder and vfxFolder:FindFirstChild(kitId)
	if not moduleScript then
		VFXController._cache[kitId] = false
		return nil
	end

	local ok, mod = pcall(require, moduleScript)
	if not ok or type(mod) ~= "table" then
		VFXController._cache[kitId] = false
		return nil
	end

	VFXController._cache[kitId] = mod
	return mod
end

function VFXController:Dispatch(message)
	if type(message) ~= "table" then
		return
	end
	if message.kind ~= "Event" then
		return
	end

	local kitId = message.kitId
	local effect = message.effect
	local eventName = message.event
	local extra = message.extraData

	if type(kitId) ~= "string" or type(effect) ~= "string" or type(eventName) ~= "string" then
		return
	end
	if type(extra) ~= "table" or typeof(extra.position) ~= "Vector3" then
		return
	end

	local kitModule = loadKitModule(kitId)
	if not kitModule then
		return
	end

	local effectTable = kitModule[effect]
	if type(effectTable) ~= "table" then
		return
	end

	local handler = effectTable[eventName]
	if type(handler) ~= "function" then
		return
	end

	handler({
		position = extra.position,
		playerId = message.playerId,
		kitId = kitId,
		effect = effect,
		event = eventName,
		abilityType = message.abilityType,
		raw = message,
	})
end

return VFXController
